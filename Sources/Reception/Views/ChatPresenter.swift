import SwiftUI
import UIKit

@MainActor
internal final class ChatPresenter: NSObject, UIAdaptivePresentationControllerDelegate {
    private weak var hostingController: UIViewController?
    private var presentationPending = false
    private var dismissing = false
    private var dismissalCompleted = false
    private var presentAfterDismiss = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(retryPresentation),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(retryPresentation),
            name: UIScene.didActivateNotification, object: nil)
    }

    func present() {
        if dismissing {
            presentAfterDismiss = true
            return
        }
        guard !Reception.shared.isChatOpen, hostingController == nil else {
            presentationPending = false
            Log.debug("Chat presentation skipped, chat already open")
            return
        }
        guard let presentingController else {
            presentationPending = true
            Log.debug("Chat presentation deferred, no active window")
            return
        }

        presentationPending = false
        Reception.shared.appearanceConfiguration.activate()
        let controller = UIHostingController(rootView: ReceptionChatView())
        controller.modalPresentationStyle = .pageSheet
        controller.sheetPresentationController?.prefersGrabberVisible = true
        if let colorScheme = Reception.resolvedAppearance.preferredColorScheme {
            controller.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        } else {
            controller.overrideUserInterfaceStyle = .unspecified
        }
        controller.presentationController?.delegate = self
        hostingController = controller
        presentingController.present(controller, animated: true) {
            if self.hostingController === controller { Log.debug("Chat presented") }
        }
    }

    @discardableResult
    func dismiss() -> Bool {
        presentationPending = false
        presentAfterDismiss = false
        guard let controller = hostingController else { return false }
        dismissing = true
        dismissalCompleted = false
        controller.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.dismissalCompleted = true
            self.finishDismissalIfReady()
        }
        hostingController = nil
        Log.debug("Chat dismissed")
        return true
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController === hostingController else { return }
        hostingController = nil
        Log.debug("Chat dismissed")
    }

    func chatDidDisappear() {
        finishDismissalIfReady()
    }

    private func finishDismissalIfReady() {
        // SwiftUI can clear chat visibility after UIKit's dismissal completion.
        guard dismissing, dismissalCompleted, !Reception.shared.isChatOpen else { return }
        dismissing = false
        if presentAfterDismiss {
            presentAfterDismiss = false
            present()
        }
    }

    @objc private func retryPresentation() {
        guard presentationPending else { return }
        present()
    }

    private var presentingController: UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first else { return nil }
        var controller = window.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}
