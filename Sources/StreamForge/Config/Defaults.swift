import Foundation

/// 全部默认值常量。**与上游默认值保持一致**（契约 §1.6），
/// UI 显示的默认即上游默认，不做二次加工。
enum Defaults {
    // 队列
    static let maxConcurrentTasks = 2

    // 内核参数默认值（取自 `--help` 实测）
    static let threadCount = 8
    static let downloadRetryCount = 3
    static let httpRequestTimeout = 100

    // 暂停策略（ADR-003）
    /// 时长守卫上限：min(httpRequestTimeout × 0.8, 80)
    static let pauseGuardCeiling: TimeInterval = 80
    static let pauseGuardRatio = 0.8
    /// SIGTERM 后等待多久再 SIGKILL
    static let terminateGraceSeconds: TimeInterval = 5

    // 解析层（ADR-004）
    /// 幽灵轨道剔除窗口（tick 数）。上游约 10 Hz 刷新，即约 1 秒。
    static let staleWindowTicks = 10

    // 日志
    /// 每任务日志环形缓冲上限
    static let logBufferCapacity = 5000
    /// 进度向主线程发布的合并窗口（≤10 Hz）
    static let progressThrottleSeconds: TimeInterval = 0.1

    // 路径
    static let saveDirRelativePath = "Downloads/StreamForge"
    static let appSupportFolderName = "StreamForge"
    static let cachesFolderName = "StreamForge"
    static let logsFolderName = "StreamForge"

    // 持久化
    static let userDefaultsSuite = "com.streamforge.preferences"
    static let settingsKey = "app.settings.v1"
    static let historyFileName = "history.json"

    // 依赖
    static let dependencyProbeTimeoutSeconds: TimeInterval = 2
}
