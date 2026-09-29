import Foundation

enum LogLevel: String, Codable, CaseIterable, Comparable {
    case debug
    case info
    case warn
    case error

    var displayName: String {
        switch self {
        case .debug: return "调试"
        case .info: return "信息"
        case .warn: return "警告"
        case .error: return "错误"
        }
    }

    /// 过滤用权重，越大越严重。
    var rank: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warn: return 2
        case .error: return 3
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rank < rhs.rank }

    /// 内核输出级别字面量 → 枚举。未知级别视为 info，解析层绝不因此失败。
    static func parse(_ text: String) -> LogLevel {
        switch text.uppercased() {
        case "DEBUG": return .debug
        case "INFO": return .info
        case "WARN", "WARNING": return .warn
        case "ERROR": return .error
        default: return .info
        }
    }
}

enum LogSource: String, Codable {
    case stdout
    case stderr
}

struct LogEntry: Identifiable, Equatable, Codable {
    let id: UUID
    var timestamp: String?
    var level: LogLevel
    var message: String
    var taskID: UUID?
    var source: LogSource
    /// 由 `LogHints` 生成的修复提示，可能为 nil。
    var hint: String?

    init(id: UUID = UUID(),
         timestamp: String? = nil,
         level: LogLevel,
         message: String,
         taskID: UUID? = nil,
         source: LogSource = .stdout,
         hint: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.taskID = taskID
        self.source = source
        self.hint = hint
    }
}
