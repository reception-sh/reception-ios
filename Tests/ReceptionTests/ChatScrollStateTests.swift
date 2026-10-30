import XCTest
@testable import Reception

final class ChatScrollStateTests: XCTestCase {
    func testRepliesFollowAReaderAtTheNewestMessage() {
        var state = opened()
        XCTAssertTrue(state.messagesChanged(entries("a", "b", "c:AGENT", "d:AI")))
        XCTAssertEqual(state.unseenCount, 0)
        XCTAssertFalse(state.showsJumpControl)
    }

    func testRepliesAreCountedWhileTheReaderIsFurtherUp() {
        var state = scrolledUp()
        XCTAssertFalse(state.messagesChanged(entries("a", "b", "c:AGENT")))
        XCTAssertFalse(state.messagesChanged(entries("a", "b", "c:AGENT", "d:AUTOMATION", "e:AI")))
        XCTAssertEqual(state.unseenCount, 3)
        XCTAssertTrue(state.showsJumpControl)
        XCTAssertFalse(state.followsNewest)
    }

    func testControlOnlyAppearsWithUnseenReplies() {
        let state = scrolledUp()
        XCTAssertFalse(state.followsNewest)
        XCTAssertFalse(state.showsJumpControl)
    }

    func testReloadDoesNotCountTwiceOrCountOlderMessages() {
        var state = scrolledUp()
        _ = state.messagesChanged(entries("a", "b", "c:AGENT"))
        // A reload returns the same reply, fills in an older message and drops a stale cached one.
        XCTAssertFalse(state.messagesChanged(entries("older:AGENT", "a", "c:AGENT")))
        XCTAssertEqual(state.unseenCount, 1)
        XCTAssertFalse(state.messagesChanged(entries("older:AGENT", "a", "c:AGENT", "d:AGENT")))
        XCTAssertEqual(state.unseenCount, 2)
    }

    func testRemovedRepliesLeaveTheCount() {
        var state = scrolledUp()
        _ = state.messagesChanged(entries("a", "b", "c:AGENT", "d:AGENT"))
        _ = state.messagesChanged(entries("a", "b", "d:AGENT"))
        XCTAssertEqual(state.unseenCount, 1)
    }

    func testOwnMessageAlwaysScrollsAndClearsTheCount() {
        var state = scrolledUp()
        _ = state.messagesChanged(entries("a", "b", "c:AGENT"))
        XCTAssertTrue(state.messagesChanged(entries("a", "b", "c:AGENT", "d:USER")))
        XCTAssertEqual(state.unseenCount, 0)
        XCTAssertTrue(state.followsNewest)
    }

    func testSeeingTheNewestMessageClearsTheCount() {
        var state = scrolledUp()
        _ = state.messagesChanged(entries("a", "b", "c:AGENT"))
        state.newest("c", isVisible: true)
        XCTAssertEqual(state.unseenCount, 0)
        XCTAssertFalse(state.showsJumpControl)
        XCTAssertTrue(state.followsNewest)
    }

    func testANewRowLaidOutBelowDoesNotStopFollowing() {
        var state = opened()
        _ = state.messagesChanged(entries("a", "b", "c:AGENT"))
        // The new row reports off screen before the follow scroll reaches it; only the row that was seen can leave.
        state.newest("c", isVisible: false)
        XCTAssertTrue(state.followsNewest)
        state.newest("c", isVisible: true)
        state.newest("c", isVisible: false)
        XCTAssertFalse(state.followsNewest)
    }

    func testJumpingClearsTheCountAndFollowsAgain() {
        var state = scrolledUp()
        _ = state.messagesChanged(entries("a", "b", "c:AGENT"))
        state.jumpedToNewest()
        XCTAssertEqual(state.unseenCount, 0)
        XCTAssertTrue(state.followsNewest)
        XCTAssertFalse(state.showsJumpControl)
    }

    func testANewHistoryStartsAtTheEnd() {
        var state = scrolledUp()
        _ = state.messagesChanged(entries("a", "b", "c:AGENT"))
        XCTAssertTrue(state.messagesChanged(entries("x:AGENT", "y:AGENT")))
        XCTAssertEqual(state.unseenCount, 0)
        XCTAssertTrue(state.followsNewest)
    }

    func testUnreadTextIsCappedAtTheLimit() {
        let locale = Locale(identifier: "en")
        let format: (Int) -> String = { "\($0) new" }
        XCTAssertNil(ChatScrollState.unreadText(for: 0, locale: locale, format: format))
        XCTAssertEqual(ChatScrollState.unreadText(for: 7, locale: locale, format: format), "7 new")
        XCTAssertEqual(ChatScrollState.unreadText(for: 99, locale: locale, format: format), "99 new")
        XCTAssertEqual(ChatScrollState.unreadText(for: 1_000, locale: locale, format: format), "99+ new")
    }

    func testUnreadTextUsesThePluralCatalog() throws {
        XCTAssertEqual(try unread(1, "en"), "1 new message")
        XCTAssertEqual(try unread(3, "en"), "3 new messages")
        XCTAssertEqual(try unread(120, "en"), "99+ new messages")
        XCTAssertEqual(try unread(1, "de"), "1 neue Nachricht")
        XCTAssertEqual(try unread(3, "ru"), "3 новых сообщения")
        XCTAssertEqual(try unread(5, "ru"), "5 новых сообщений")
        XCTAssertEqual(try unread(2, "pl"), "2 nowe wiadomości")
        XCTAssertTrue(try unread(120, "ar").contains("+"))
    }

    private func unread(_ count: Int, _ language: String) throws -> String {
        let url = try XCTUnwrap(ReceptionResources.bundle.url(forResource: language, withExtension: "lproj"))
        let bundle = try XCTUnwrap(Bundle(url: url))
        let locale = Locale(identifier: language)
        return try XCTUnwrap(ChatScrollState.unreadText(for: count, locale: locale) {
            String(localized: "\($0) new messages", bundle: bundle, locale: locale)
        })
    }

    /// A chat that opened on "a" and "b" with the reader at the newest message.
    private func opened() -> ChatScrollState {
        var state = ChatScrollState()
        _ = state.messagesChanged(entries("a", "b"))
        state.newest("b", isVisible: true)
        return state
    }

    private func scrolledUp() -> ChatScrollState {
        var state = opened()
        state.newest("b", isVisible: false)
        return state
    }

    /// "id" for the reader's own messages, "id:SENDER" for others.
    private func entries(_ specs: String...) -> [ChatScrollState.Entry] {
        specs.map { spec in
            let parts = spec.split(separator: ":").map(String.init)
            return ChatScrollState.Entry(id: parts[0], sender: parts.count > 1 ? parts[1] : ChatScrollState.userSender)
        }
    }
}
