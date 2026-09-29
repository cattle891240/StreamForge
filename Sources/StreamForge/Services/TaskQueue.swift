import Foundation
import Combine

/// 任务队列与并发调度（architecture.md §4.3）。全部 @Published 变更只发生在 MainActor。
@MainActor
final class TaskQueue: ObservableObject {

    @Published private(set) var tasks: [DownloadTask] = []
    @Published private(set) var blockedReason: String?

    var maxConcurrent: Int { settings.maxConcurrentTasks }

    private var coordinators: [UUID: TaskCoordinator] = [:]
    private var layouts: [UUID: TaskLayout] = [:]
    private var previews: [UUID: String] = [:]
    private var elapsedBasis: [UUID: Date] = [:]

    private let settings: AppSettings
    private let logStore: LogStore
    private let notifications: NotificationService
    private let dependencies: DependencyResolver

    init(settings: AppSettings,
                logStore: LogStore,
                notifications: NotificationService,
                dependencies: DependencyResolver) {
        self.settings = settings
        self.logStore = logStore
        self.notifications = notifications
        self.dependencies = dependencies
    }

    // MARK: - 入队

    func enqueue(_ input: InputSource, options: DownloadOptions) {
        enqueue(input, options: options, saveDir: nil, saveName: nil)
    }

    func enqueue(_ input: InputSource,
                        options: DownloadOptions,
                        saveDir: String?,
                        saveName: String?) {
        let resolvedDir = (saveDir?.isEmpty == false) ? saveDir! : settings.defaultSaveDir
        let id = UUID()
        var opts = options
        opts.saveName = saveName ?? TaskNaming.saveName(for: input)
        var task = DownloadTask(id: id,
                                input: input,
                                options: opts,
                                saveDir: resolvedDir,
                                tmpDir: TaskDirectory.tmpDir(taskID: id))
        task.phase = .preparing
        tasks.append(task)
    }

    // MARK: - 控制

    func start(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        guard tasks[index].phase != .downloading, tasks[index].phase != .merging else { return }

        // AC-12：内核缺失时阻止启动并给出指引。
        guard dependencies.downloadEngineReady else {
            blockedReason = dependencies.tool(.nre).map { dependencies.guidance(for: $0).headline }
                ?? "未找到 N_m3u8DL-RE。StreamForge 需要它来分析 m3u8 清单。"
            return
        }
        // AC-09：达到并发上限时保持「准备中」排队，由 scheduleNext 自动递补。
        guard runningCount < max(1, maxConcurrent) else { return }

        blockedReason = nil
        let layout = TaskLayout(tmpDir: TaskDirectory.tmpDir(taskID: id),
                                saveDir: tasks[index].saveDir,
                                logFile: tasks[index].options.keepLogFile ? TaskDirectory.logFile(taskID: id) : nil)
        TaskDirectory.ensure(at: layout.tmpDir)
        TaskDirectory.ensure(at: layout.saveDir)
        guard let executable = dependencies.resolvedExecutable(.nre) else { return }

        let coordinator: TaskCoordinator
        do {
            coordinator = try TaskCoordinator(task: tasks[index], layout: layout, executable: executable)
        } catch {
            tasks[index].lastError = error.localizedDescription
            tasks[index].phase = .finished(.failed)
            return
        }
        layouts[id] = layout
        previews[id] = coordinator.commandPreview
        coordinators[id] = coordinator
        elapsedBasis[id] = Date()

        coordinator.onProgress = { [weak self] progress in self?.applyProgress(progress, to: id) }
        coordinator.onLogs = { [weak self] entries in self?.logStore.append(entries, taskID: id) }
        coordinator.onPhaseChange = { [weak self] phase in self?.applyPhase(phase, to: id) }
        coordinator.onTerminated = { [weak self] outcome, error, count in
            self?.handleTermination(outcome: outcome, error: error, errorCount: count, id: id)
        }
        tasks[index].phase = .preparing
        coordinator.start()
    }

    func pause(_ id: UUID) {
        guard let coordinator = coordinators[id] else { return }
        coordinator.pause()
    }

    func resume(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        if case .stopped = tasks[index].phase {
            restart(id, deleteTemp: false)
            return
        }
        coordinators[id]?.resume()
    }

    /// P2 停止：保留 tmp，之后可用「重试（保留已下载分片）」恢复。
    func stopPreservingProgress(_ id: UUID) {
        coordinators[id]?.stopPreservingProgress()
    }

    func cancel(_ id: UUID, deleteTemp: Bool) {
        coordinators[id]?.cancel(deleteTemp: deleteTemp)
        if coordinators[id] == nil {
            applyPhase(.finished(.cancelled), to: id)
            if deleteTemp { TaskDirectory.remove(at: TaskDirectory.tmpDir(taskID: id)) }
        }
    }

