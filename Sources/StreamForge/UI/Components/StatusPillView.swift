import SwiftUI

/// 状态胶囊：图标 + 中文状态词。状态不用 `.badge()`（macOS 列表里 badge 语义偏计数，design.md §4.5）。
struct StatusPillView: View {
    let symbol: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: SFSpace.s1) {
            Image(systemName: symbol).imageScale(.small)
            Text(text).font(.footnote).fontWeight(.medium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, SFSpace.s2)
        .padding(.vertical, SFSpace.s1)
        .background(color.opacity(0.12), in: Capsule())
    }
}

extension StatusPillView {
    /// 八态映射见 SPEC §8。颜色只用五个语义色，不与强调色混淆。
    init(phase: TaskPhase) {
        switch phase {
        case .queued, .preparing:
            self.init(symbol: SFSymbol.statusPreparing, text: phase.displayName, color: SFColor.neutral)
        case .downloading:
            self.init(symbol: SFSymbol.statusDownloading, text: phase.displayName, color: SFColor.accent)
        case .paused:
            self.init(symbol: SFSymbol.statusPaused, text: phase.displayName, color: SFColor.neutral)
        case .stopped:
            self.init(symbol: SFSymbol.statusStopped, text: phase.displayName, color: SFColor.warning)
        case .merging:
            self.init(symbol: SFSymbol.statusMerging, text: phase.displayName, color: SFColor.warning)
        case .finished(.succeeded):
            self.init(symbol: SFSymbol.statusDone, text: phase.displayName, color: SFColor.success)
        case .finished(.failed):
            self.init(symbol: SFSymbol.statusFailed, text: phase.displayName, color: SFColor.danger)
        case .finished(.cancelled):
            self.init(symbol: SFSymbol.statusCanceled, text: phase.displayName, color: SFColor.neutral)
        }
    }
}
