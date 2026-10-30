import XCTest
@testable import Reception

@MainActor
final class SheetDismissalTests: XCTestCase {
    func testTheHeaderIsTheGrabberInsetAndTheTitleBar() {
        XCTAssertTrue(ChatPresenter.isSheetHandle(touchStartingAt: 0))
        XCTAssertTrue(ChatPresenter.isSheetHandle(touchStartingAt: Theme.sheetHandleHeight))
        XCTAssertFalse(ChatPresenter.isSheetHandle(touchStartingAt: Theme.sheetHandleHeight + 1))
    }

    func testOnlyTheKeyboardRestrictsClosingToTheHeader() {
        XCTAssertFalse(ChatPresenter.locksSheet(keyboardVisible: false, onHeader: false), "with the keyboard down any drag closes the sheet")
        XCTAssertFalse(ChatPresenter.locksSheet(keyboardVisible: false, onHeader: true))
        XCTAssertFalse(ChatPresenter.locksSheet(keyboardVisible: true, onHeader: true), "the header closes the sheet while typing")
        XCTAssertTrue(ChatPresenter.locksSheet(keyboardVisible: true, onHeader: false), "the messages put the keyboard away instead")
    }
}
