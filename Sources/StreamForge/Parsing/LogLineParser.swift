import Foundation

struct LogLineParseResult {
    let entry: LogEntry?
    /// 头部结束位置（UTF-16 偏移）。进度帧从此处之后开始扫描。
    let headerEndUTF16: Int
    let matched: Bool
}

/// 单条 record → `LogEntry`。匹配失败不抛异常：返回 `matched == false`，
/// 由 `OutputParser` 记一条 WARN 并跳过（ADR-004 §7）。
enum LogLineParser {
    static func parse(_ record: String, taskID: UUID?) -> LogLineParseResult {
        guard let regex = ParserPatterns.makeRegex(ParserPatterns.logHeader) else {
            return LogLineParseResult(entry: nil, headerEndUTF16: 0, matched: false)
        }
        let range = NSRange(record.startIndex..<record.endIndex, in: record)
        guard let match = regex.firstMatch(in: record, options: [], range: range) else {
            return LogLineParseResult(entry: nil, headerEndUTF16: 0, matched: false)
        }

        let timestamp = group(1, of: match, in: record)
        let levelText = group(2, of: match, in: record) ?? "INFO"
        let message = (group(3, of: match, in: record) ?? "")
            .trimmingCharacters(in: .newlines)

        let level = LogLevel.parse(levelText)
        let entry = LogEntry(timestamp: timestamp,
                             level: level,
                             message: message,
                             taskID: taskID,
                             source: .stdout,
                             hint: LogHints.hint(for: message))
        return LogLineParseResult(entry: entry,
                                  headerEndUTF16: match.range(at: 3).location,
                                  matched: true)
    }

    private static func group(_ index: Int, of match: NSTextCheckingResult, in text: String) -> String? {
        guard match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }
}
