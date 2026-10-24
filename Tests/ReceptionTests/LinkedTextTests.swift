import SwiftUI
import XCTest
@testable import Reception

final class LinkedTextTests: XCTestCase {
    func testOnlyLinksBecomeTappableAndTheRestStaysPlain() {
        let text = "Docs at https://reception.sh/docs or www.apple.com, nothing else."
        let attributed = LinkedText.attributed(text, linkColor: .white)
        let links = attributed.runs.compactMap { run in run.link.map { (String(attributed[run.range].characters), $0.absoluteString) } }
        XCTAssertEqual(links.map(\.0), ["https://reception.sh/docs", "www.apple.com"])
        XCTAssertEqual(links.map(\.1), ["https://reception.sh/docs", "http://www.apple.com"])
        XCTAssertEqual(String(attributed.characters), text, "Nothing is added or removed")
        XCTAssertNil(LinkedText.attributed("Just words, no address.", linkColor: .white).runs.first { $0.link != nil })
    }
}
