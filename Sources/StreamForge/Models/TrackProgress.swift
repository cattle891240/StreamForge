import Foundation

enum TrackKind: String {
    case video
    case audio
    case subtitle
    case other

    /// 轨道图标按名称前缀判定（契约 §4.2）。真名含其他前缀时归为 other。
    static func infer(name: String) -> TrackKind {
        let lower = name.lowercased()
        if lower.hasPrefix("vid") { return .video }
        if lower.hasPrefix("aud") { return .audio }
        if lower.hasPrefix("sub") { return .subtitle }
        return .other
    }
}

/// 单轨道进度快照。所有"未知"字段用 nil 表示，界面渲染占位符（AC-02）。
struct TrackProgress: Equatable {
    var name: String
    var done: Int
    var total: Int
    /// 已 clamp 到 0...100；内核会输出 `-0.00%`。
    var percent: Double
    var bytesDone: Int64?
    var bytesTotal: Int64?
    var speedBytesPerSecond: Double?
    /// 内核输出负速度（如 `-0.00Bps`）时为 true，此时 `speedBytesPerSecond` 为 nil。
    var speedUnknown: Bool
    var etaSeconds: Int?
    /// 速度列后缀 `(1)` `(2)` 表示重试计数，0 表示无重试。
    var retryCount: Int

    init(name: String,
         done: Int,
         total: Int,
         percent: Double,
         bytesDone: Int64? = nil,
         bytesTotal: Int64? = nil,
         speedBytesPerSecond: Double? = nil,
         speedUnknown: Bool = false,
         etaSeconds: Int? = nil,
         retryCount: Int = 0) {
        self.name = name
        self.done = done
        self.total = total
        self.percent = min(max(percent, 0), 100)
        self.bytesDone = bytesDone
        self.bytesTotal = bytesTotal
        self.speedBytesPerSecond = speedBytesPerSecond
        self.speedUnknown = speedUnknown
        self.etaSeconds = etaSeconds
        self.retryCount = retryCount
    }

    var kind: TrackKind { TrackKind.infer(name: name) }

    mutating func merge(_ newer: TrackProgress) {
        // 分片数单调不回退：直播场景 total 会增长，但 done 不应倒退。
        if newer.done >= done || newer.total != total {
            done = newer.done
            total = newer.total
            percent = newer.percent
            bytesDone = newer.bytesDone ?? bytesDone
            bytesTotal = newer.bytesTotal ?? bytesTotal
        }
        speedBytesPerSecond = newer.speedBytesPerSecond
        speedUnknown = newer.speedUnknown
        etaSeconds = newer.etaSeconds
        retryCount = newer.retryCount
    }
}
