import XCTest
@testable import Reception

@MainActor
final class CooldownTextTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let keys = [
        "Message limit reached. You can send again %@.", "Photos can be sent again %@. You can still send text.",
        "Too many attempts. Try again %@.", "Can't connect right now. Try again %@.", "Sending again %@",
        "Cancel", "Cancel automatic sending", "Live updates paused"
    ]

    private func inLanguage(_ language: String, _ check: () -> Void) {
        Reception.shared.languageOverride = language
        defer { Reception.shared.languageOverride = nil }
        check()
    }

    func testWaitsRoundUpInTheLargestUnitSoTheyAreNeverUnderstated() {
        inLanguage("en") {
            let waits: [(TimeInterval, String)] = [
                (0.2, "in 1 second"), (45, "in 45 seconds"), (59.5, "in 1 minute"), (61, "in 2 minutes"),
                (3599, "in 1 hour"), (3601, "in 2 hours"), (7.5 * 3600, "in 8 hours")
            ]
            for (seconds, text) in waits {
                XCTAssertEqual(CooldownText.relative(until: now.addingTimeInterval(seconds), now: now), text)
            }
        }
    }

    func testNoticesUseTheChatLanguageWithoutPromisingDelivery() {
        let messages = ServerCooldowns.Cooldown(scope: .messages, until: now.addingTimeInterval(45), automatic: true)
        let photos = ServerCooldowns.Cooldown(scope: .uploads, until: now.addingTimeInterval(2 * 3600), automatic: false)
        inLanguage("de") {
            XCTAssertEqual(CooldownText.notice(messages, now: now), "Nachrichtenlimit erreicht. Du kannst in 45 Sekunden wieder senden.")
            XCTAssertEqual(CooldownText.notice(photos, now: now),
                           "Fotos kannst du in 2 Stunden wieder senden. Textnachrichten funktionieren weiterhin.")
            XCTAssertEqual(CooldownText.resend(until: now.addingTimeInterval(8), now: now), "Wird in 8 Sekunden erneut gesendet")
        }
        inLanguage("en") {
            XCTAssertEqual(CooldownText.notice(messages, now: now), "Message limit reached. You can send again in 45 seconds.")
        }
    }

    func testEveryLanguageTranslatesEveryCooldownString() {
        for language in ReceptionLocalization.supportedLanguages where language != "en" {
            inLanguage(language) {
                let bundle = ReceptionLocalization.bundle
                for key in keys {
                    let value = bundle.localizedString(forKey: key, value: "missing", table: nil)
                    XCTAssertNotEqual(value, "missing", "\(language): \(key)")
                    XCTAssertNotEqual(value, key, "\(language): \(key)")
                    XCTAssertEqual(value.components(separatedBy: "%@").count, key.components(separatedBy: "%@").count,
                                   "\(language): \(key)")
                }
            }
        }
    }
}
