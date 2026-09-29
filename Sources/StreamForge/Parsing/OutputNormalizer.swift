import Foundation

/// 字节流 → 干净文本：UTF-8 增量解码 + ANSI 剥离 + 半个转义序列滞留。
/// 严禁产生替换字符 `�` 或丢帧（ADR-004 §2）。
final class OutputNormalizer {
    private var pendingBytes: [UInt8] = []
    private var pendingEscape = ""

    /// 解码一批字节。跨 chunk 被截断的多字节字符（进度条 `━` 是 3 字节）会滞留到下一批。
    func decode(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        pendingBytes.append(contentsOf: data)
        guard let (text, consumed) = decodeValidPrefix(pendingBytes) else {
            // 不足 4 字节且尚不能判定：继续等待后续字节。
            if pendingBytes.count > 4 { pendingBytes = [] }
            return ""
        }
        pendingBytes = Array(pendingBytes.dropFirst(consumed))
        return text
    }

    /// 进程退出时冲刷残留。无法构成合法 UTF-8 的尾部字节直接丢弃，不做替换。
    func flush() -> String {
        guard !pendingBytes.isEmpty else { pendingBytes = []; return "" }
        let text = String(decoding: partialValidPrefix(pendingBytes), as: UTF8.self)
        pendingBytes = []
        return text
    }

    /// 剥离 ANSI，并返回可能被截断的半个转义序列供下一批拼接。
    func stripANSI(_ text: String) -> String {
        let combined = pendingEscape + text
        pendingEscape = ""
        guard let regex = ParserPatterns.makeRegex(ParserPatterns.ansiEscape) else { return combined }
        let range = NSRange(combined.startIndex..<combined.endIndex, in: combined)
        var cleaned = regex.stringByReplacingMatches(in: combined, options: [], range: range, withTemplate: "")

        if let tail = ParserPatterns.makeRegex(ParserPatterns.incompleteANSI) {
            let tailRange = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            if let match = tail.firstMatch(in: cleaned, options: [], range: tailRange),
               let found = Range(match.range, in: cleaned) {
                pendingEscape = String(cleaned[found])
                cleaned.removeSubrange(found)
            }
        }
        return cleaned
    }

    /// 一步完成「解码 + 剥离」，供 `OutputParser` 使用。
    func ingest(_ data: Data) -> String {
        let text = decode(data)
        return text.isEmpty ? "" : stripANSI(text)
    }

    private func decodeValidPrefix(_ bytes: [UInt8]) -> (String, Int)? {
        // 从最长前缀往回退，最多回退 3 字节（UTF-8 最长 4 字节序列）。
        let lowerBound = max(0, bytes.count - 3)
        var length = bytes.count
        while length > lowerBound {
            if let text = String(bytes: bytes[0..<length], encoding: .utf8) { return (text, length) }
            length -= 1
        }
        if length == 0 { return ("", 0) }
        return nil
    }

    private func partialValidPrefix(_ bytes: [UInt8]) -> [UInt8] {
        var length = bytes.count
        while length > 0 {
            if String(bytes: bytes[0..<length], encoding: .utf8) != nil { return Array(bytes[0..<length]) }
            length -= 1
        }
        return []
    }
}
