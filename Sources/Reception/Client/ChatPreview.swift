#if DEBUG && targetEnvironment(simulator)
import UIKit
import os

/// Lets a coding agent screenshot the chat without tapping the UI. Launched with `-ReceptionPreview welcome`, the app
/// opens the chat in its empty welcome state; with `-ReceptionPreview conversation`, it shows a short example
/// conversation. Both use local example data only: nothing is loaded, sent or cached, and the real chat history stays
/// untouched. Compiled only into debug simulator builds, so App Store builds never contain it.
@MainActor
enum ChatPreview {
    private static let logger = Logger(subsystem: "com.reception.sdk", category: "ChatPreview")
    private static var started = false

    static func startIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard !started, let flag = arguments.firstIndex(of: "-ReceptionPreview") else { return }
        started = true
        let state = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : ""
        guard state == "welcome" || state == "conversation" else {
            logger.error("[Reception] Chat preview failed: use welcome or conversation")
            return
        }
        let model = ChatModel(session: nil)
        if state == "conversation" {
            model.messages = exampleMessages()
            model.team = ["preview-agent": TeamMember(id: "preview-agent", name: "Alex", photoUrl: nil)]
        }
        Reception.shared.usePreviewChat(model)
        Task {
            let deadline = ContinuousClock.now + .seconds(30)
            while UIApplication.shared.applicationState != .active, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(200))
            }
            // Give the host's first screen time to appear before presenting above it.
            try? await Task.sleep(for: .seconds(1))
            Reception.shared.openChat()
            logger.notice("[Reception] Chat preview shown: \(state, privacy: .public)")
        }
    }

    private static func exampleMessages() -> [Message] {
        let now = Date()
        func message(_ id: String, _ sender: String, _ text: String, minutesAgo: Double) -> Message {
            Message(id: id, seq: nil, sender: sender, text: text, attachments: [],
                    createdAt: now.addingTimeInterval(-minutesAgo * 60),
                    authorId: sender == "AGENT" ? "preview-agent" : nil)
        }
        return [
            message("preview-1", "USER", "Hi! Quick question: can I use the app on my iPad too?", minutesAgo: 14),
            message("preview-2", "AGENT", "Hi! Yes, just sign in with the same account there.", minutesAgo: 12),
            message("preview-3", "USER", "Do I need to buy it again?", minutesAgo: 10),
            message("preview-4", "AGENT", "No, your purchase works on all your devices.", minutesAgo: 3),
            message("preview-5", "USER", "Perfect, thank you!", minutesAgo: 1),
        ]
    }
}
#endif
