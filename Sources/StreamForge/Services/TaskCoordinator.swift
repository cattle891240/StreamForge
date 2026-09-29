import Foundation

/// 单任务状态机与进程编排（architecture.md §4.3）。
/// 控制与解析跑在专用串行队列 `queue`；管道读取跑在另一个队列，避免 wait 阻塞读回调造成死锁。
/// 终态一律以进程退出码判定：0 = 完成，非 0 = 失败，用户主动取消 = 已取消（ADR-004 §6）。
final class TaskCoordinator {

    let taskID: UUID

    private let layout: TaskLayout
    private let executable: String
    private let argv: [String]
    private let httpRequestTimeout: Int
    private let isLive: Bool
    private let queue: DispatchQueue
    private let pumpQueue: DispatchQueue
    private let parser: OutputParser

    private var pauseController: PauseController?
    private var handle: ProcessHandle?
    private var pump: OutputPump?
    private var forceKillWork: DispatchWorkItem?

    private var phase: TaskPhase
    private var progress: TaskProgress
    private var lastProgressPublish = Date.distantPast
    private let progressInterval: TimeInterval = 0.1
    private var errorCount = 0
    private var lastError: String?
    private var userCanceled = false
    private var exitHandled = false

    var onProgress: ((TaskProgress) -> Void)?
    var onLogs: (([LogEntry]) -> Void)?
    var onPhaseChange: ((TaskPhase) -> Void)?
    var onTerminated: ((TaskOutcome, String?, Int) -> Void)?

    init(task: DownloadTask, layout: TaskLayout, executable: String) throws {
        self.taskID = task.id
        self.layout = layout
        self.executable = executable
        self.argv = try buildArguments(input: task.input, options: task.options, layout: layout)
        self.httpRequestTimeout = task.options.httpRequestTimeout
        self.isLive = task.options.isLive || task.options.livePerformAsVOD
        self.queue = DispatchQueue(label: "com.streamforge.task.\(task.id.uuidString)")
        self.pumpQueue = DispatchQueue(label: "com.streamforge.pump.\(task.id.uuidString)")
        self.parser = OutputParser(taskID: task.id)
        self.phase = task.phase
        self.progress = task.progress
    }

    /// 命令预览与实际执行同源（都来自 buildArguments），禁止 UI 另拼一份。
    var commandPreview: String {
        ShellEscaping.commandLine(executable: executable, arguments: argv)
    }

    var allowsPause: Bool { !(isLive) }

    // MARK: - 生命周期

    func start() {
        queue.async { [weak self] in self?.performStart() }
    }

