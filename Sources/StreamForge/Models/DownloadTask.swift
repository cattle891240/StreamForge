import Foundation

/// 任务实体。值类型 + Identifiable；状态变更由 Services 层产生新值。
struct DownloadTask: Identifiable, Equatable {
    let id: UUID
    var input: InputSource
    var options: DownloadOptions
    var phase: TaskPhase
    var progress: TaskProgress
    var createdAt: Date
    var startedAt: Date?
    var endedAt: Date?
    var saveDir: String
    var tmpDir: String
    var logFile: String?
    var exitCode: Int?
    var terminationSignal: Int?
    var lastError: String?
    /// 本次实际下发的 argv（不含可执行文件），用于重试与命令预览。
    var arguments: [String]
    /// 暂停累计时长（秒）。UI 展示"已用时"时必须扣除（ADR-003）。
    var pausedSeconds: TimeInterval

    var saveName: String { options.saveName }

    var isActive: Bool {
        switch phase {
        case .downloading, .preparing, .paused, .merging, .queued: return true
        default: return false
        }
    }

    init(id: UUID = UUID(),
         input: InputSource,
         options: DownloadOptions,
         phase: TaskPhase = .queued,
         progress: TaskProgress = .empty,
         createdAt: Date = Date(),
         startedAt: Date? = nil,
         endedAt: Date? = nil,
         saveDir: String,
         tmpDir: String,
         logFile: String? = nil,
         exitCode: Int? = nil,
         terminationSignal: Int? = nil,
         lastError: String? = nil,
         arguments: [String] = [],
         pausedSeconds: TimeInterval = 0) {
        self.id = id
        self.input = input
        self.options = options
        self.phase = phase
        self.progress = progress
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.saveDir = saveDir
        self.tmpDir = tmpDir
        self.logFile = logFile
        self.exitCode = exitCode
        self.terminationSignal = terminationSignal
        self.lastError = lastError
        self.arguments = arguments
        self.pausedSeconds = pausedSeconds
    }

    /// 已用时（扣除暂停时长）。未开始为 0。
    func elapsedSeconds(now: Date = Date()) -> TimeInterval {
        guard let startedAt else { return 0 }
        let end = endedAt ?? now
        return max(0, end.timeIntervalSince(startedAt) - pausedSeconds)
    }
}
