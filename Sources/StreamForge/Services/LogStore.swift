import Foundation
import Combine

/// 每任务一条环形日志缓冲。日志正文只存内存，不落盘（SPEC §6）。
/// 高频追加必须成批：单条 append 不触发发布，避免逐行刷新把界面拖垮。
final class LogStore: ObservableObject {

    static let capacity = 5000

    private var buffers: [UUID: RingBuffer<LogEntry>] = [:]
    private var pending: [LogEntry] = []
    private let flushInterval: TimeInterval = 0.2
    private var lastFlush = Date.distantPast
    private let lock = NSLock()

    @Published private(set) var revision: Int = 0

    init() {}

    /// 追加一批日志。合并窗口 200ms（design.md §9.5 坑 5）。
    func append(_ entries: [LogEntry], taskID: UUID) {
        guard !entries.isEmpty else { return }
        lock.lock()
        pending.append(contentsOf: entries)
        let due = Date().timeIntervalSince(lastFlush) >= flushInterval || pending.count >= 50
        lock.unlock()
        if due { flush(taskID: taskID) }
    }

    func flush(taskID: UUID? = nil) {
        lock.lock()
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        lastFlush = Date()
        for entry in batch {
            guard let tid = entry.taskID else { continue }
            var buffer = buffers[tid] ?? RingBuffer<LogEntry>(capacity: LogStore.capacity)
            buffer.append(entry)
            buffers[tid] = buffer
        }
        lock.unlock()
        guard !batch.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in self?.revision += 1 }
    }

    func entries(for taskID: UUID) -> [LogEntry] {
        lock.lock()
        let snapshot = buffers[taskID]?.toArray ?? []
        lock.unlock()
        return snapshot
    }

    /// 详情区日志超过 5000 行时只暴露最近 2000 行（design.md §8.6 详情区 Edge 态）。
    func visibleEntries(for taskID: UUID, limit: Int = 2000) -> [LogEntry] {
        let all = entries(for: taskID)
        guard all.count > limit else { return all }
        return Array(all.suffix(limit))
    }

    func isTruncated(for taskID: UUID, limit: Int = 2000) -> Bool {
        entries(for: taskID).count > limit
    }

    func removeAll(for taskID: UUID) {
        lock.lock()
        buffers[taskID]?.removeAll()
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.revision += 1 }
    }

    func dropBuffer(for taskID: UUID) {
        lock.lock()
        buffers.removeValue(forKey: taskID)
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.revision += 1 }
    }

    /// 复制用：拼成纯文本，非法字符已在上游清洗。
    func plainText(for taskID: UUID) -> String {
        entries(for: taskID).map { entry in
            "\(SFLogTimestamp.string(entry.timestamp)) \(entry.level.rawValue.uppercased()) \(entry.message)"
        }.joined(separator: "\n")
    }
}

/// 日志时间戳格式化。日志区用 HH:mm:ss.SSS，与内核时间戳对齐便于对照。
enum SFLogTimestamp {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func string(_ date: Date) -> String {
        formatter.string(from: date)
    }

    /// 日志条目已自带格式化好的时间戳字符串，透传即可（nil 时回退为空串）。
    static func string(_ timestamp: String?) -> String {
        timestamp ?? ""
    }
}
