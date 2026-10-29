import SwiftUI
import XCTest
@testable import Reception

@MainActor
final class LinkedTextTests: XCTestCase {
    func testWebAddressesBecomeLinks() {
        let text = "See https://example.com/help or http://example.org, and www.example.net."
        XCTAssertEqual(links(in: text).map(\.0), ["https://example.com/help", "http://example.org", "www.example.net"])
        XCTAssertEqual(links(in: text).map(\.1.scheme), ["https", "http", "http"])
        XCTAssertEqual(String(LinkedText.attributed(text).characters), text)
    }

    func testOtherSchemesStayPlainText() {
        XCTAssertTrue(links(in: "Open exampleapp://plans or write to help@example.com, call tel:+15551234").isEmpty)
        XCTAssertTrue(links(in: "No links here").isEmpty)
    }

    private func links(in text: String) -> [(String, URL)] {
        let attributed = LinkedText.attributed(text)
        return attributed.runs.compactMap { run in
            run[AttributeScopes.FoundationAttributes.LinkAttribute.self].map { (String(attributed[run.range].characters), $0) }
        }
    }
}
