import SwiftUI

@MainActor
/// The chat interface for host-owned navigation or presentation. Use `Reception.shared.openChat()` for the standard SDK sheet.
public struct ReceptionChatView: View {
    @Environment(\.colorScheme) private var inheritedScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isPresented) private var isPresented
    @State private var presentation = Presentation()
    public init() {}

    public var body: some View {
        let showsAsSheet = presentation.showsAsSheet(isPresented: isPresented)
        Group {
            if showsAsSheet {
                NavigationStack { ChatContent(showsSheetControls: true) }
                    .padding(.top, Theme.sheetTopInset)
                    .background(Theme.background)
                    .presentationDragIndicator(.visible)
                    .preferredColorScheme(Reception.resolvedAppearance.preferredColorScheme)
            }
            else {
                ChatContent(showsSheetControls: false)
                    .environment(\.colorScheme, Reception.resolvedAppearance.preferredColorScheme ?? inheritedScheme)
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
}

/// Whether the chat is its own sheet, settled on its first render. A sheet reports `isPresented` from the start;
/// a screen pushed through a navigation path reports it only after the push, and wrapping the chat in its own
/// navigation stack then makes SwiftUI pop it again.
@MainActor
private final class Presentation {
    private var settled: Bool?

    func showsAsSheet(isPresented: Bool) -> Bool {
        if let settled { return settled }
        settled = isPresented
        return isPresented
    }
}
