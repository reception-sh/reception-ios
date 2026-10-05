import SwiftUI
import XCTest
@testable import Reception

@MainActor
final class AppearanceMergeTests: XCTestCase {
    private func remote(_ json: String) throws -> RemoteAppearance {
        try JSONDecoder().decode(RemoteAppearance.self, from: Data(json.utf8))
    }

    private func localAppearance() -> Reception.Appearance {
        var local = Reception.Appearance()
        // Literal copy keeps merge tests independent of the shared instance and its secure storage.
        local.title = "Support"
        local.welcomeTitle = "Welcome"
        local.welcomeText = "How can we help?"
        return local
    }

    func testRemoteWithoutWelcomeSettingsKeepsHostValues() throws {
        var local = localAppearance()
        local.welcomeIcon = .symbol("sparkles")
        local.welcomeIconSize = 80
        local.welcomeIconOffset = CGSize(width: 0, height: -10)
        local.hidesTitle = true
        local.hidesWelcomeText = true

        let result = try remote("{}").applying(to: local)

        guard case .symbol("sparkles") = result.welcomeIcon?.icon else { return XCTFail("host icon replaced") }
        XCTAssertEqual(result.welcomeIconSize, 80)
        XCTAssertEqual(result.welcomeIconOffset, CGSize(width: 0, height: -10))
        XCTAssertTrue(result.hidesTitle)
        XCTAssertFalse(result.hidesWelcomeTitle)
        XCTAssertTrue(result.hidesWelcomeText)
    }

