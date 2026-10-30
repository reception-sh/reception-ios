import SwiftUI

/// The notification card or status line under the person's latest message.
internal struct PushPromptSlotView: View {
    let slot: PushPromptSlot
    let decline: () -> Void
    let accept: () -> Void

    var body: some View {
        switch slot {
        case .card(let prompt):
            card(prompt)
        case .status:
            belled(Theme.string("You'll get a notification when we reply."))
                .frame(maxWidth: .infinity)
        case .none:
            EmptyView()
        }
    }

    private func card(_ prompt: PushPrompt) -> some View {
        VStack(spacing: Theme.pushPromptSpacing) {
            belled(text(for: prompt))
            // Equal buttons, so the choice is not nudged before the system asks.
            HStack(spacing: Theme.pushPromptButtonSpacing) {
                button(Theme.string("No thanks"), action: decline)
                button(Theme.string("Continue"), action: accept)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.pushPromptVertical)
        .accessibilityElement(children: .contain)
    }

    /// The bell sits inside the text, so a sentence that wraps stays centered line by line.
    private func belled(_ text: String) -> some View {
        Text("\(Image(systemName: "bell.fill")) \(text)")
            .font(Theme.footnoteFont)
            .foregroundStyle(Theme.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(text)
    }

    private func text(for prompt: PushPrompt) -> String {
        switch prompt {
        case .replies: Theme.string("Get a notification when we reply.")
        case .offers: Theme.string("Get notifications for replies, offers and updates.")
        }
    }

    private func button(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.footnoteFont.weight(.semibold))
                .foregroundStyle(Reception.resolvedAppearance.accentColor)
                .frame(minHeight: Theme.pushPromptButtonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
