import StoreKit

/// What the App Store says about one subscription the person bought, reduced to what automations react to.
internal enum SubscriptionState: String {
    case trial, trialCancelled, active, cancelled, billingIssue, expired
}

/// Reads subscription changes from the App Store on the device, so automations can react to a cancelled trial or a
/// failed payment without the app writing code or a server receiving App Store notifications.
internal enum StoreSubscriptions {
    /// Events Reception reports on its own; the app never needs to track them.
    static let events: Set<String> = [
        "trial_cancelled", "trial_expired", "subscription_cancelled", "subscription_expired", "billing_issue",
    ]

    /// The event a change from `old` to `new` means. A subscription seen for the first time is only remembered,
    /// so updating the SDK never reports old history. A trial that runs out never was paid, so it has its own event.
    static func event(from old: SubscriptionState?, to new: SubscriptionState) -> String? {
        guard let old, old != new else { return nil }
        switch new {
        case .trialCancelled: return old == .trial ? "trial_cancelled" : nil
        case .cancelled: return old == .expired ? nil : "subscription_cancelled"
        case .billingIssue: return old == .expired ? nil : "billing_issue"
        case .expired: return old == .trial || old == .trialCancelled ? "trial_expired" : "subscription_expired"
        case .trial, .active: return nil
        }
    }

    /// The current state of every subscription group the person bought into, by group ID. Family-shared access is
    /// left out: the person who shares it decides about renewing, not this one.
    static func current() async -> [String: SubscriptionState] {
        var groups: Set<String> = []
        for await result in Transaction.all {
            if case .verified(let transaction) = result, transaction.productType == .autoRenewable,
               transaction.ownershipType == .purchased, let group = transaction.subscriptionGroupID {
                groups.insert(group)
            }
        }
        var states: [String: SubscriptionState] = [:]
        for group in groups {
            guard let statuses = try? await Product.SubscriptionInfo.status(for: group) else { continue }
            states[group] = statuses.lazy.compactMap(state).first
        }
        return states
    }

    private static func state(of status: Product.SubscriptionInfo.Status) -> SubscriptionState? {
        guard case .verified(let transaction) = status.transaction, transaction.ownershipType == .purchased,
              case .verified(let renewal) = status.renewalInfo else { return nil }
        switch status.state {
        case .subscribed:
            let trial = isFreeTrial(transaction)
            if renewal.willAutoRenew { return trial ? .trial : .active }
            return trial ? .trialCancelled : .cancelled
        case .inGracePeriod, .inBillingRetryPeriod: return .billingIssue
        case .expired, .revoked: return .expired
        default: return nil
        }
    }

    private static func isFreeTrial(_ transaction: Transaction) -> Bool {
        if #available(iOS 17.2, *) { return transaction.offer?.paymentMode == .freeTrial }
        return transaction.offerType == .introductory
    }
}
