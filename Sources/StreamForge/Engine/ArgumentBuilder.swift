import Foundation

/// 参数构建时的校验失败。UI 据此展示字段级错误，不启动任务（AC-10）。
enum ArgumentError: Error, Equatable {
    case leadingDash(field: String)
}

/// 单个任务的路径布局。由 `TaskQueue` 计算后传入，避免 `ArgumentBuilder` 触碰目录逻辑。
struct TaskLayout {
    let tmpDir: String
    let saveDir: String
    let logFile: String?

    init(tmpDir: String, saveDir: String, logFile: String?) {
        self.tmpDir = tmpDir
        self.saveDir = saveDir
        self.logFile = logFile
    }
}

/// 把任务输入与选项翻译成内核 argv。
///
/// 规则（详见 `docs/contracts/cli-argument-contract.md` 与 architecture.md §4.1）：
/// - 输入源排在最前（索引 0），其后才是所有选项。
/// - 顺序固定：行为开关 → 路径 → 性能 → 网络 → 轨道选择 → 解密 → 输出/合并 → 直播 → 字幕 → 杂项。
/// - 空字符串取值不输出；默认 false 的开关在 false 时不输出。
/// - 上游默认 true 的三项（`--check-segments-count` / `--del-after-done` / `--use-system-proxy`）
///   始终显式输出 `=True` / `=False`。
/// - 用户输入取值禁止以 `-` 开头，否则抛出 `ArgumentError`。
func buildArguments(
    input: InputSource,
    options: DownloadOptions,
    layout: TaskLayout
) throws -> [String] {
    try ArgumentRules.validate(options)

    var argv: [String] = []
    argv.append(input.argumentValue)

    // 行为开关（必传）
    argv.append("--no-ansi-color")
    argv.append("--disable-update-check")

    // 路径类
    argv.append("--tmp-dir"); argv.append(layout.tmpDir)
    argv.append("--save-dir"); argv.append(layout.saveDir)
    argv.append("--save-name")
    argv.append(options.saveName.isEmpty ? defaultSaveName(input) : options.saveName)
    if !options.baseURL.isEmpty { argv.append("--base-url"); argv.append(options.baseURL) }
    if !options.savePattern.isEmpty { argv.append("--save-pattern"); argv.append(options.savePattern) }
    if options.keepLogFile, let logFile = layout.logFile {
        argv.append("--log-file-path"); argv.append(logFile)
    }

    // 性能类
    argv.append("--thread-count"); argv.append(String(options.threadCount))
    argv.append("--download-retry-count"); argv.append(String(options.downloadRetryCount))
    argv.append("--http-request-timeout"); argv.append(String(options.httpRequestTimeout))
    if !options.maxSpeed.isEmpty { argv.append("--max-speed"); argv.append(options.maxSpeed) }
    if options.concurrentDownload { argv.append("--concurrent-download=True") }

    // 网络类
    for header in options.headers where !header.isEmpty {
        argv.append("-H"); argv.append(header)
    }
    argv.append("--use-system-proxy=\(ArgumentRules.effectiveSystemProxy(options) ? "True" : "False")")
    if !options.customProxy.isEmpty { argv.append("--custom-proxy"); argv.append(options.customProxy) }
    if options.appendURLParams { argv.append("--append-url-params=True") }
    if !options.urlProcessorArgs.isEmpty { argv.append("--urlprocessor-args"); argv.append(options.urlProcessorArgs) }

    // 轨道选择
    if options.autoSelect { argv.append("--auto-select=True") }
    if !options.selectVideo.isEmpty { argv.append("-sv"); argv.append(options.selectVideo) }
    if !options.selectAudio.isEmpty { argv.append("-sa"); argv.append(options.selectAudio) }
    if !options.selectSubtitle.isEmpty { argv.append("-ss"); argv.append(options.selectSubtitle) }
    if !options.dropVideo.isEmpty { argv.append("-dv"); argv.append(options.dropVideo) }
    if !options.dropAudio.isEmpty { argv.append("-da"); argv.append(options.dropAudio) }
    if !options.dropSubtitle.isEmpty { argv.append("-ds"); argv.append(options.dropSubtitle) }
    if !options.adKeyword.isEmpty { argv.append("--ad-keyword"); argv.append(options.adKeyword) }

    // 解密类
    for key in options.keys where !key.isEmpty {
        argv.append("--key"); argv.append(key)
    }
    if !options.keyTextFile.isEmpty { argv.append("--key-text-file"); argv.append(options.keyTextFile) }
    argv.append("--decryption-engine"); argv.append(options.decryptionEngine.rawValue)
    if !options.decryptionBinaryPath.isEmpty { argv.append("--decryption-binary-path"); argv.append(options.decryptionBinaryPath) }
    if options.mp4RealTimeDecryption { argv.append("--mp4-real-time-decryption=True") }
    if !options.customHLSMethod.isEmpty { argv.append("--custom-hls-method"); argv.append(options.customHLSMethod) }
    if !options.customHLSKey.isEmpty { argv.append("--custom-hls-key"); argv.append(options.customHLSKey) }
    if !options.customHLSIV.isEmpty { argv.append("--custom-hls-iv"); argv.append(options.customHLSIV) }

    // 输出与合并
    if options.skipMerge { argv.append("--skip-merge=True") }
    if options.skipDownload { argv.append("--skip-download=True") }
    argv.append("--check-segments-count=\(options.checkSegmentsCount ? "True" : "False")")
    if options.binaryMerge { argv.append("--binary-merge=True") }
    if options.useFFmpegConcatDemuxer { argv.append("--use-ffmpeg-concat-demuxer=True") }
    argv.append("--del-after-done=\(options.delAfterDone ? "True" : "False")")
    if options.noDateInfo { argv.append("--no-date-info=True") }
    if options.noLog { argv.append("--no-log=True") }
    argv.append("--write-meta-json=\(options.writeMetaJSON ? "True" : "False")")
    if !options.ffmpegBinaryPath.isEmpty { argv.append("--ffmpeg-binary-path"); argv.append(options.ffmpegBinaryPath) }
    if !options.muxAfterDone.isEmpty { argv.append("-M"); argv.append(options.muxAfterDone) }
    for item in options.muxImports where !item.isEmpty {
        argv.append("--mux-import"); argv.append(item)
    }

    // 直播类
    if options.livePerformAsVOD { argv.append("--live-perform-as-vod=True") }
    if options.liveRealTimeMerge { argv.append("--live-real-time-merge=True") }
    argv.append("--live-keep-segments=\(options.liveKeepSegments ? "True" : "False")")
    if options.livePipeMux { argv.append("--live-pipe-mux=True") }
    if options.liveFixVTTByAudio { argv.append("--live-fix-vtt-by-audio=True") }
    if !options.liveRecordLimit.isEmpty { argv.append("--live-record-limit"); argv.append(options.liveRecordLimit) }
    if let wait = options.liveWaitTime { argv.append("--live-wait-time"); argv.append(String(wait)) }
    if let take = options.liveTakeCount { argv.append("--live-take-count"); argv.append(String(take)) }

    // 字幕类
    if options.subOnly { argv.append("--sub-only=True") }
    argv.append("--sub-format"); argv.append(options.subFormat.rawValue)
    argv.append("--auto-subtitle-fix=\(options.autoSubtitleFix ? "True" : "False")")

    // 杂项
    if !options.customRange.isEmpty { argv.append("--custom-range"); argv.append(options.customRange) }
    if !options.taskStartAt.isEmpty { argv.append("--task-start-at"); argv.append(options.taskStartAt) }
    if let lang = options.uiLanguage { argv.append("--ui-language"); argv.append(lang.rawValue) }
    if options.allowHLSMultiExtMap { argv.append("--allow-hls-multi-ext-map=True") }

    return argv
}

/// 用户未填写保存名时，从输入源推导一个默认名（不含扩展名）。
private func defaultSaveName(_ input: InputSource) -> String {
    switch input {
    case .localFile(let url):
        return url.deletingPathExtension().lastPathComponent
    case .url(let value):
        return URL(string: value)?.deletingPathExtension().lastPathComponent ?? "video"
    }
}
