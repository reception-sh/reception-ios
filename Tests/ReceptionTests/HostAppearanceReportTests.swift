import SwiftUI
import XCTest
@testable import Reception

@MainActor
final class HostAppearanceReportTests: XCTestCase {
    func testDefaultsReportOnlyTheRemoteSetting() throws {
        let report = HostAppearanceReport.payload(Reception.Appearance(), usesRemoteAppearance: true)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(report))
        XCTAssertEqual(report as NSDictionary, ["usesRemoteAppearance": true])
    }

    func testCodedAppearanceUsesTheDashboardSchema() throws {
        var appearance = Reception.Appearance()
        appearance.accentColor = Color(red: 1, green: 85 / 255, blue: 0)
        appearance.incomingBackground = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .black : .white })
        appearance.title = "Help"
        appearance.preferredColorScheme = .dark
        appearance.closeIcon = .chevronDown
        appearance.closeImage = Image(systemName: "xmark")
        appearance.fontDesign = .rounded
        appearance.fontFamily = "AvenirNext-Bold"
        appearance.fadesOlderMessages = false
        appearance.welcomeIcon = .symbol("sparkles")
        appearance.welcomeIconSize = 59.6
        appearance.welcomeIconOffset = CGSize(width: 0, height: -10)
        appearance.hidesWelcomeText = true
        appearance.hidesPushStatus = true

        let report = HostAppearanceReport.payload(appearance, usesRemoteAppearance: false)

        XCTAssertTrue(JSONSerialization.isValidJSONObject(report))
        XCTAssertEqual(report as NSDictionary, [
            "usesRemoteAppearance": false,
            "colors": ["accent": ["light": "#FF5500", "dark": "#FF5500"], "incoming": ["light": "#FFFFFF", "dark": "#000000"]],
            "text": ["title": "Help"], "colorScheme": "dark", "closeIcon": "chevron.down", "closeImage": true,
            "fontDesign": "rounded", "fontFamily": "AvenirNext-Bold", "fadesOlderMessages": false,
            "welcomeIcon": ["symbol": "sparkles", "size": 60, "offset": ["x": 0, "y": -10]],
            "visibility": ["welcomeText": false, "pushStatus": false],
        ])
    }

    func testHiddenAndLocalWelcomeIcons() {
        var appearance = Reception.Appearance()
        appearance.welcomeIcon = .hidden
        XCTAssertEqual(HostAppearanceReport.payload(appearance, usesRemoteAppearance: true)["visibility"] as? [String: Bool], ["welcomeIcon": false])
        appearance.welcomeIcon = .image(Image(systemName: "star"))
        appearance.welcomeIconCornerRadius = 12
        XCTAssertEqual(HostAppearanceReport.payload(appearance, usesRemoteAppearance: true)["welcomeIcon"] as? NSDictionary,
                       ["image": true, "cornerRadius": 12])
    }
}
