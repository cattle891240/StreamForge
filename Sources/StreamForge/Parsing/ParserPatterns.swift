import Foundation

/// 全部正则常量集中一处（架构 §3）。上游改格式时只改这里。
/// 一律用 `NSRegularExpression`（ICU），**不用 Swift Regex DSL**——
/// Regex DSL 的运行时可用性会给 macOS 13 部署目标带来额外风险（ADR-004 §3）。
enum ParserPatterns {
    /// 粘连切分：**零宽 lookahead**。内核把日志与进度写在同一缓冲，
    /// 实测样本 4623 字节仅 8 个 `\n`、0 个 `\r`，按行解析必失败。
    static let recordSplit = #"(?=\d{2}:\d{2}:\d{2}\.\d{3}\s+(?:INFO|WARN|DEBUG|ERROR)\s*:)"#

    /// 仅供「变异加固」测试使用的反例：**吃掉时间戳**的普通匹配。
    /// 生产路径禁止引用——去掉 `(?=...)` 会吞掉切分锚点本身。
    static let recordSplitConsuming = #"\d{2}:\d{2}:\d{2}\.\d{3}\s+(?:INFO|WARN|DEBUG|ERROR)\s*:"#

    /// record 头部：1 时间戳 / 2 级别 / 3 消息（含粘连的进度块）。
    static let logHeader = #"^(\d{2}:\d{2}:\d{2}\.\d{3})\s+(INFO|WARN|DEBUG|ERROR)\s*:\s*(.*)$"#

    /// 进度帧。组号：1 name / 2 bar / 3 done / 4 total / 5 pct /
    /// 6 sizeDone / 7 unitA / 8 sizeTotal / 9 unitB / 10 speed / 11 unitC / 12 retry / 13 eta
    ///
    /// name 必须**字母开头**且字符集排除 `.` 与 `:`——否则粘连文本
    /// （`Start downloading...Vid Kbps`、`--:--:--Vid Kbps`）会被吞进轨道名（已复现，勿改回）。
    static let progressFrame = #"([A-Za-z][A-Za-z0-9 _\|\(\)\[\]x\-]{0,63}?)\s*([━╺─]*)\s*(\d+)/(\d+)\s+(-?[\d.]+)%(?:\s+([\d.]+)(B|KB|MB|GB)/([\d.]+)(B|KB|MB|GB))?\s+(-?[\d.]+)(Bps|KBps|MBps)(?:\((\d+)\))?\s+(\d{2}:\d{2}:\d{2}|--:--:--)"#

    /// ANSI CSI 转义。Swift 字符串字面量先解析 \u{1B} 为真实 ESC 字节，
    /// 避免依赖 ICU 对 `\u{...}` 花括号语法的支持差异。
    static let ansiEscape = "\u{1B}\\[[0-9;?]*[a-zA-Z]"

    /// 被 chunk 边界截断的半个转义序列，需滞留到下一批再剥离。
    static let incompleteANSI = "\u{1B}(?:\\[[0-9;?]*)?$"

    static func makeRegex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    }
}
