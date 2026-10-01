import XCTest
@testable import Reception

final class ConfigurationTests: XCTestCase {
    func testAppIdFormat() {
        XCTAssertTrue(ReceptionAPI.accepts(appId: "app_" + String(repeating: "A1b2", count: 5) + "Zz"))
        for value in ["app_" + String(repeating: "a", count: 21), "app_" + String(repeating: "a", count: 23),
                      "ids_" + String(repeating: "a", count: 43), "pk_" + String(repeating: "a", count: 22),
                      "app_" + String(repeating: "a", count: 21) + "-", " app_" + String(repeating: "a", count: 22), ""] {
            XCTAssertFalse(ReceptionAPI.accepts(appId: value), value)
        }
    }

}
