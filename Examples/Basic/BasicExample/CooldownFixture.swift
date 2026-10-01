#if DEBUG && targetEnvironment(simulator)
import Foundation
import Reception

/// Maintainer screenshots of limit cooldowns: the real SDK chat against simulated service replies.
/// Launch with `-ReceptionCooldownFixture <scenario>`. The replies are fixtures, not backend enforcement.
enum CooldownScenario: String, CaseIterable {
    /// The first send gets a 45-second message wait, then succeeds when resent.
    case messageShort = "message-short"
    /// The first send gets a two-hour message wait and needs a manual retry.
    case messageLong = "message-long"
    /// The first send gets a 65-second message wait: manual, Retry becomes available when it ends.
    case messageExpired = "message-expired"
    /// A photo reservation gets a 30-minute upload wait; text still sends.
    case photo
    /// The first send gets a 50-second general request wait.
    case requests
    /// The first registration gets an 8-minute session wait.
    case session
    /// Sending works; the live connection gets a 60-second stream wait.
    case stream
    /// Existing states for comparison: a blocked device and a required sign-in.
    case blocked, verification

    static var launch: CooldownScenario? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ReceptionCooldownFixture"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return CooldownScenario(rawValue: arguments[index + 1])
    }
}

@MainActor
enum CooldownFixture {
    /// Each launch starts a fresh chat unless `-ReceptionCooldownFixtureRelaunch` keeps the previous one,
    /// which shows that stored waits survive a relaunch.
    static func start(_ scenario: CooldownScenario) {
        CooldownFixtureProtocol.scenario = scenario
        URLProtocol.registerClass(CooldownFixtureProtocol.self)
        Reception.shared.usesRemoteAppearance = false
        Reception.configure(appId: "app_CooldownFixture0000000")
        if !ProcessInfo.processInfo.arguments.contains("-ReceptionCooldownFixtureRelaunch") {
            Reception.shared.logout()
            CooldownFixtureProtocol.resetLog()
        }
    }
}
#endif
