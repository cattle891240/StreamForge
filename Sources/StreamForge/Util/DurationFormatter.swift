import Foundation

/// 时长格式化与解析。内核 ETA 可能是 `--:--:--`，一律解析为 nil 并渲染为 `--`。
enum DurationFormatter {
    static let placeholder = "--"

    /// 秒 → `HH:MM:SS`（不足 1 小时也补零，等宽对齐）。nil 或负值 → `--`。
    static func eta(_ seconds: Int?) -> String {
        guard let seconds, seconds >= 0 else { return placeholder }
        return clock(seconds)
    }

    static func clock(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        let h = safe / 3600
        let m = (safe % 3600) / 60
        let s = safe % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    /// 紧凑形态：超过 1 小时用 `H:MM:SS`，否则 `M:SS`。
    static func compact(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        if safe >= 3600 { return clock(safe) }
        return String(format: "%d:%02d", safe / 60, safe % 60)
    }

    /// `HH:MM:SS` → 秒。`--:--:--` 或格式不符 → nil。
    static func parseClock(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var total = 0
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            total = total * 60 + value
        }
        return total
    }
}
