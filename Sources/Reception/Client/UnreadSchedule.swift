import Foundation

internal struct UnreadStage: Codable {
    let forMinutes: Int
    let everySeconds: Int
}

internal enum UnreadSchedule {
    static let defaultStages = [
        UnreadStage(forMinutes: 1, everySeconds: 15),
        UnreadStage(forMinutes: 10, everySeconds: 60),
        UnreadStage(forMinutes: 1440, everySeconds: 600)
    ]

    static func interval(status: String?, lastActivity: Date?, push: Bool?,
                         stages: [UnreadStage]?, now: Date) -> TimeInterval? {
        guard status == "OPEN", push == false, let lastActivity else { return nil }
        let age = now.timeIntervalSince(lastActivity)
        guard let stage = (stages ?? defaultStages).first(where: { age < Double($0.forMinutes) * 60 }),
              stage.everySeconds > 0 else { return nil }
        return TimeInterval(stage.everySeconds)
    }
}
