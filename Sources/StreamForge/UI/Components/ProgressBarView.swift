import SwiftUI

/// 进度条。任务行（4pt）与详情区（6pt）共用一套实现（design.md §4.4）。
/// The State-Is-Color Rule：填色只跟随任务状态，不用于装饰。
struct ProgressBarView: View {
    /// 0...1。nil 表示总量未知：走不确定形态，避免 `value / 0` 产生 NaN（design.md §9.5 坑 4）。
    let fraction: Double?
    var tint: Color = SFColor.accent
    var height: CGFloat = 4
    var dimmed: Bool = false

    var body: some View {
        Group {
            if let fraction {
                ProgressView(value: Self.clamp(fraction), total: 1.0)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.small)
            }
        }
        .frame(height: height)
        .tint(tint)
        .opacity(dimmed ? 0.6 : 1)
        .accessibilityHidden(true)
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

extension ProgressBarView {
    /// 按任务状态取色：下载中用强调色，合并中用警告色，冻结态用中性色并降透明度。
    init(phase: TaskPhase, fraction: Double?, height: CGFloat = 4) {
        switch phase {
        case .downloading:
            self.init(fraction: fraction, tint: SFColor.accent, height: height)
        case .merging:
            self.init(fraction: nil, tint: SFColor.warning, height: height)
        case .finished(.succeeded):
            self.init(fraction: 1, tint: SFColor.success, height: height)
        case .finished:
            self.init(fraction: fraction, tint: SFColor.neutral, height: height, dimmed: true)
        default:
            self.init(fraction: fraction, tint: SFColor.neutral, height: height, dimmed: true)
        }
    }
}
