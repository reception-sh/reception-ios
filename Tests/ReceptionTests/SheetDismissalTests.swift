import XCTest
@testable import Reception

@MainActor
final class SheetDismissalTests: XCTestCase {
    func testOnlyADragFromTheHeaderClosesTheSheet() {
        XCTAssertTrue(ChatPresenter.closesSheet(touchStartingAt: 0))
        XCTAssertTrue(ChatPresenter.closesSheet(touchStartingAt: Theme.sheetHandleHeight))
        XCTAssertFalse(ChatPresenter.closesSheet(touchStartingAt: Theme.sheetHandleHeight + 1), "the messages never close the chat")
    }
}
