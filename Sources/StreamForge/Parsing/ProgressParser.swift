import Foundation

/// 粘连进度块 → `[TrackProgress]`（kernel-output-contract §3）。
/// 纯函数：一次调用返回文本中出现的**全部**帧（按出现顺序），不做归并；
/// 归并由 `OutputParser` 按 name 为 key 完成。
enum ProgressParser {

    /// 一个进度帧 + 它在源文本中的结束位置（UTF-16 偏移），
    /// 供 `OutputParser` 计算"最后一个完整帧之后的未闭合文本"。
    struct ParsedFrame {
        let frame: TrackProgress
        let endUTF16: Int
    }

    static func parse(_ text: String) -> [TrackProgress] {
        parseWithRanges(text).map { $0.frame }
    }

    static func parseWithRanges(_ text: String) -> [ParsedFrame] {
        guard !text.isEmpty,
              let regex = ParserPatterns.makeRegex(ParserPatterns.progressFrame) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        var frames: [ParsedFrame] = []
        frames.reserveCapacity(matches.count)
        for match in matches {
            guard let frame = makeFrame(match, in: text) else { continue }
            frames.append(ParsedFrame(frame: frame, endUTF16: NSMaxRange(match.range)))
        }
        return frames
    }

    /// 组号：1 name / 3 done / 4 total / 5 pct / 6 sizeDone / 7 unitA /
    /// 8 sizeTotal / 9 unitB / 10 speed / 11 unitC / 12 retry / 13 eta
    private static func makeFrame(_ match: NSTextCheckingResult, in text: String) -> TrackProgress? {
        guard let name = group(1, of: match, in: text),
              let done = Int(group(3, of: match, in: text) ?? ""),
              let total = Int(group(4, of: match, in: text) ?? ""),
              let percent = Double(group(5, of: match, in: text) ?? "") else { return nil }

        let bytesDone = scaledBytes(value: group(6, of: match, in: text), unit: group(7, of: match, in: text))
        let bytesTotal = scaledBytes(value: group(8, of: match, in: text), unit: group(9, of: match, in: text))

        let rawSpeedText = group(10, of: match, in: text)
        let rawSpeed = Double(rawSpeedText ?? "")
        let speedUnit = group(11, of: match, in: text)
        var speed: Double?
        var speedUnknown = true
        // 内核把"未知速度"写成 -0.00Bps（负零）。`rawSpeed >= 0` 对负零也为真，
        // 会把它误判为已知速度，因此必须以字面量是否以 `-` 开头来识别占位符。
        if let rawSpeed, let unit = speedUnit, let multiplier = speedMultiplier(for: unit),
           !(rawSpeedText ?? "").hasPrefix("-") {
            speed = rawSpeed * multiplier
            speedUnknown = false
        }

        let retryCount = Int(group(12, of: match, in: text) ?? "") ?? 0
        let eta = group(13, of: match, in: text).flatMap(DurationFormatter.parseClock)

        return TrackProgress(name: name,
                             done: done,
                             total: total,
                             percent: percent,
                             bytesDone: bytesDone,
                             bytesTotal: bytesTotal,
                             speedBytesPerSecond: speed,
                             speedUnknown: speedUnknown,
                             etaSeconds: eta,
                             retryCount: retryCount)
    }

    private static func scaledBytes(value: String?, unit: String?) -> Int64? {
        guard let value, let unit,
              let amount = Double(value),
              let multiplier = ByteFormatter.multiplier(for: unit) else { return nil }
        return Int64(amount * multiplier)
    }

    /// `Bps / KBps / MBps` → 每秒字节数。未知单位返回 nil（按缺失处理）。
    private static func speedMultiplier(for unit: String) -> Double? {
        ByteFormatter.multiplier(for: unit.replacingOccurrences(of: "ps", with: ""))
    }

    private static func group(_ index: Int, of match: NSTextCheckingResult, in text: String) -> String? {
        guard index < match.numberOfRanges,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }
}