    func pause() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.pauseController?.beginPause()
            self.publishPhase(.paused)
        }
    }

    func resume() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.pauseController?.endPause()
            self.publishPhase(.downloading)
        }
    }

    /// P2：停止并保留 tmp 目录，供「重试（保留已下载分片）」复用（ADR-003）。
    func stopPreservingProgress() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.pauseController?.stopPreservingProgress()
            self.publishPhase(.stopped(reusable: true))
        }
    }

    func cancel(deleteTemp: Bool) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.userCanceled = true
            // terminate() 内部先 SIGCONT 再 SIGTERM，保证停止中的进程也能收到信号。
            self.handle?.terminate()
            let kill = DispatchWorkItem { [weak self] in self?.handle?.forceKill() }
            self.forceKillWork = kill
            self.queue.asyncAfter(deadline: .now() + 5, execute: kill)
        }
    }

    private func performStart() {
        publishPhase(.preparing)
        do {
            let spawned = try spawnGroup(executable: executable, arguments: argv, environment: nil)
            let handle = ProcessHandle(pid: spawned.pid)
            self.handle = handle

            let pauseController = PauseController(control: ProcessHandleAdapter(handle: handle),
                                                  httpRequestTimeout: httpRequestTimeout,
                                                  isLive: isLive,
                                                  queue: queue)
            pauseController.onAutoConvert = { [weak self] in self?.stopPreservingProgress() }
            self.pauseController = pauseController

            let pump = OutputPump(stdoutFD: spawned.stdoutFD, stderrFD: spawned.stderrFD, queue: pumpQueue) { [weak self] isStderr, data in
                guard let self = self else { return }
                self.queue.async { self.ingest(data, isStderr: isStderr) }
            }
            self.pump = pump
            pump.start()

            DispatchQueue.global(qos: .utility).async { [weak self] in
                let exit = handle.wait()
                self?.queue.async { self?.handleExit(exit) }
            }
        } catch {
            lastError = error.localizedDescription
            publishPhase(.finished(.failed))
            finish(outcome: .failed)
        }
    }

    private func handleExit(_ exit: ProcessExit) {
        guard !exitHandled else { return }
        exitHandled = true
        forceKillWork?.cancel()
        pump?.cancel()
        parser.freeze()
        pauseController?.invalidate()

        let outcome: TaskOutcome
        if userCanceled {
            outcome = .cancelled
        } else if let code = exit.code {
            outcome = code == 0 ? .succeeded : .failed
            if code != 0, lastError == nil {
                lastError = "N_m3u8DL-RE 退出码 \(code)。查看日志面板中的 ERROR 行定位原因。"
            }
        } else {
            outcome = .failed
            if lastError == nil {
                lastError = "N_m3u8DL-RE 被信号 \(exit.signal ?? 0) 终止。"
            }
        }
        publishPhase(.finished(outcome))
        finish(outcome: outcome)
    }

    private func finish(outcome: TaskOutcome) {
        let error = lastError
        let count = errorCount
        DispatchQueue.main.async { [weak self] in
            self?.onTerminated?(outcome, error, count)
        }
    }

    // MARK: - 解析与节流

    private func ingest(_ data: Data, isStderr: Bool) {
        let result = parser.ingest(data, isStderr: isStderr)
        consume(result)
        if Date().timeIntervalSince(lastProgressPublish) >= progressInterval {
            lastProgressPublish = Date()
            let snapshot = progress
            DispatchQueue.main.async { [weak self] in self?.onProgress?(snapshot) }
        }
    }

    private func consume(_ result: ParseResult) {
        if !result.logs.isEmpty {
            for entry in result.logs where entry.level == .error {
                errorCount += 1
                if lastError == nil { lastError = entry.message }
            }
            let logs = result.logs
            DispatchQueue.main.async { [weak self] in self?.onLogs?(logs) }
        }
        if let hint = result.phaseHint {
            switch hint {
            case .preparing: publishPhase(.preparing)
            case .downloading: publishPhase(.downloading)
            case .merging: publishPhase(.merging)
            }
        }
        let tracks = parser.latestTracks
        guard !tracks.isEmpty else { return }
        progress = TaskAggregator.aggregate(tracks: tracks, previous: progress)
    }

    private func publishPhase(_ next: TaskPhase) {
        // 终态之后不再回退：退出码是唯一终态依据，日志关键词只用于阶段提示。
        if case .finished = phase { return }
        guard next != phase else { return }
        phase = next
        DispatchQueue.main.async { [weak self] in self?.onPhaseChange?(next) }
    }
}

/// 多轨道进度 → 任务级快照。幽灵轨道已由 OutputParser 剔除（kernel-output-contract §4.1）。
enum TaskAggregator {
    static func aggregate(tracks: [TrackProgress], previous: TaskProgress) -> TaskProgress {
        guard !tracks.isEmpty else { return previous }
        var percentSum = 0.0
        var done = 0
        var total = 0
        var bytesDone: Int64 = 0
        var bytesTotal: Int64 = 0
        var hasBytes = false
        var speed: Double = 0
        var speedUnknown = false
        var maxRetry = previous.retryCount
        var eta: Int?

        for track in tracks {
            percentSum += track.percent
            done += track.done
            total += track.total
            if let d = track.bytesDone, let t = track.bytesTotal {
                bytesDone += d
                bytesTotal += t
                hasBytes = true
            }
            if let s = track.speedBytesPerSecond, !track.speedUnknown, s >= 0 {
                speed += s
            } else {
                speedUnknown = true
            }
            maxRetry = max(maxRetry, track.retryCount)
            if let trackETA = track.etaSeconds { eta = max(eta ?? 0, trackETA) }
        }

        var result = previous
        result.percent = percentSum / Double(tracks.count)
        result.segmentDone = done
        result.segmentTotal = total
        result.bytesDone = hasBytes ? bytesDone : nil
        result.bytesTotal = hasBytes ? bytesTotal : nil
        result.speedBytesPerSecond = speedUnknown ? nil : speed
        result.etaSeconds = eta
        result.retryCount = maxRetry
        result.tracks = tracks
        return result
    }
}