    /// 重试：与首次完全一致的 argv + tmp/save 路径，这是上游能否复用已下载分片的前提（ADR-003）。
    func retry(_ id: UUID) {
        restart(id, deleteTemp: false)
    }

    func remove(_ id: UUID) {
        coordinators[id]?.cancel(deleteTemp: settings.deleteTempOnCancel)
        coordinators.removeValue(forKey: id)
        layouts.removeValue(forKey: id)
        previews.removeValue(forKey: id)
        elapsedBasis.removeValue(forKey: id)
        logStore.dropBuffer(for: id)
        tasks.removeAll { $0.id == id }
    }

    func commandPreview(for id: UUID) -> String? { previews[id] }

    func elapsedSeconds(for id: UUID) -> Int {
        guard let basis = elapsedBasis[id] else { return 0 }
        return max(0, Int(Date().timeIntervalSince(basis)))
    }

    var runningCount: Int {
        tasks.filter { task in
            switch task.phase {
            case .downloading, .merging, .paused, .stopped: return true
            default: return false
            }
        }.count
    }

    // MARK: - 内部

    private func restart(_ id: UUID, deleteTemp: Bool) {
        // 先摘掉旧协调器的回调，避免它的退出回调覆盖新进程的阶段。
        if let old = coordinators[id] {
            old.onProgress = nil
            old.onLogs = nil
            old.onPhaseChange = nil
            old.onTerminated = nil
            old.cancel(deleteTemp: deleteTemp)
        }
        coordinators.removeValue(forKey: id)
        if deleteTemp { TaskDirectory.remove(at: TaskDirectory.tmpDir(taskID: id)) }
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].lastError = nil
        tasks[index].progress.errorCount = 0
        tasks[index].phase = .preparing
        logStore.removeAll(for: id)
        start(id)
    }

    private func applyProgress(_ progress: TaskProgress, to id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].progress = progress
    }

    private func applyPhase(_ phase: TaskPhase, to id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].phase = phase
    }

    private func handleTermination(outcome: TaskOutcome, error: String?, errorCount: Int, id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].phase = .finished(outcome)
        tasks[index].lastError = error
        tasks[index].progress.errorCount = errorCount
        coordinators.removeValue(forKey: id)
        logStore.flush()
        notify(outcome: outcome, task: tasks[index])
        scheduleNext()
    }

    private func notify(outcome: TaskOutcome, task: DownloadTask) {
        switch outcome {
        case .succeeded:
            guard settings.notifyOnSuccess else { return }
            let size = task.progress.bytesTotal.map { ByteFormatter.bytes($0) } ?? "—"
            let used = DurationFormatter.clock(Int(elapsedSeconds(for: task.id)))
            notifications.notifySuccess(name: TaskNaming.displayName(for: task.input),
                                       detail: "大小 \(size)，用时 \(used)。")
        case .failed:
            guard settings.notifyOnFailure else { return }
            notifications.notifyFailure(name: TaskNaming.displayName(for: task.input),
                                        detail: task.lastError ?? "N_m3u8DL-RE 退出码非 0。")
        case .cancelled:
            return
        }
    }

    private func scheduleNext() {
        let waiting = tasks.filter { if case .preparing = $0.phase { return true } else { return false } }
        let free = max(0, max(1, maxConcurrent) - runningCount)
        for task in waiting.prefix(free) { start(task.id) }
    }
}

/// 任务目录约定（SPEC §6）。tmp 每任务隔离，便于取消后清理与重试复用。
enum TaskDirectory {
    private static let appName = "StreamForge"

    private static var cachesRoot: String {
        NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first
            ?? (NSHomeDirectory() + "/Library/Caches")
    }

    static func tmpDir(taskID: UUID) -> String {
        cachesRoot + "/\(appName)/tmp/\(taskID.uuidString)"
    }

    static func logFile(taskID: UUID) -> String {
        (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/\(appName)/\(taskID.uuidString).log")
    }

    static func ensure(at path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    static func remove(at path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}

enum TaskNaming {
    static func displayName(for input: InputSource) -> String {
        switch input {
        case .url(let text):
            let last = URL(string: text)?.lastPathComponent
            return last.nonEmpty ?? text
        case .localFile(let url): return url.deletingPathExtension().lastPathComponent
        }
    }

    static func saveName(for input: InputSource) -> String {
        switch input {
        case .url(let text):
            let last = URL(string: text)?.lastPathComponent ?? ""
            let trimmed = (last as NSString).deletingPathExtension
            return trimmed.isEmpty ? "streamforge_output" : trimmed
        case .localFile(let url):
            return url.deletingPathExtension().lastPathComponent
        }
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self, !value.isEmpty else { return nil }
        return value
    }
}
