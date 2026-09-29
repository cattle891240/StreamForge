import Foundation

/// 版本字符串比较：按 `.` 切段，数字段按数值比，非数字段按字典序比。
/// 缺位段视为 0（`0.6` 与 `0.6.0` 相等）。
enum VersionComparator {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = components(of: lhs)
        let right = components(of: rhs)
        let limit = max(left.count, right.count)
        for index in 0..<limit {
            let a = index < left.count ? left[index] : "0"
            let b = index < right.count ? right[index] : "0"
            if let x = Int(a), let y = Int(b) {
                if x != y { return x < y ? .orderedAscending : .orderedDescending }
            } else if a != b {
                return a < b ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }

    static func isAtLeast(_ version: String, _ minimum: String) -> Bool {
        compare(version, minimum) != .orderedAscending
    }

    /// 从任意文本中抽取首个形如 `1.2` / `1.2.3` 的版本号；找不到返回 nil。
    static func extract(from text: String) -> String? {
        let pattern = #"(\d+(?:\.\d+)+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let group = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[group])
    }

    private static func components(of version: String) -> [String] {
        version.split(separator: ".").map { String($0) }
    }
}
