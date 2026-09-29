import Foundation

/// 命令行预览用转义。仅用于展示，**绝不**用于执行——
/// 实际执行走 `ProcessSpawner` 的 argv 直传，不存在 shell 注入面。
enum ShellEscaping {
    private static let safeCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_./=:,")

    static func quote(_ token: String) -> String {
        if token.isEmpty { return "''" }
        if token.allSatisfy({ safeCharacters.contains($0) }) { return token }
        let escaped = token.replacingOccurrences(of: "'", with: "'\\''")
        return "'" + escaped + "'"
    }

    static func join(_ tokens: [String]) -> String {
        tokens.map { quote($0) }.joined(separator: " ")
    }

    /// 完整命令行预览：`executable` + 经转义后的 argv，单空格连接。
    /// 与实际执行的 argv 同源（都来自 `ArgumentBuilder.buildArguments`）。
    static func commandLine(executable: String, arguments: [String]) -> String {
        join([executable] + arguments)
    }
}
