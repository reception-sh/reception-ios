import SafariServices
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Lets each touch decide whether the sheet may be dragged away. With the keyboard up, only a touch that begins on
/// the header may; one over the messages scrolls them or puts the keyboard away instead. With the keyboard down,
/// every drag may, like any sheet. It never recognizes anything itself and recognizes alongside every other gesture,
/// so it sees each touch through to its end.
@MainActor
private final class SheetHandleRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    weak var sheet: UIViewController?
    private var keyboardVisible = false

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillShow() { keyboardVisible = true }
    @objc private func keyboardWillHide() { keyboardVisible = false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first, let view else { return }
        let onHeader = ChatPresenter.isSheetHandle(touchStartingAt: touch.location(in: view).y)
        sheet?.isModalInPresentation = ChatPresenter.locksSheet(keyboardVisible: keyboardVisible, onHeader: onHeader)
        // With the keyboard up, iOS spends the first drag on putting it away; ending editing here lets one drag close.
        if keyboardVisible && onHeader { view.endEditing(true) }
    }

    // A touch on the grabber never reaches this view, so between touches the sheet stays draggable.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        sheet?.isModalInPresentation = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        sheet?.isModalInPresentation = false
    }

    override func reset() { sheet?.isModalInPresentation = false }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

@MainActor
internal final class ChatPresenter: NSObject, UIAdaptivePresentationControllerDelegate {
    private weak var hostingController: UIViewController?
    private let sheetHandle = SheetHandleRecognizer()
    private var presentationPending = false
    private var dismissing = false
    private var dismissalCompleted = false
    private var presentAfterDismiss = false
    /// Runs once UIKit and SwiftUI both consider the chat gone, so `isChatOpen` is already false.
    private var afterDismissal: (() -> Void)?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(retryPresentation),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(retryPresentation),
            name: UIScene.didActivateNotification, object: nil)
    }

    /// Whether a touch began on the header: the grabber inset and the title bar.
    static func isSheetHandle(touchStartingAt y: CGFloat) -> Bool {
        y <= Theme.sheetHandleHeight
    }

    /// While the keyboard is up, only a drag from the header closes the sheet; one over the messages scrolls them or
    /// dismisses the keyboard. With the keyboard down, a drag anywhere closes it, like any sheet.
    static func locksSheet(keyboardVisible: Bool, onHeader: Bool) -> Bool {
        keyboardVisible && !onHeader
    }

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
        sheetHandle.sheet = controller
        controller.view.addGestureRecognizer(sheetHandle)
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

    /// Answers false, without calling `completion`, when the SDK has not presented the chat.
    @discardableResult
    func dismiss(completion: (() -> Void)? = nil) -> Bool {
        presentationPending = false
        presentAfterDismiss = false
        guard let controller = hostingController else { return false }
        dismissing = true
        dismissalCompleted = false
        afterDismissal = completion
        controller.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.dismissalCompleted = true
            self.finishDismissalIfReady()
        }
        hostingController = nil
        Log.debug("Chat dismissed")
        return true
    }

    /// Shows a web page in Safari as a sheet in front: over the chat the SDK presented, so Done returns to it, or over
    /// the front screen for a host-embedded chat or after the chat closed. False when no screen can present right now.
    func presentWebPage(_ url: URL) -> Bool {
        guard let front = frontController(from: hostingController ?? window?.rootViewController),
              !front.isBeingPresented else { return false }
        let safari = SFSafariViewController(url: url)
        safari.modalPresentationStyle = .pageSheet
        front.present(safari, animated: true)
        Log.debug("Web page presented")
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
        let next = afterDismissal
        afterDismissal = nil
        next?()
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

    private var presentingController: UIViewController? { frontController(from: window?.rootViewController) }

    private func frontController(from root: UIViewController?) -> UIViewController? {
        var controller = root
        // A paywall that is closing cannot present: the chat would vanish with it.
        while let presented = controller?.presentedViewController, !presented.isBeingDismissed { controller = presented }
        return controller
    }
}
