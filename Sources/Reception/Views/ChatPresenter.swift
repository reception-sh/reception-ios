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
        // A downward swipe over the messages while typing dismisses the keyboard, never the whole sheet: the sheet
        // refuses interactive dismissal while the keyboard is up and allows it again as soon as it is gone.
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillShow() { hostingController?.isModalInPresentation = true }
    @objc private func keyboardWillHide() { hostingController?.isModalInPresentation = false }

    /// Presents the chat, or arranges for it: after a dismissal in progress, or once a window is active. Answers
    /// false only when another screen is still opening, so a caller that can wait tries again.
    @discardableResult
    func present() -> Bool {
        if dismissing {
            presentAfterDismiss = true
            return true
        }
        guard !Reception.shared.isChatOpen, hostingController == nil else {
            presentationPending = false
            Log.debug("Chat presentation skipped, chat already open")
            return true
        }
        guard let presentingController else {
            presentationPending = true
            Log.debug("Chat presentation deferred, no active window")
            return true
        }
        // A screen that is still opening owns this moment; the chat would only fight it.
        guard !presentingController.isBeingPresented else {
            presentationPending = false
            Log.debug("Chat presentation skipped, another screen is being presented")
            return false
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
        return true
    }

    /// Whether the chat can open right now: the app is active and no screen in front is still opening or closing.
    /// A cancelled purchase is reported while the App Store sheet is still closing, and a closed paywall often
    /// comes straight back, so an automation waits for this before it opens the chat.
    var isSettled: Bool {
        guard UIApplication.shared.applicationState == .active else { return false }
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        guard let front = controller else { return true }
        return !front.isBeingPresented && !front.isBeingDismissed
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

    private var window: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return nil }
        return scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
    }

    private var presentingController: UIViewController? {
        var controller = window?.rootViewController
        // A paywall that is closing cannot present: the chat would vanish with it.
        while let presented = controller?.presentedViewController, !presented.isBeingDismissed { controller = presented }
        return controller
    }
}
