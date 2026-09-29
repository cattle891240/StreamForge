import SwiftUI
import AppKit

/// 设计令牌唯一真相源。The Zero-Hex Rule：本文件是唯一允许出现颜色定义的地方，
/// 且全部引用 macOS 系统语义色，零字面色值。深色模式与「增强对比度」由系统自动适配。
enum SFColor {
    static var background: Color { Color(nsColor: .windowBackgroundColor) }
    static var surface: Color { Color(nsColor: .controlBackgroundColor) }
    static var surfaceInset: Color { Color(nsColor: .textBackgroundColor) }
    static var label: Color { .primary }
    static var labelSecondary: Color { .secondary }
    static var labelTertiary: Color { Color(nsColor: .tertiaryLabelColor) }
    static var border: Color { Color(nsColor: .separatorColor) }
    static var accent: Color { .accentColor }

    static var success: Color { Color(nsColor: .systemGreen) }
    static var warning: Color { Color(nsColor: .systemOrange) }
    static var danger: Color { Color(nsColor: .systemRed) }
    static var info: Color { Color(nsColor: .systemBlue) }
    static var neutral: Color { Color(nsColor: .systemGray) }

    static var fillQuaternary: Color { Color(nsColor: .quaternaryLabelColor) }
}

enum SFSpace {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
    static let s12: CGFloat = 48
}

enum SFRadius {
    static let sm: CGFloat = 4
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
}

enum SFSize {
    static let toolbarHit: CGFloat = 32
    static let inlineHit: CGFloat = 28
    static let taskRowMinHeight: CGFloat = 56
    static let windowMinWidth: CGFloat = 820
    static let windowMinHeight: CGFloat = 520
    static let sidebarWidth: CGFloat = 200
    static let detailWidth: CGFloat = 560
    static let sheetWidth: CGFloat = 560
    static let dependencySheetWidth: CGFloat = 620
}

enum SFMotion {
    static let base: Double = 0.15
    static let sheet: Double = 0.25
}

/// 无数据占位符。The Real-Numbers Rule：禁止用 0 或编造值占位。
enum SFValue {
    static let placeholder = "—"

    static func orPlaceholder(_ value: String?) -> String {
        guard let value = value, !value.isEmpty else { return placeholder }
        return value
    }

    static func percent(_ value: Double?) -> String {
        guard let value = value, value.isFinite else { return placeholder }
        return String(format: "%.0f%%", min(max(value, 0), 100))
    }

    /// 速度为负值或未知时（内核的 `-0.00Bps`）一律降级为占位符，绝不显示负数。
    static func rate(_ bytesPerSecond: Double?, unknown: Bool) -> String {
        guard !unknown, let v = bytesPerSecond, v.isFinite, v >= 0 else { return placeholder }
        return ByteFormatter.speed(v)
    }

    static func eta(_ seconds: Int?) -> String {
        guard let seconds = seconds, seconds >= 0 else { return placeholder }
        return DurationFormatter.clock(seconds)
    }

    static func bytes(_ value: Int64?) -> String {
        guard let value = value, value >= 0 else { return placeholder }
        return ByteFormatter.bytes(value)
    }

    static func segments(done: Int, total: Int) -> String {
        guard total > 0 else { return placeholder }
        return "\(done)/\(total)"
    }
}
