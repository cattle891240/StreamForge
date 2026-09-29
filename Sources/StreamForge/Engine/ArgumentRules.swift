import Foundation

/// 参数构建的静态校验与互斥规则。
enum ArgumentRules {

    /// AC-10：任何用户输入取值禁止以 `-` 开头，否则会被上游当成选项解析。
    /// `DownloadOptions.userProvidedValues` 已汇总全部用户输入字段。
    static func validate(_ options: DownloadOptions) throws {
        for pair in options.userProvidedValues where !pair.value.isEmpty {
            if pair.value.hasPrefix("-") {
                throw ArgumentError.leadingDash(field: pair.field)
            }
        }
    }

    /// `--use-system-proxy` 与 `--custom-proxy` 互斥（契约 §5）：
    /// 一旦填写自定义代理，系统代理强制为 False。
    static func effectiveSystemProxy(_ options: DownloadOptions) -> Bool {
        options.useSystemProxy && options.customProxy.isEmpty
    }
}
