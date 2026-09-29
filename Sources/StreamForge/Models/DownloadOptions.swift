import Foundation

/// 高级参数模型。字段与 `docs/contracts/cli-argument-contract.md` 参数表 1:1，
/// 默认值即上游默认值——不做"我们再改一层默认"的隐式行为（契约 §1.6）。
struct DownloadOptions: Codable, Equatable {
    enum KernelLogLevel: String, Codable, CaseIterable {
        case debug = "DEBUG"
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
        case off = "OFF"
    }

    enum DecryptionEngine: String, Codable, CaseIterable {
        case ffmpeg = "FFMPEG"
        case mp4decrypt = "MP4DECRYPT"
        case shakaPackager = "SHAKA_PACKAGER"
    }

    enum SubtitleFormat: String, Codable, CaseIterable {
        case srt = "SRT"
        case vtt = "VTT"
    }

    enum UILanguage: String, Codable, CaseIterable {
        case enUS = "en-US"
        case zhCN = "zh-CN"
        case zhTW = "zh-TW"
    }

    // 输出
    var saveName: String = ""
    var baseURL: String = ""
    var savePattern: String = ""

    // 必传开关
    var noAnsiColor: Bool = true
    var disableUpdateCheck: Bool = true
    var logLevel: KernelLogLevel = .info
    var keepLogFile: Bool = false

    // 性能
    var threadCount: Int = Defaults.threadCount
    var downloadRetryCount: Int = Defaults.downloadRetryCount
    var httpRequestTimeout: Int = Defaults.httpRequestTimeout
    var maxSpeed: String = ""
    var concurrentDownload: Bool = false

    // 网络
    var headers: [String] = []
    var useSystemProxy: Bool = true
    var customProxy: String = ""
    var appendURLParams: Bool = false
    var urlProcessorArgs: String = ""

    // 轨道选择
    var autoSelect: Bool = false
    var selectVideo: String = ""
    var selectAudio: String = ""
    var selectSubtitle: String = ""
    var dropVideo: String = ""
    var dropAudio: String = ""
    var dropSubtitle: String = ""
    var adKeyword: String = ""

    // 解密
    var keys: [String] = []
    var keyTextFile: String = ""
    var decryptionEngine: DecryptionEngine = .mp4decrypt
    var decryptionBinaryPath: String = ""
    var mp4RealTimeDecryption: Bool = false
    var customHLSMethod: String = ""
    var customHLSKey: String = ""
    var customHLSIV: String = ""

    // 输出与合并
    var skipMerge: Bool = false
    var skipDownload: Bool = false
    var checkSegmentsCount: Bool = true
    var binaryMerge: Bool = false
    var useFFmpegConcatDemuxer: Bool = false
    var delAfterDone: Bool = true
    var noDateInfo: Bool = false
    var noLog: Bool = false
    var writeMetaJSON: Bool = true
    var ffmpegBinaryPath: String = ""
    var muxAfterDone: String = ""
    var muxImports: [String] = []

    // 直播
    var livePerformAsVOD: Bool = false
    var liveRealTimeMerge: Bool = false
    var liveKeepSegments: Bool = true
    var livePipeMux: Bool = false
    var liveFixVTTByAudio: Bool = false
    var liveRecordLimit: String = ""
    var liveWaitTime: Int?
    var liveTakeCount: Int?

    // 字幕
    var subOnly: Bool = false
    var subFormat: SubtitleFormat = .srt
    var autoSubtitleFix: Bool = true

    // 杂项
    var customRange: String = ""
    var taskStartAt: String = ""
    var uiLanguage: UILanguage?
    var allowHLSMultiExtMap: Bool = false

    /// 是否按直播任务处理（未开 `--live-perform-as-vod`）。直播禁用暂停（ADR-003）。
    var isLive: Bool = false

    /// 需要合并（ffmpeg）的任务：未跳过合并即需要。
    var requiresFFmpeg: Bool { !skipMerge && !skipDownload }
}

extension DownloadOptions {
    /// 用户输入类取值。用于前导 `-` 校验（AC-10）——这些值会被上游当成选项解析。
    var userProvidedValues: [(field: String, value: String)] {
        var pairs: [(String, String)] = [
            ("saveName", saveName),
            ("baseURL", baseURL),
            ("savePattern", savePattern),
            ("maxSpeed", maxSpeed),
            ("customProxy", customProxy),
            ("urlProcessorArgs", urlProcessorArgs),
            ("selectVideo", selectVideo),
            ("selectAudio", selectAudio),
            ("selectSubtitle", selectSubtitle),
            ("dropVideo", dropVideo),
            ("dropAudio", dropAudio),
            ("dropSubtitle", dropSubtitle),
            ("adKeyword", adKeyword),
            ("keyTextFile", keyTextFile),
            ("decryptionBinaryPath", decryptionBinaryPath),
            ("customHLSKey", customHLSKey),
            ("customHLSIV", customHLSIV),
            ("ffmpegBinaryPath", ffmpegBinaryPath),
            ("muxAfterDone", muxAfterDone),
            ("liveRecordLimit", liveRecordLimit),
            ("customRange", customRange),
            ("taskStartAt", taskStartAt)
        ]
        for header in headers { pairs.append(("header", header)) }
        for key in keys { pairs.append(("key", key)) }
        for item in muxImports { pairs.append(("muxImport", item)) }
        return pairs
    }
}
