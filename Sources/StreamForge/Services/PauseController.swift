import Foundation

/// 暂停控制器的可注入替身接口（ADR-003 验证方式：用协议替身断言超时走 terminate 而非 resume）。
protocol ProcessControlling: AnyObject {
    func suspend()
    func resume()
    func terminate()
    func forceKill()
}

/// 把 Engine 的 ProcessHandle 适配到 ProcessControlling，避免在 Services 里给 Engine 类型加协议声明。
final class ProcessHandleAdapter: ProcessControlling {
    private let handle: ProcessHandle
    init(handle: ProcessHandle) { self.handle = handle }
    func suspend() { handle.suspend() }
    func resume() { handle.resume() }
    func terminate() { handle.terminate() }
    func forceKill() { handle.forceKill() }
}

/// 暂停策略与时长守卫（ADR-003）。
/// P1：SIGSTOP 挂起进程组；P2：暂停超时后自动转为「已停止（可重试）」，保留 tmp 目录。
/// 守卫时长 = min(httpRequestTimeout × 0.8, 80s)，避免恢复瞬间在途请求集中超时。
final class PauseController {

    /// 硬上限：与内核 --http-request-timeout 默认 100s 对齐后留 20s 余量。
    static let hardLimitSeconds: TimeInterval = 80
    static let safetyRatio: Double = 0.8

    private let control: ProcessControlling
    private let queue: DispatchQueue
    private let httpRequestTimeout: Int
    private var timer: DispatchSourceTimer?
    private var pausedAt: Date?
    private var isLive: Bool

    /// 暂停已累计时长（跨多次暂停累加），供 UI 的「已用时」扣除。
    private(set) var accumulatedPauseSeconds: TimeInterval = 0

    /// 超过守卫时长 → 回调（由 TaskCoordinator 转成 .stopped 状态）。
    var onAutoConvert: (() -> Void)?

    init(control: ProcessControlling,
                httpRequestTimeout: Int,
                isLive: Bool,
                queue: DispatchQueue = DispatchQueue(label: "com.streamforge.pause")) {
        self.control = control
        self.httpRequestTimeout = httpRequestTimeout
        self.isLive = isLive
        self.queue = queue
    }

    var guardSeconds: TimeInterval {
        min(TimeInterval(httpRequestTimeout) * PauseController.safetyRatio, PauseController.hardLimitSeconds)
    }

    /// 直播任务禁止暂停：SIGSTOP 期间播放列表持续刷新，恢复后必然丢片段（ADR-003）。
    var canPause: Bool { !isLive }

    func beginPause() {
        guard canPause else { return }
        queue.async { [weak self] in self?.performBeginPause() }
    }

    func endPause() {
        queue.async { [weak self] in self?.performEndPause() }
    }

    /// P2：停止并保留 tmp。必须先 SIGCONT 再 SIGTERM，否则停止中的进程收不到信号。
    func stopPreservingProgress() {
        queue.async { [weak self] in
            self?.performEndPause()
            self?.control.terminate()
        }
    }

    func invalidate() {
        queue.async { [weak self] in self?.teardownTimer() }
    }

    private func performBeginPause() {
        teardownTimer()
        control.suspend()
        pausedAt = Date()
        let seconds = guardSeconds
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + seconds)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.teardownTimer()
            self.control.resume()
            DispatchQueue.main.async { self.onAutoConvert?() }
        }
        timer.resume()
        self.timer = timer
    }

    private func performEndPause() {
        if let started = pausedAt {
            accumulatedPauseSeconds += Date().timeIntervalSince(started)
        }
        pausedAt = nil
        teardownTimer()
        control.resume()
    }

    private func teardownTimer() {
        timer?.cancel()
        timer = nil
    }
}
