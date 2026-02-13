import os

enum LogCategory: String {
    case mqtt
    case sensor
    case action
    case config
    case general
}

enum LogLevel: String, Codable, Comparable, CaseIterable {
    case debug
    case info
    case warning
    case error

    private var rank: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

final class Log {
    static var level: LogLevel = .info

    private static let subsystem = "com.macquitto"

    private static var loggers: [LogCategory: os.Logger] = [:]

    private static func logger(for category: LogCategory) -> os.Logger {
        if let existing = loggers[category] { return existing }
        let l = os.Logger(subsystem: subsystem, category: category.rawValue)
        loggers[category] = l
        return l
    }

    static func debug(_ message: String, category: LogCategory = .general) {
        guard level <= .debug else { return }
        logger(for: category).debug("\(message, privacy: .public)")
    }

    static func info(_ message: String, category: LogCategory = .general) {
        guard level <= .info else { return }
        logger(for: category).info("\(message, privacy: .public)")
    }

    static func warning(_ message: String, category: LogCategory = .general) {
        guard level <= .warning else { return }
        logger(for: category).warning("\(message, privacy: .public)")
    }

    static func error(_ message: String, category: LogCategory = .general) {
        logger(for: category).error("\(message, privacy: .public)")
    }
}
