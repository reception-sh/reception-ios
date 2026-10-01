import Foundation

/// A settable wall clock for cooldown deadlines; tests move it instead of waiting.
final class TestTime: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}
