import SwiftUI

/// 指标徽标：速度 / 剩余时间 / 分片计数。图标 + 文字同现，数字等宽防止跳动（design.md §3.4）。
struct StatBadgeView: View {
    let symbol: String
    let value: String
    var caption: String? = nil

    var body: some View {
        HStack(spacing: SFSpace.s1) {
            Image(systemName: symbol)
                .imageScale(.small)
                .foregroundStyle(SFColor.labelSecondary)
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(SFColor.labelSecondary)
            }
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(SFColor.label)
        }
        .lineLimit(1)
    }
}

extension StatBadgeView {
    /// 无数据一律走占位符，禁止显示 0 KB/s 这类伪值（The Real-Numbers Rule）。
    static func speed(bytesPerSecond: Double?, unknown: Bool = false) -> StatBadgeView {
        StatBadgeView(symbol: SFSymbol.speedometer,
                      value: SFValue.rate(bytesPerSecond, unknown: unknown))
    }

    static func eta(seconds: Int?) -> StatBadgeView {
        StatBadgeView(symbol: SFSymbol.statusPreparing,
                      value: SFValue.eta(seconds),
                      caption: "剩余")
    }

    static func segments(done: Int, total: Int) -> StatBadgeView {
        StatBadgeView(symbol: SFSymbol.trackGeneric,
                      value: SFValue.segments(done: done, total: total),
                      caption: "分片")
    }
}
