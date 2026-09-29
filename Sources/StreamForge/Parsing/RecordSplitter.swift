import Foundation

/// 时间戳 lookahead 切分。零宽断言切分，不吞掉任何字符；
/// 第一个时间戳之前的残留（进程刚启动的半个进度帧）直接丢弃。
enum RecordSplitter {
    /// 无时间戳时返回空数组——调用方据此判定"纯进度流"，进入无日志分支。
    static func split(_ text: String) -> [String] {
        guard !text.isEmpty,
              let regex = ParserPatterns.makeRegex(ParserPatterns.recordSplit) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        guard !matches.isEmpty else { return [] }

        let utf16 = text.utf16
        var records: [String] = []
        for index in 0..<matches.count {
            let startOffset = matches[index].range.location
            let endOffset = index + 1 < matches.count ? matches[index + 1].range.location : utf16.count
            guard endOffset > startOffset else { continue }
            let start = String.Index(utf16Offset: startOffset, in: text)
            let end = String.Index(utf16Offset: endOffset, in: text)
            records.append(String(text[start..<end]))
        }
        return records
    }

    /// 文本中时间戳（含级别）出现的次数，用于「日志条数 == 时间戳个数」断言。
    static func timestampCount(_ text: String) -> Int {
        guard let regex = ParserPatterns.makeRegex(ParserPatterns.recordSplit) else { return 0 }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }
}
