import XCTest
@testable import Reception

@MainActor
final class CooldownRecheckTests: XCTestCase {
    private let time = TestTime()

    private func makeStore(scope: String) -> DeviceStore {
        DeviceStore(scope: scope, credentialStorage: .init(read: { _ in .missing }, save: { _, _ in true }, delete: { _ in true }))
    }

    private func limits(_ json: String) throws -> ConversationResponse.Limits {
        try JSONDecoder().decode(ConversationResponse.Limits.self, from: Data(json.utf8))
    }

    func testCheckSpacingSurvivesRecreationAndFailedAttempts() {
        let store = makeStore(scope: "recheck-" + UUID().uuidString)
        let first = ServerCooldowns(store: store, now: { self.time.now })
        first.impose(.messages, seconds: 3600)
        XCTAssertEqual(Set(first.beginRecheck().keys), [.messages])
        XCTAssertTrue(first.beginRecheck().isEmpty)
        first.invalidate()

        let relaunched = ServerCooldowns(store: store, now: { self.time.now })
        defer { relaunched.invalidate(); store.clear() }
        time.now.addTimeInterval(59)
        XCTAssertTrue(relaunched.beginRecheck().isEmpty, "No answer was needed to spend the interval")
        time.now.addTimeInterval(1)
        XCTAssertEqual(Set(relaunched.beginRecheck().keys), [.messages])
        time.now.addTimeInterval(-600)
        XCTAssertTrue(relaunched.beginRecheck().isEmpty)
        time.now.addTimeInterval(60)
        XCTAssertFalse(relaunched.beginRecheck().isEmpty, "A clock change cannot hold checks indefinitely")
    }

    func testChecksOnlyLongMessagesAndUploadsAndLeavesShortenedWaitManual() throws {
        let store = makeStore(scope: "recheck-" + UUID().uuidString)
        let waits = ServerCooldowns(store: store, now: { self.time.now })
        defer { waits.invalidate(); store.clear() }
        waits.impose(.messages, seconds: 60)
        waits.impose(.uploads, seconds: 3600)
        waits.impose(.session, seconds: 600)
        waits.impose(.stream, seconds: 60)
        let check = waits.beginRecheck()
        XCTAssertEqual(Set(check.keys), [.uploads])
        waits.applyRecheck(try limits(#"{"messages":0,"uploads":30}"#), checked: check)
        XCTAssertNotNil(waits.blocking([.messages]), "An unchecked scope cannot be released")
        XCTAssertEqual(waits.blocking([.uploads])?.until, time.now.addingTimeInterval(30))
        XCTAssertEqual(waits.blocking([.uploads])?.automatic, false)
        XCTAssertNotNil(waits.blocking([.session]))
    }

    func testNewRejectionEvenWithSameDeadlineRejectsOldAnswerPerScope() throws {
        let store = makeStore(scope: "recheck-" + UUID().uuidString)
        let waits = ServerCooldowns(store: store, now: { self.time.now })
        defer { waits.invalidate(); store.clear() }
        waits.impose(.messages, seconds: 3600)
        waits.impose(.uploads, seconds: 3600)
        let check = waits.beginRecheck()
        waits.impose(.messages, seconds: 3600)
        waits.applyRecheck(try limits(#"{"messages":0,"uploads":0}"#), checked: check)
        XCTAssertNotNil(waits.blocking([.messages]))
        XCTAssertNil(waits.blocking([.uploads]))
    }

    func testMissingInvalidOrUnrequestedResultsNeverReleaseAWait() throws {
        for json in [#"{}"#, #"{"messages":null}"#, #"{"messages":false}"#,
                     #"{"messages":"0"}"#, #"{"messages":-1}"#, #"{"messages":86401}"#,
                     #"{"messages":0.5}"#] {
            let store = makeStore(scope: "recheck-" + UUID().uuidString)
            let waits = ServerCooldowns(store: store, now: { self.time.now })
            waits.impose(.messages, seconds: 3600)
            let check = waits.beginRecheck()
            waits.applyRecheck(try limits(json), checked: check)
            XCTAssertNotNil(waits.blocking([.messages]), json)
            waits.applyRecheck(try limits(#"{"messages":0}"#), checked: [:])
            XCTAssertNotNil(waits.blocking([.messages]))
            waits.invalidate(); store.clear()
        }
    }

    func testScopesAndSessionResetKeepIndependentCheckIntervals() {
        let firstStore = makeStore(scope: "first-" + UUID().uuidString)
        let secondStore = makeStore(scope: "second-" + UUID().uuidString)
        let first = ServerCooldowns(store: firstStore, now: { self.time.now })
        let second = ServerCooldowns(store: secondStore, now: { self.time.now })
        defer { first.invalidate(); second.invalidate(); firstStore.clear(); secondStore.clear() }
        first.impose(.messages, seconds: 3600)
        second.impose(.messages, seconds: 3600)
        XCTAssertFalse(first.beginRecheck().isEmpty)
        XCTAssertFalse(second.beginRecheck().isEmpty)
        firstStore.clear()
        XCTAssertNil(firstStore.lastLimitCheck)
    }
}
