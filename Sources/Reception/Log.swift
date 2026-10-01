import os

// Never log access tokens, session secrets, identity tokens or their claims, the identity secret,
// push token values, user IDs, names, email addresses, metadata values, message text, image URLs,
// conversation content, or base URL credentials.
// Allowed values are HTTP status and Reception error codes, counts, revision numbers,
// opaque conversation IDs, push environments, language tags, and development hostnames.
internal enum Log {
    private struct Settings: Sendable {
        var level: Reception.LogLevel = .info
        var handler: (@Sendable (Reception.LogLevel, String) -> Void)?
    }

    private static let settings = OSAllocatedUnfairLock(initialState: Settings())
    private static let logger = Logger(subsystem: "com.reception.sdk", category: "Reception")

    static var level: Reception.LogLevel {
        get { settings.withLock { $0.level } }
        set { settings.withLock { $0.level = newValue } }
    }

    static var handler: (@Sendable (Reception.LogLevel, String) -> Void)? {
        get { settings.withLock { $0.handler } }
        set { settings.withLock { $0.handler = newValue } }
    }

    static func error(_ message: @autoclosure () -> String) {
        emit(.error, label: "ERROR", message)
    }

    static func info(_ message: @autoclosure () -> String) {
        emit(.info, label: "INFO", message)
    }

    static func debug(_ message: @autoclosure () -> String) {
        emit(.debug, label: "DEBUG", message)
    }

    static func redacted(_ secret: String) -> String {
        "<\(secret.count) chars>"
    }

    private static func emit(_ level: Reception.LogLevel, label: String,
                             _ message: () -> String) {
        let destination = settings.withLock { settings in
            (enabled: settings.level != .off && level <= settings.level,
             handler: settings.handler)
        }
        guard destination.enabled else { return }
        let line = message()
        if let handler = destination.handler {
            handler(level, line)
            return
        }
        switch level {
        case .error:
            logger.error("[Reception] ERROR \(line, privacy: .public)")
        case .info:
            logger.info("[Reception] INFO \(line, privacy: .public)")
        case .debug:
            logger.debug("[Reception] DEBUG \(line, privacy: .public)")
        case .off:
            break
        }
    }
}
