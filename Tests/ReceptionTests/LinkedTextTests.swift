import SwiftUI
import XCTest
@testable import Reception

final class LinkedTextTests: XCTestCase {
    func testWebAddressesBecomeLinksAndTheRestStaysPlain() {
        let text = "Docs at https://reception.sh/docs or www.apple.com, nothing else."
        let attributed = LinkedText.attributed(text, linkColor: .white)
        XCTAssertEqual(links(in: attributed).map(\.0), ["https://reception.sh/docs", "www.apple.com"])
        XCTAssertEqual(links(in: attributed).map(\.1.absoluteString), ["https://reception.sh/docs", "http://www.apple.com"])
        XCTAssertEqual(String(attributed.characters), text, "Nothing is added or removed")
    }

    func testOtherSchemesStayPlainText() {
        for text in ["Open exampleapp://plans or write to help@example.com, call tel:+15551234", "Just words, no address."] {
            XCTAssertTrue(links(in: LinkedText.attributed(text, linkColor: .white)).isEmpty, text)
        }
    }

    private func links(in attributed: AttributedString) -> [(String, URL)] {
        attributed.runs.compactMap { run in run.link.map { (String(attributed[run.range].characters), $0) } }
    }
}
