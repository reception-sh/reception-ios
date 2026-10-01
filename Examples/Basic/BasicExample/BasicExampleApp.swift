import SwiftUI
import Reception

@main
struct BasicExampleApp: App {
    @State private var deletion = DataDeletion()
    init() {
        PaywallPresentation.configure()
        #if DEBUG
        Reception.logLevel = .debug
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-ReceptionLanguage"), arguments.indices.contains(index + 1) {
            Reception.shared.languageOverride = arguments[index + 1]
        }
        #endif
        #if DEBUG && targetEnvironment(simulator)
        if let scenario = CooldownScenario.launch {
            CooldownFixture.start(scenario)
            return
        }
        #endif
        // Replace with the App ID from your Reception dashboard.
        Reception.configure(appId: "app_YOUR_APP_ID")
    }

    /// Screenshots of fixture scenarios say plainly that the service replies are simulated.
    @ViewBuilder private var fixtureLabel: some View {
        #if DEBUG && targetEnvironment(simulator)
        if let scenario = CooldownScenario.launch {
            Text(verbatim: "Cooldown fixture \(scenario.rawValue): simulated service replies, not backend enforcement.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack {
                    ContentUnavailableView("Welcome", systemImage: "hand.wave",
                                           description: Text("We are here to help. Open support in Settings."))
                        .navigationTitle("Home")
                        .safeAreaInset(edge: .bottom) { fixtureLabel }
                }.tabItem { Label("Home", systemImage: "house") }
                NavigationStack {
                    List {
                        Section("Language") {
                            Picker("Reception language", selection: Binding(
                                get: { Reception.shared.languageOverride ?? "automatic" },
                                set: { Reception.shared.languageOverride = $0 == "automatic" ? nil : $0 }
                            )) {
                                Text("Automatic (app language)").tag("automatic")
                                Text("English").tag("en")
                                Text("Deutsch").tag("de")
                                Text("Français (Canada)").tag("fr-CA")
                                Text("Español (México)").tag("es-MX")
                                Text("Português (Portugal)").tag("pt-PT")
                                Text("繁體中文 (香港)").tag("zh-HK")
                                Text("العربية").tag("ar")
                            }
                            .accessibilityIdentifier("reception-language-picker")
                        }
                        Section("Help") {
                            Button("Delete my data", role: .destructive) { deletion.delete() }
                                .disabled(deletion.isDeleting)
                            if let error = deletion.error { Text(error).foregroundStyle(.secondary) }
                            Button { Reception.shared.openChat() } label: {
                                HStack {
                                    Text("Support")
                                    Spacer()
                                    if Reception.shared.unreadCount > 0 {
                                        Text(Reception.shared.unreadCount, format: .number)
                                    }
                                }
                            }
                        }
                    }
                        .navigationTitle("Settings")
                }.tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .task {
                #if DEBUG && targetEnvironment(simulator)
                if CooldownScenario.launch != nil { Reception.shared.openChat() }
                #endif
            }
        }
    }
}
