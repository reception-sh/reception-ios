import StoreKit

/// Whether the person has paid access, read from the App Store on the device, so "Without a subscription" never
/// reaches someone who pays, even when the app doesn't report `subscription_status`. Nil until the first check.
@MainActor
internal final class PaidAccess {
    private(set) var current: Bool?
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
        let paid = await Self.hasPaidAccess()
        guard paid != current else { return }
        current = paid
        onChange?()
    }

    private func refresh() {
        check?.cancel()
        check = Task {
            let paid = await Self.hasPaidAccess()
            guard !Task.isCancelled, paid != current else { return }
            current = paid
            onChange?()
        }
    }

    /// A subscription (also in a trial or grace period), or a lifetime or non-renewing purchase. Family-shared access
    /// counts too: that person already has what an offer would sell.
    private static func hasPaidAccess() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.revocationDate == nil,
               [.autoRenewable, .nonRenewable, .nonConsumable].contains(transaction.productType) { return true }
        }
        return false
    }
}
