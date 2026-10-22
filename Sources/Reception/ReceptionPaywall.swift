import Foundation

public struct ReceptionPaywall: Sendable, Hashable {
    /// Where the paywall is built. Your team sees it beside the paywall in the dashboard. Any lowercase
    /// name works, so a vendor the SDK doesn't name yet can still be reported.
    public struct Source: RawRepresentable, Sendable, Hashable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static let revenueCat = Source(rawValue: "revenuecat")
        public static let superwall = Source(rawValue: "superwall")
        public static let adapty = Source(rawValue: "adapty")
        public static let app = Source(rawValue: "app")

        /// Lowercase letters, digits and hyphens, 1–32 characters, like the dashboard expects.
        internal var isValid: Bool {
            rawValue.range(of: "^[a-z0-9-]{1,32}$", options: .regularExpression) != nil
        }
    }

    /// A product the paywall sells, shown to your team in the dashboard.
    public struct Product: Sendable, Hashable {
        public let id: String
        /// The localized price, like "$4.99".
        public let price: String?
        /// The renewal period as an ISO 8601 duration, like "P1M"; nil for one-time purchases.
        public let period: String?
        /// The free trial as an ISO 8601 duration, like "P1W".
        public let trial: String?

        public init(id: String, price: String? = nil, period: String? = nil, trial: String? = nil) {
            self.id = id
            self.price = price
            self.period = period
            self.trial = trial
        }
    }

    public let id: String
    public let title: String
    public let source: Source?
    public let products: [Product]
    /// Whether a card can open it. `false` only lists it for your team, for example an offering without a
    /// paywall; it is always reported, never checked with `paywallAvailability`, and never sent as a card.
    public let presentable: Bool

    /// Kept as its own overload so unapplied references like `.map(ReceptionPaywall.init)` from 1.3 still compile.
    public init(id: String, title: String) {
        self.init(id: id, title: title, source: nil)
    }

    public init(id: String, title: String, source: Source? = nil, products: [Product] = [], presentable: Bool = true) {
        self.id = id
        self.title = title
        self.source = source
        self.products = products
        self.presentable = presentable
    }

    /// Bounds what products add to device requests, so a large catalog never pushes registration past the server's size limit.
    internal static let productBudget = 40

    internal static func validated(_ paywalls: [Self]) -> [Self] {
        var result: [Self] = []
        var ids: Set<String> = []
        var productBudget = Self.productBudget
        for paywall in paywalls {
            let id = paywall.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = paywall.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard result.count < 20, (1...64).contains(id.utf16.count),
                  id.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil,
                  (1...60).contains(title.utf16.count), ids.insert(id).inserted else {
                Log.debug("Invalid or duplicate paywall dropped")
                continue
            }
            let products = Array(Product.validated(paywall.products).prefix(productBudget))
            productBudget -= products.count
            // Details describe the paywall for the team only, so an invalid source is dropped instead of the paywall.
            let source = paywall.source?.isValid == true ? paywall.source : nil
            result.append(Self(id: id, title: title, source: source, products: products, presentable: paywall.presentable))
        }
        return result
    }

    /// The registration entry; source, products and the info-only flag are sent only when the app sets them.
    internal var payload: [String: Any] {
        var entry: [String: Any] = ["id": id, "title": title]
        if let source { entry["source"] = source.rawValue }
        if !products.isEmpty { entry["products"] = products.map(\.payload) }
        if !presentable { entry["presentable"] = false }
        return entry
    }
}

extension ReceptionPaywall.Product {
    /// Products describe the paywall for the team only, so a malformed detail is dropped instead of the paywall.
    static func validated(_ products: [Self]) -> [Self] {
        products.prefix(10).compactMap { product in
            let id = product.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...100).contains(id.utf16.count) else { return nil }
            let price = product.price?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Self(id: id, price: price.flatMap { (1...40).contains($0.utf16.count) ? $0 : nil },
                        period: product.period.flatMap(isoPeriod), trial: product.trial.flatMap(isoPeriod))
        }
    }

    var payload: [String: String] {
        var entry = ["id": id]
        entry["price"] = price
        entry["period"] = period
        entry["trial"] = trial
        return entry
    }

    private static func isoPeriod(_ value: String) -> String? {
        value.range(of: "^P([0-9]{1,3}[DWMY]){1,3}$", options: .regularExpression) != nil ? value : nil
    }
}
