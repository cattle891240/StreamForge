import SwiftUI

/// SF Symbols 名称常量表 —— 全项目唯一出处。
/// The Symbol-Only Rule：视图中禁止出现字符串字面量符号名，禁止 emoji 作功能图标。
/// 全部符号为 SF Symbols 4 或更早（macOS 13 运行时上限），避免运行时渲染为空白框。
enum SFSymbol {
    // 工具栏 / 主操作
    static let newTask = "plus"
    static let start = "play.fill"
    static let startAll = "play.fill"
    static let pause = "pause.fill"
    static let pauseAll = "pause.fill"
    static let stop = "stop.fill"
    static let remove = "trash"
    static let close = "xmark"
    static let retry = "arrow.clockwise"
    static let copy = "doc.on.doc"
    static let paste = "doc.on.clipboard"
    static let folder = "folder"
    static let settings = "gearshape"
    static let search = "magnifyingglass"
    static let scrollToBottom = "chevron.down"
    static let help = "questionmark.circle"
    static let reveal = "folder"

    // 依赖
    static let dependencyOK = "checkmark.circle.fill"
    static let dependencyMissing = "exclamationmark.triangle.fill"
    static let dependencyBroken = "xmark.octagon.fill"
    static let dependencyShield = "checkmark.shield"
    static let toolTerminal = "terminal"
    static let toolFilm = "film"

    // 任务状态（附录 C.1）
    static let statusPreparing = "clock"
    static let statusDownloading = "arrow.down.circle.fill"
    static let statusPaused = "pause.circle.fill"
    static let statusStopped = "stop.circle.fill"
    static let statusMerging = "shuffle"
    static let statusDone = "checkmark.circle.fill"
    static let statusFailed = "exclamationmark.triangle.fill"
    static let statusCanceled = "xmark.circle.fill"

    // 轨道类型（按前缀判定）
    static let trackVideo = "film"
    static let trackAudio = "waveform"
    static let trackSubtitle = "captions.bubble"
    static let trackGeneric = "square.stack.3d.up"

    // 指标
    static let speedometer = "speedometer"
    static let threadCount = "number.circle"
    static let headerList = "list.bullet"
    static let cookie = "lock.circle"

    // 设置分组
    static let groupDownload = "square.and.arrow.down.fill"
    static let groupNetwork = "network"
    static let groupDecryption = "key.fill"
    static let groupOutput = "square.and.pencil"
    static let groupLive = "antenna.radiowaves.left.and.right"
    static let groupAdvanced = "slider.horizontal.3"

    // 空状态
    static let emptyTray = "tray.and.arrow.down"
}

/// 轨道名前缀 → 图标。契约见 kernel-output-contract.md §4.2。
enum SFTrackIcon {
    static func symbol(for trackName: String) -> String {
        let lower = trackName.lowercased()
        if lower.hasPrefix("vid") { return SFSymbol.trackVideo }
        if lower.hasPrefix("aud") { return SFSymbol.trackAudio }
        if lower.hasPrefix("sub") { return SFSymbol.trackSubtitle }
        return SFSymbol.trackGeneric
    }
}