    func testRemoteWelcomeSettingsOverrideHostValues() throws {
        var local = localAppearance()
        local.welcomeIcon = .image(Image(systemName: "star"))
        local.welcomeIconSize = 80

        let result = try remote(#"{"welcomeIcon":{"symbol":"heart","size":500},"hidden":["welcomeTitle"]}"#).applying(to: local)

        guard case .symbol("heart") = result.welcomeIcon?.icon else { return XCTFail("remote icon ignored") }
        XCTAssertEqual(result.welcomeIconSize, 160)
        XCTAssertTrue(result.hidesWelcomeTitle)
    }

    func testHostCloseImageStaysUntilRemoteSetsOne() throws {
        var local = localAppearance()
        local.closeImage = Image(systemName: "star")

        let result = try remote("{}").applying(to: local)

        XCTAssertNotNil(result.closeImage)
        XCTAssertNil(result.remoteCloseImage)
    }

    func testRemoteHiddenIconWinsOverHostImage() throws {
        var local = localAppearance()
        local.welcomeIcon = .image(Image(systemName: "star"))

        let result = try remote(#"{"hidden":["welcomeIcon"]}"#).applying(to: local)

        XCTAssertTrue(result.welcomeIcon?.icon.isHidden == true)
    }

    func testExplicitVisibilityOverridesLocalAndLegacyHiding() throws {
        var local = localAppearance()
        local.hidesTitle = true
        local.hidesWelcomeTitle = true
        local.hidesWelcomeText = true
        let shown = try remote(#"{"visibility":{"title":true,"welcomeTitle":true,"welcomeText":true},"hidden":["title","welcomeTitle","welcomeText"]}"#)
            .applying(to: local)
        XCTAssertFalse(shown.hidesTitle)
        XCTAssertFalse(shown.hidesWelcomeTitle)
        XCTAssertFalse(shown.hidesWelcomeText)
        XCTAssertTrue(local.hidesTitle)

        let hidden = try remote(#"{"visibility":{"title":false,"welcomeTitle":false,"welcomeText":false}}"#)
            .applying(to: localAppearance())
        XCTAssertTrue(hidden.hidesTitle)
        XCTAssertTrue(hidden.hidesWelcomeTitle)
        XCTAssertTrue(hidden.hidesWelcomeText)
    }

    func testExplicitShowRestoresHiddenWelcomeIcon() throws {
        var local = localAppearance()
        local.welcomeIcon = .hidden
        let shown = try remote(#"{"visibility":{"welcomeIcon":true}}"#).applying(to: local)
        XCTAssertNil(shown.welcomeIcon)

        let inherited = try remote("{}").applying(to: local)
        XCTAssertTrue(inherited.welcomeIcon?.icon.isHidden == true)

        let replaced = try remote(#"{"welcomeIcon":{"symbol":"heart.fill"}}"#).applying(to: local)
        guard case .symbol("heart.fill") = replaced.welcomeIcon?.icon else { return XCTFail("remote icon ignored") }
    }

    func testShowingWelcomeIconKeepsHostImageAndHidingOverridesRemoteSymbol() throws {
        var local = localAppearance()
        local.welcomeIcon = .image(Image(systemName: "star"))
        let shown = try remote(#"{"visibility":{"welcomeIcon":true}}"#).applying(to: local)
        guard case .local = shown.welcomeIcon?.icon else { return XCTFail("host image replaced") }

        let hidden = try remote(#"{"visibility":{"welcomeIcon":false},"welcomeIcon":{"symbol":"heart.fill"}}"#)
            .applying(to: local)
        XCTAssertTrue(hidden.welcomeIcon?.icon.isHidden == true)
    }

    func testExplicitShowOverridesLegacyNoneForWelcomeAndCards() throws {
        let result = try remote(#"{"visibility":{"welcomeIcon":true,"reviewIcon":true,"offerAccessory":false},"welcomeIcon":{"symbol":"none"},"cards":{"review":{"icon":"none"}}}"#)
            .applying(to: localAppearance())
        XCTAssertNil(result.welcomeIcon)
        XCTAssertNil(result.reviewCard.icon)
        XCTAssertTrue(result.offerCard.accessory?.isHidden == true)

        let legacy = try remote(#"{"welcomeIcon":{"symbol":"none"},"cards":{"review":{"icon":"none"}}}"#)
            .applying(to: localAppearance())
        XCTAssertTrue(legacy.welcomeIcon?.icon.isHidden == true)
        XCTAssertTrue(legacy.reviewCard.icon?.isHidden == true)
    }

    func testRemoteCloseSymbolOverridesHostImageOnlyWhenValid() throws {
        var local = localAppearance()
        local.closeImage = Image(systemName: "star")
        let overridden = try remote(#"{"closeIcon":"chevron.down"}"#).applying(to: local)
        XCTAssertNil(overridden.closeImage)
        XCTAssertEqual(overridden.closeIcon, .chevronDown)
        XCTAssertNotNil(local.closeImage)

        let invalid = try remote(#"{"closeIcon":"unknown"}"#).applying(to: local)
        XCTAssertNotNil(invalid.closeImage)
    }

    func testRemoteFontDesignOverridesHostFontOnlyWhenValid() throws {
        var local = localAppearance()
        local.fontFamily = "AppFont"
        local.fontDesign = .serif
        for design in ["default", "rounded", "serif", "monospaced"] {
            let result = try remote("{\"fontDesign\":\"\(design)\"}").applying(to: local)
            XCTAssertNil(result.fontFamily)
        }
        for json in ["{}", #"{"fontDesign":"unknown"}"#] {
            let result = try remote(json).applying(to: local)
            XCTAssertEqual(result.fontFamily, "AppFont")
            XCTAssertEqual(result.fontDesign, .serif)
        }
        XCTAssertEqual(local.fontFamily, "AppFont")
    }

    func testExplicitCenterOverridesHostOffset() throws {
        var local = localAppearance()
        local.welcomeIconOffset = CGSize(width: 20, height: -40)
        let result = try remote(#"{"welcomeIcon":{"offset":{"x":0,"y":0}}}"#).applying(to: local)
        XCTAssertEqual(result.welcomeIconOffset, .zero)
        XCTAssertEqual(try remote("{}").applying(to: local).welcomeIconOffset, local.welcomeIconOffset)
    }

    func testWelcomeCornerRadiusOverridesIndependentlyAndRestoresLocalValue() throws {
        var local = localAppearance()
        local.welcomeIcon = .image(Image(systemName: "star"))
        local.welcomeIconCornerRadius = 16
        for (json, expected) in [
            (#"{"welcomeIcon":{"cornerRadius":0}}"#, CGFloat(0)),
            (#"{"welcomeIcon":{"cornerRadius":24}}"#, CGFloat(24)),
            (#"{"welcomeIcon":{"size":80}}"#, CGFloat(16)),
            ("{}", CGFloat(16)),
        ] {
            let result = try remote(json).applying(to: local)
            XCTAssertEqual(result.welcomeIconCornerRadius, expected)
            guard case .local = result.welcomeIcon?.icon else { return XCTFail("radius replaced the image") }
        }
        XCTAssertEqual(local.welcomeIconCornerRadius, 16)
        XCTAssertEqual(Reception.Appearance().welcomeIconCornerRadius, 0)
    }

}
