import SwiftUI

@MainActor
/// The chat interface for host-owned navigation or presentation. Use `Reception.shared.openChat()` for the standard SDK sheet.
public struct ReceptionChatView: View {
    @Environment(\.colorScheme) private var inheritedScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isPresented) private var isPresented
    public init() {}

    public var body: some View {
        Group {
            if isPresented {
                NavigationStack { content }
                    .padding(.top, Theme.sheetTopInset)
                    .background(Theme.background)
                    .presentationDragIndicator(.visible)
                    .preferredColorScheme(Reception.resolvedAppearance.preferredColorScheme)
            }
            else {
                content.environment(\.colorScheme, Reception.resolvedAppearance.preferredColorScheme ?? inheritedScheme)
            }
        }.id(Reception.shared.revision)
        .environment(\.locale, ReceptionLocalization.locale)
        .environment(\.layoutDirection, ReceptionLocalization.layoutDirection)
        .onAppear { Reception.shared.appearanceConfiguration.activate() }
        .task(id: "\(scenePhase)-\(Reception.shared.revision)-\(Reception.shared.usesRemoteAppearance)") {
            if scenePhase == .active && Reception.shared.usesRemoteAppearance {
                await Reception.shared.appearanceConfiguration.refreshWhileActive()
            }
        }
    }
    private var content: some View {
        ChatContent()
    }
}
