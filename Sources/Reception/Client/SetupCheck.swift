#if DEBUG && targetEnvironment(simulator)
import UIKit
import os

/// Lets a coding agent prove a new integration without tapping the UI. Launched with
/// `-ReceptionSetupCheck <App ID>`, the app sends "Hello from setup" once through the normal send path and logs whether
/// Reception accepted it. Compiled only into debug simulator builds, so App Store builds never contain it.
@MainActor
enum SetupCheck {
    static let text = "Hello from setup"
    // Its own logger keeps the result readable when the host silences or redirects the SDK's logs.
    private static let logger = Logger(subsystem: "com.reception.sdk", category: "SetupCheck")
    private static var started = false

    static func startIfRequested(configuredAppId: String) {
        let arguments = ProcessInfo.processInfo.arguments
        guard !started, let flag = arguments.firstIndex(of: "-ReceptionSetupCheck") else { return }
        started = true
        guard arguments.indices.contains(flag + 1), arguments[flag + 1] == configuredAppId else {
            report(passed: false, "app_id_mismatch")
            return
        }
        Task { await run() }
    }

    private static func run() async {
        logger.notice("[Reception] Setup check started")
        let deadline = ContinuousClock.now + .seconds(60)
        while UIApplication.shared.applicationState != .active {
            guard ContinuousClock.now < deadline else { return report(passed: false, "app_not_active") }
            try? await Task.sleep(for: .milliseconds(200))
        }
        let chat = Reception.shared.chatModel()
        let earlier = Set(chat.messages.map(\.id))
        chat.send(text: text, images: [])
        // The send guards (verified-only apps, blocked devices, cooldowns) return without adding a message.
        guard let id = chat.messages.first(where: { !earlier.contains($0.id) })?.id else {
            return report(passed: false, "send_not_allowed")
        }
        while ContinuousClock.now < deadline {
            // A confirmed message carries the draft's ID as its client ID.
            switch Reception.shared.chatModel().messages.first(where: { $0.id == id || $0.clientId == id })?.status {
            case .sent?: return report(passed: true, nil)
            case .failed?: return report(passed: false, "not_delivered")
            default: try? await Task.sleep(for: .milliseconds(200))
            }
        }
        report(passed: false, "timeout")
    }

    private static func report(passed: Bool, _ reason: String?) {
        if passed {
            logger.notice("[Reception] Setup check passed")
        } else {
            logger.error("[Reception] Setup check failed: \(reason ?? "unknown", privacy: .public)")
        }
    }
}
#endif
