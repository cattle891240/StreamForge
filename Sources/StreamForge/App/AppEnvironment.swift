import SwiftUI
import Combine

/// 依赖注入根（architecture.md §3 / §4.4）：全部服务在此创建一次，视图只读取、不自建。
/// 主 actor 隔离：所有 `@Published` 变更只发生在主线程（architecture.md §8.1）。
@MainActor
final class AppEnvironment: ObservableObject {

    let settings: AppSettings
    let queue: TaskQueue
    let logStore: LogStore
    let dependencies: DependencyResolver
    let notifications: NotificationService
    let history: HistoryStore

    /// 选中任务与两个 Sheet 的开关放在环境中：菜单栏 Commands 与主窗口需要共享同一份状态。
    @Published var selectedTaskID: UUID?
    @Published var composerPresented = false
    @Published var dependencySheetPresented = false

    init() {
        let settings = AppSettings()
        settings.apply(SettingsStore().load())
        let logStore = LogStore()
        let dependencies = DependencyResolver()
        let notifications = NotificationService()
        self.settings = settings
        self.logStore = logStore
        self.dependencies = dependencies
        self.notifications = notifications
        self.history = HistoryStore()
        self.queue = TaskQueue(settings: settings,
                               logStore: logStore,
                               notifications: notifications,
                               dependencies: dependencies)
    }

    /// 启动装配：请求通知授权并做首次依赖探测（architecture.md §6）。
    func bootstrap() {
        notifications.requestAuthorizationIfNeeded()
        dependencies.probe(overrides: settings.toolPaths)
    }

    func persistSettings() {
        SettingsStore().save(settings.snapshot)
    }

    /// 退出前收尾：停掉仍在跑的进程并落盘设置。
    /// 先 SIGCONT 再 SIGTERM 由 `ProcessHandle.terminate()` 保证（AC-07）。
    func prepareForTermination() {
        for task in queue.tasks where task.phase.mayHaveLiveProcess {
            queue.cancel(task.id, deleteTemp: settings.deleteTempOnCancel)
        }
        logStore.flush()
        persistSettings()
    }

    // MARK: - 任务动作

    func createTask(input: InputSource,
                    options: DownloadOptions,
                    saveDir: String?,
                    saveName: String?,
                    start: Bool = true) {
        queue.enqueue(input, options: options, saveDir: saveDir, saveName: saveName)
        guard let id = queue.tasks.last?.id else { return }
        selectedTaskID = id
        // 达到并发上限时保持「准备中」排队，由队列在任务结束时自动递补（AC-09）。
        if start { queue.start(id) }
    }

    func resume(_ id: UUID) { queue.resume(id) }

    func pause(_ id: UUID) { queue.pause(id) }

    /// P2 停止：保留 tmp 目录，之后可用「重试（保留已下载分片）」继续（ADR-003）。
    func stopKeepingTemp(_ id: UUID) { queue.stopPreservingProgress(id) }

    func cancel(_ id: UUID) { queue.cancel(id, deleteTemp: settings.deleteTempOnCancel) }

    func retry(_ id: UUID) { queue.retry(id) }

    func remove(_ id: UUID) {
        queue.remove(id)
        if selectedTaskID == id { selectedTaskID = nil }
    }

    func selectedTask() -> DownloadTask? {
        guard let selectedTaskID else { return nil }
        return queue.tasks.first { $0.id == selectedTaskID }
    }
}
