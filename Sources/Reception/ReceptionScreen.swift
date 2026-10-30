import Foundation

/// A place in your app that a link card can open: a tab, a screen, a sheet, the paywall, anything your code can show.
/// List them in `Reception.shared.screens`; the dashboard then offers them by name, and only people whose app version
/// has a screen get links to it.
///
/// ```swift
/// Reception.shared.screens = [
///     ReceptionScreen("settings") { tab = .settings },
///     ReceptionScreen("order", value: "Order number") { number in path = [.order(number)] },
/// ]
/// ```
///
/// The SDK closes the chat it presented, then runs `open` on the main actor. An ID uses letters, digits, `_`, `-` or `.`,
/// at most 64 characters, and starts with a letter or digit; IDs that don't, and repeated IDs, are ignored.
public struct ReceptionScreen {
    /// The name the dashboard shows and links use, such as `settings`.
    public let id: String
    /// What the value is called in the dashboard, such as "Order number"; nil when the screen takes none.
    public let valueName: String?
    let open: @MainActor (String?) -> Void

    /// A screen that opens the same way every time.
    @MainActor public init(_ id: String, open: @escaping @MainActor () -> Void) {
        self.id = id
        valueName = nil
        self.open = { _ in open() }
    }

    /// A screen that needs a value from the link, such as an order number. `value` names it for the team, and every
    /// link to this screen carries one.
    @MainActor public init(_ id: String, value: String, open: @escaping @MainActor (String) -> Void) {
        self.id = id
        valueName = value
        self.open = { value in if let value { open(value) } }
    }
}

/// A link card that opens one of the host's screens: `reception-screen:<id>`, with `?value=<value>` for a screen that
/// takes one.
internal struct ScreenLink: Equatable {
    static let scheme = "reception-screen"
    /// At most this many screens are reported and opened.
    static let limit = 50

    let id: String
    let value: String?

    init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              Self.isValidId(components.path) else { return nil }
        id = components.path
        value = components.queryItems?.first { $0.name == "value" }?.value.flatMap { $0.isEmpty ? nil : $0 }
    }

    static func isValidId(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$", options: .regularExpression) != nil
    }

    /// The screens the host listed that can be opened: valid IDs, each once (the first wins), at most `limit`.
    @MainActor static func usable(_ screens: [ReceptionScreen]) -> [ReceptionScreen] {
        var seen = Set<String>()
        return Array(screens.filter { isValidId($0.id) && seen.insert($0.id).inserted }.prefix(limit))
    }

    /// The screens as the service stores them for this device.
    @MainActor static func report(_ screens: [ReceptionScreen]) -> [[String: String]] {
        usable(screens).map { screen in
            var entry = ["id": screen.id]
            if let valueName = screen.valueName { entry["value"] = String(valueName.prefix(40)) }
            return entry
        }
    }
}
