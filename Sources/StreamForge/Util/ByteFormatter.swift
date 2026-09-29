import Foundation

/// 字节与速度格式化。缺失值、负值、非有限值一律渲染为占位符，
/// 绝不把负号或 NaN 交给界面（AC-02）。
enum ByteFormatter {
    static let placeholder = "--"

    private static let base = 1024.0
    private static let units = ["B", "KB", "MB", "GB", "TB"]

    static func bytes(_ value: Int64?) -> String {
        guard let value, value >= 0 else { return placeholder }
        return format(Double(value))
    }

    static func speed(_ bytesPerSecond: Double?) -> String {
        guard let value = bytesPerSecond, value.isFinite, value >= 0 else { return placeholder }
        return format(value) + "/s"
    }

    /// 内核字节单位 → 倍数。未知单位返回 nil，由调用方按"缺失"处理。
    static func multiplier(for unit: String) -> Double? {
        switch unit.uppercased() {
        case "B": return 1
        case "KB": return base
        case "MB": return base * base
        case "GB": return base * base * base
        case "TB": return base * base * base * base
        default: return nil
        }
    }

    private static func format(_ value: Double) -> String {
        var scaled = value
        var index = 0
        while scaled >= base && index < units.count - 1 {
            scaled /= base
            index += 1
        }
        if index == 0 {
            return String(format: "%.0f %@", scaled, units[index])
        }
        return String(format: "%.2f %@", scaled, units[index])
    }
}
