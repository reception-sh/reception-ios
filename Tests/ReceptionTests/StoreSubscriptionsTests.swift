import XCTest
@testable import Reception

final class StoreSubscriptionsTests: XCTestCase {
    func testOnlyAChangeIsReported() {
        XCTAssertNil(StoreSubscriptions.event(from: nil, to: .trialCancelled))
        XCTAssertNil(StoreSubscriptions.event(from: nil, to: .expired))
        XCTAssertNil(StoreSubscriptions.event(from: .cancelled, to: .cancelled))
    }

    func testEachChangeMapsToItsEvent() {
        XCTAssertEqual(StoreSubscriptions.event(from: .trial, to: .trialCancelled), "trial_cancelled")
        XCTAssertEqual(StoreSubscriptions.event(from: .active, to: .cancelled), "subscription_cancelled")
        // A trial that turned paid and was then cancelled between two checks.
        XCTAssertEqual(StoreSubscriptions.event(from: .trial, to: .cancelled), "subscription_cancelled")
        XCTAssertEqual(StoreSubscriptions.event(from: .active, to: .billingIssue), "billing_issue")
        XCTAssertEqual(StoreSubscriptions.event(from: .trialCancelled, to: .expired), "subscription_expired")
        XCTAssertEqual(StoreSubscriptions.event(from: .billingIssue, to: .expired), "subscription_expired")
    }

    func testRenewingAgainOrResubscribingIsNotAnEvent() {
        XCTAssertNil(StoreSubscriptions.event(from: .trialCancelled, to: .trial))
        XCTAssertNil(StoreSubscriptions.event(from: .billingIssue, to: .active))
        XCTAssertNil(StoreSubscriptions.event(from: .expired, to: .active))
        XCTAssertNil(StoreSubscriptions.event(from: .trial, to: .active))
    }

    @MainActor func testEveryReportedEventIsListedAndValid() {
        let states: [SubscriptionState] = [.trial, .trialCancelled, .active, .cancelled, .billingIssue, .expired]
        let events = Set(states.flatMap { old in states.compactMap { StoreSubscriptions.event(from: old, to: $0) } })
        XCTAssertEqual(events, StoreSubscriptions.events)
        XCTAssertTrue(events.allSatisfy(Automations.accepts))
    }

    @MainActor func testStatesAreRememberedPerSubscriptionGroup() {
        let store = DeviceStore(scope: "test.subscriptions.\(UUID().uuidString)")
        XCTAssertEqual(store.subscriptionStates, [:])
        store.subscriptionStates = ["group": .trialCancelled]
        XCTAssertEqual(store.subscriptionStates, ["group": .trialCancelled])
    }
}
