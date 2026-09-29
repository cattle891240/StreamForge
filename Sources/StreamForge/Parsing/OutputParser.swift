import Foundation

struct ParseResult {
    let logs: [LogEntry]
    let tracks: [TrackProgress]
    let phaseHint: PhaseHint?

    static let empty = ParseResult(logs: [], tracks: [], phaseHint: nil)
}

/// 门面：字节流 → (日志, 进度, 阶段)。线程不安全，调用方负责串行化（architecture §4.2）。
///
/// 缓冲策略：进度帧之间**没有分隔符**（实测 4623 字节仅 8 个 `\n`、0 个 `\r`），
/// 因此不能按行解析；`tail` 保存"最后一个完整进度帧之后的未闭合文本"，
/// 下批拼接后再扫描，保证跨 chunk 的半个帧不丢。
final class OutputParser {

    /// 幽灵轨道剔除窗口（tick）：上游约 10 Hz 刷新，即约 1 秒（kernel-output-contract §4.1）。
    static let staleWindow = Defaults.staleWindowTicks

    /// 未闭合文本的安全上限：极端场景（无换行的纯日志流）防止缓冲无限增长。
    private static let tailCap = 16384

    private let taskID: UUID?
    private let stdoutNormalizer = OutputNormalizer()
    private let stderrNormalizer = OutputNormalizer()

    private var tail = ""
    private var tracks: [String: TrackProgress] = [:]
    private var order: [String] = []
    private var lastSeenTick: [String: Int] = [:]
    private var tick = 0
    private var frozen = false

    init(taskID: UUID? = nil) {
        self.taskID = taskID
    }

    /// 只返回"仍在刷新"的轨道：首帧重复造成的幽灵轨道会在窗口后被剔除。
    /// `freeze()` 之后不再剔除，保证终态的轨道集合完整。
    var latestTracks: [TrackProgress] {
        let visible = frozen ? order : order.filter { tick - (lastSeenTick[$0] ?? tick) <= Self.staleWindow }
        return visible.compactMap { tracks[$0] }
    }

    /// 进程退出时调用：冻结可见集合，之后 ingest 不再剔除轨道。
    func freeze() {
        frozen = true
    }

    func ingest(_ data: Data, isStderr: Bool) -> ParseResult {
        let text = isStderr ? stderrNormalizer.ingest(data) : stdoutNormalizer.ingest(data)
        guard !text.isEmpty else { return .empty }
        return isStderr ? stderrResult(text) : parse(text)
    }

    /// 进程退出时冲刷残留：半行 UTF-8、未闭合 record、未闭合进度帧（AC-01）。
    func flushTail() -> ParseResult {
        var result = ParseResult.empty
        let stdoutTail = stdoutNormalizer.flush()
        if !stdoutTail.isEmpty { result = parse(stdoutTail) }
        let stderrTail = stderrNormalizer.flush()
        if !stderrTail.isEmpty {
            result = merging(result, logs: stderrLogs(stderrTail), phaseHint: nil)
        }
        if !tail.isEmpty {
            result = merging(result, logs: logs(in: tail), phaseHint: nil)
        }
        tail = ""
        return result
    }

    // MARK: - 内部实现

    private func parse(_ text: String) -> ParseResult {
        let combined = tail + text
        // tail 若以一条 record 头部开头，说明该 record 的日志已在上批产出，不得重复。
        let skipFirst = !tail.isEmpty && LogLineParser.parse(tail, taskID: nil).matched
        let logs = logs(in: combined, skipFirstRecord: skipFirst)

        let parsed = ProgressParser.parseWithRanges(combined)
        absorb(parsed.map { $0.frame })
        tail = newTail(from: combined, lastFrameEndUTF16: parsed.last?.endUTF16)

        var hint: PhaseHint?
        for entry in logs {
            if let phase = LogHints.phaseHint(for: entry.message) { hint = phase }
        }
        return ParseResult(logs: logs, tracks: latestTracks, phaseHint: hint)
    }

    /// 切分并解析日志。解析失败只记一条 WARN，绝不影响进程生命期（ADR-004 §5）。
    private func logs(in text: String, skipFirstRecord: Bool = false) -> [LogEntry] {
        let records = RecordSplitter.split(text)
        guard !records.isEmpty else { return [] }
        var entries: [LogEntry] = []
        for (index, record) in records.enumerated() {
            if index == 0 && skipFirstRecord { continue }
            let parsed = LogLineParser.parse(record, taskID: taskID)
            tick += 1
            if parsed.matched, let entry = parsed.entry {
                entries.append(entry)
            } else {
                entries.append(LogEntry(level: .warn,
                                        message: "无法解析的内核输出：\(String(record.prefix(120)))",
                                        taskID: taskID,
                                        source: .stdout))
            }
        }
        return entries
    }

    /// 按 name 归并：后者覆盖最新字段，`TrackProgress.merge` 保证分片数不回退。
    private func absorb(_ frames: [TrackProgress]) {
        for frame in frames {
            if tracks[frame.name] == nil { order.append(frame.name) }
            if var existing = tracks[frame.name] {
                existing.merge(frame)
                tracks[frame.name] = existing
            } else {
                tracks[frame.name] = frame
            }
            lastSeenTick[frame.name] = tick
        }
    }

    /// 未闭合文本 = 最后一个完整进度帧之后的部分；无帧时整段保留。以换行结尾视为闭合。
    private func newTail(from combined: String, lastFrameEndUTF16: Int?) -> String {
        if combined.hasSuffix("\n") || combined.hasSuffix("\r") { return "" }
        guard let offset = lastFrameEndUTF16, offset > 0 else {
            return clipped(combined)
        }
        // 最后一帧已抵达文本末尾：没有残留，返回空。否则会把已解析的整段重新塞回
        // tail，被 flushTail 再次当作日志产出，造成跨 chunk 重复（AC-01）。
        if offset >= combined.utf16.count { return "" }
        let start = String.Index(utf16Offset: offset, in: combined)
        return clipped(String(combined[start...]))
    }

    private func clipped(_ text: String) -> String {
        text.count > Self.tailCap ? String(text.suffix(Self.tailCap)) : text
    }

    /// stderr 无时间戳（.NET 未捕获异常栈）：逐行记为 ERROR。
    private func stderrResult(_ text: String) -> ParseResult {
        ParseResult(logs: stderrLogs(text), tracks: latestTracks, phaseHint: nil)
    }

    private func stderrLogs(_ text: String) -> [LogEntry] {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { LogEntry(level: .error,
                            message: $0,
                            taskID: taskID,
                            source: .stderr,
                            hint: LogHints.hint(for: $0)) }
    }

    private func merging(_ base: ParseResult, logs: [LogEntry], phaseHint: PhaseHint?) -> ParseResult {
        ParseResult(logs: base.logs + logs, tracks: base.tracks, phaseHint: base.phaseHint ?? phaseHint)
    }
}
