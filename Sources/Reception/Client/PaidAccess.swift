import StoreKit

/// Whether the person has paid access, read from the App Store on the device, so "Without a subscription" never
/// reaches someone who pays, even when the app doesn't report `subscription_status`. Nil until the first check.
@MainActor
internal final class PaidAccess {
    private(set) var current: Bool?
    /// The `originalID`s of the paid entitlements as decimal strings, sorted and at most 20, so App Store Server
    /// Notifications the service receives can be tied to the person. Nil until the first check.
    private(set) var transactionIds: [String]?
    private var check: Task<Void, Never>?
    private var updates: Task<Void, Never>?
    private var onChange: (() -> Void)?

    /// Checks now, and again for every purchase or refund while the app runs, so a delayed automation sees a
    /// purchase made after the event that started it.
    func start(onChange: @escaping () -> Void) {
        self.onChange = onChange
        if updates == nil {
            updates = Task { [weak self] in
                for await _ in Transaction.updates { self?.refresh() }
            }
        }
        refresh()
    }

    /// Checks now and waits for the answer, for decisions that must not rest on an older one: a purchase made through
    /// `Product.purchase()` or a store view never arrives in `Transaction.updates`.
    func refreshNow() async {
        check?.cancel()
        apply(await Self.paidEntitlements())
    }

    private func refresh() {
        check?.cancel()
        check = Task {
            let originalIDs = await Self.paidEntitlements()
            guard !Task.isCancelled else { return }
            apply(originalIDs)
        }
    }

    /// Internal for tests.
    func apply(_ originalIDs: Set<UInt64>) {
        let paid = !originalIDs.isEmpty
        let ids = originalIDs.sorted().prefix(20).map(String.init)
        guard paid != current || ids != transactionIds else { return }
        current = paid
        transactionIds = ids
        onChange?()
    }

    /// The original transaction IDs of subscriptions (also in a trial or grace period) and lifetime or non-renewing
    /// purchases. Family-shared access counts too: that person already has what an offer would sell.
    private static func paidEntitlements() async -> Set<UInt64> {
        var originalIDs = Set<UInt64>()
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.revocationDate == nil,
               [.autoRenewable, .nonRenewable, .nonConsumable].contains(transaction.productType) {
                originalIDs.insert(transaction.originalID)
            }
        }
        return originalIDs
    }
}
