import XCTest
@testable import Reception

final class LocalizationTests: XCTestCase {
    func testEverySupportedLanguageMatchesExactly() {
        for language in ReceptionLocalization.supportedLanguages {
            XCTAssertEqual(ReceptionLocalization.resolveLanguage(language), language)
        }
    }

    func testRegionalAndScriptAliases() {
        let fixtures = [
            "de_DE": "de", "de-AT": "de", "fr_CA": "fr-CA", "fr-BE": "fr",
            "es": "es", "es-ES": "es", "es-MX": "es-419", "es-US": "es-419",
            "pt": "pt-BR", "pt-PT": "pt-PT", "pt-AO": "pt-BR",
            "no": "nb", "nn-NO": "nb", "iw-IL": "he", "mo": "ro", "mol-US": "ro",
            "zh": "zh-Hans", "zh-TW": "zh-Hant", "zh-HK": "zh-HK", "zh-MO": "zh-HK",
            "zh-Hans-HK": "zh-Hans", "zh-Hant-CN": "zh-Hant", "zh-Hant-MO": "zh-HK",
            "zh-Hans-TW": "zh-Hans", " de_DE ": "de"
        ]
        for (identifier, expected) in fixtures {
            XCTAssertEqual(ReceptionLocalization.resolveLanguage(identifier), expected, identifier)
        }
    }

    func testUnsupportedAndInvalidLanguagesUseEnglish() {
        for identifier in ["xx", "is-IS", "invalid!", "de-12", "de-@", "en-u", "", "Base", "de-1901-1901", "de-a-foo-a-bar", "de-u-ca-gregory-u-nu-latn"] {
            XCTAssertEqual(ReceptionLocalization.resolveLanguage(identifier), "en", identifier)
        }
    }

    func testCanonicalAppLanguagePreservesSelection() {
        XCTAssertEqual(ReceptionLocalization.canonical("es_mx"), "es-MX")
        XCTAssertEqual(ReceptionLocalization.canonical("zh_hans_hk"), "zh-Hans-HK")
        XCTAssertEqual(ReceptionLocalization.canonical("iw-IL"), "he-IL")
        XCTAssertEqual(ReceptionLocalization.canonical("is-IS"), "is-IS")
        XCTAssertEqual(ReceptionLocalization.canonical("en-US-u-ca-gregory"), "en-US")
    }
}
