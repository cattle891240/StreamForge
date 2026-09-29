import Foundation

/// 任务级进度快照：由多轨道聚合而来，供 UI 展示。纯值类型，聚合规则集中在此。
struct TaskProgress: Equatable {
    var tracks: [TrackProgress]
    /// 按分片数加权：sum(done) / sum(total)。无轨道时为 0。
    var percent: Double
    var bytesDone: Int64?
    var bytesTotal: Int64?
    var speedBytesPerSecond: Double?
    var etaSeconds: Int?
    var segmentDone: Int
    var segmentTotal: Int
    var errorCount: Int
    var lastError: String?
    /// 最近一次解析到的重试计数（任一轨道）。
    var retryCount: Int

    static let empty = TaskProgress(tracks: [],
                                    percent: 0,
                                    bytesDone: nil,
                                    bytesTotal: nil,
                                    speedBytesPerSecond: nil,
                                    etaSeconds: nil,
                                    segmentDone: 0,
                                    segmentTotal: 0,
                                    errorCount: 0,
                                    lastError: nil,
                                    retryCount: 0)

    init(tracks: [TrackProgress],
         percent: Double,
         bytesDone: Int64?,
         bytesTotal: Int64?,
         speedBytesPerSecond: Double?,
         etaSeconds: Int?,
         segmentDone: Int,
         segmentTotal: Int,
         errorCount: Int,
         lastError: String?,
         retryCount: Int) {
        self.tracks = tracks
        self.percent = min(max(percent, 0), 100)
        self.bytesDone = bytesDone
        self.bytesTotal = bytesTotal
        self.speedBytesPerSecond = speedBytesPerSecond
        self.etaSeconds = etaSeconds
        self.segmentDone = segmentDone
        self.segmentTotal = segmentTotal
        self.errorCount = errorCount
        self.lastError = lastError
        self.retryCount = retryCount
    }

    /// 聚合规则：分片数取和；字节取和（任一轨道缺失则该侧为 nil）；
    /// 速度取和；ETA 优先按剩余字节与总速度推算，否则取轨道 ETA 的最大值。
    static func aggregate(tracks: [TrackProgress],
                          errorCount: Int = 0,
                          lastError: String? = nil) -> TaskProgress {
        guard !tracks.isEmpty else {
            return TaskProgress(tracks: [], percent: 0, bytesDone: nil, bytesTotal: nil,
                                speedBytesPerSecond: nil, etaSeconds: nil, segmentDone: 0,
                                segmentTotal: 0, errorCount: errorCount, lastError: lastError,
                                retryCount: 0)
        }
        let segmentDone = tracks.reduce(0) { $0 + $1.done }
        let segmentTotal = tracks.reduce(0) { $0 + $1.total }
        let percent = segmentTotal > 0 ? Double(segmentDone) / Double(segmentTotal) * 100 : 0

        var bytesDone: Int64?
        var bytesTotal: Int64?
        if tracks.allSatisfy({ $0.bytesDone != nil }) {
            bytesDone = tracks.reduce(Int64(0)) { $0 + ($1.bytesDone ?? 0) }
        }
        if tracks.allSatisfy({ $0.bytesTotal != nil }) {
            bytesTotal = tracks.reduce(Int64(0)) { $0 + ($1.bytesTotal ?? 0) }
        }

        let speeds = tracks.compactMap { $0.speedBytesPerSecond }
        let speed = speeds.isEmpty ? nil : speeds.reduce(0, +)

        var eta: Int?
        if let done = bytesDone, let total = bytesTotal, let speed, speed > 0, total > done {
            eta = Int(Double(total - done) / speed)
        } else {
            let known = tracks.compactMap { $0.etaSeconds }
            eta = known.max()
        }

        let retry = tracks.map { $0.retryCount }.max() ?? 0
        return TaskProgress(tracks: tracks, percent: percent, bytesDone: bytesDone,
                            bytesTotal: bytesTotal, speedBytesPerSecond: speed, etaSeconds: eta,
                            segmentDone: segmentDone, segmentTotal: segmentTotal,
                            errorCount: errorCount, lastError: lastError, retryCount: retry)
    }
}
