import Foundation

/// 内核阶段提示。关键词只用于**展示**，终态一律以退出码判定（kernel-output-contract §5）。
enum PhaseHint: Equatable {
    case preparing
    case downloading
    case merging
}

/// 错误关键词 → 用户可懂的中文修复提示（kernel-output-contract §5）。
/// 所有关键词与提示文案集中在此，禁止散落到视图层。
enum LogHints {

    private struct Rule {
        let pattern: String
        let hint: String
    }

    /// 顺序即优先级：先命中者胜出。
    private static let rules: [Rule] = [
        Rule(pattern: "unhandled exception",
             hint: "内核未捕获异常：通常是首个分片下载失败，检查链接、请求头与 Cookie 后重试。"),
        Rule(pattern: "403",
             hint: "服务器拒绝访问（403）：检查请求头（-H）中的 Referer 与 Cookie 是否完整。"),
        Rule(pattern: "401",
             hint: "未授权（401）：检查请求头中的 Authorization 或 Cookie 是否仍有效。"),
        Rule(pattern: "404",
             hint: "资源不存在（404）：链接已失效，或 --base-url 填写有误。"),
        Rule(pattern: "timed out",
             hint: "请求超时：提高「HTTP 请求超时」，或降低线程数后重试。"),
        Rule(pattern: "timeout",
             hint: "请求超时：提高「HTTP 请求超时」，或降低线程数后重试。"),
        Rule(pattern: "no space left",
             hint: "磁盘空间不足：清理保存目录所在磁盘后重试。"),
        Rule(pattern: "access denied",
             hint: "没有写入权限：更换保存目录或临时目录后重试。"),
        Rule(pattern: "could not find file",
             hint: "分片文件缺失：临时目录被清理或写入失败，重试该任务即可。"),
        Rule(pattern: "decrypt",
             hint: "解密失败：检查解密 Key（KID:KEY）与解密引擎二进制路径。"),
        Rule(pattern: "ffmpeg",
             hint: "ffmpeg 调用失败：在「设置 - 解密」填写正确的 ffmpeg 路径，或勾选「跳过合并」。"),
        Rule(pattern: "quarantine",
             hint: "二进制被 Gatekeeper 隔离：执行 xattr -dr com.apple.quarantine <路径> 后重试。"),
        Rule(pattern: "segment download failed",
             hint: "分片下载失败：内核会自动重试；持续失败时降低线程数或检查网络。")
    ]

    private static let phaseRules: [(pattern: String, phase: PhaseHint)] = [
        ("loading url", .preparing),
        ("parsing streams", .preparing),
        ("start downloading", .downloading),
        ("decrypting", .merging),
        ("merging", .merging)
    ]

    /// 返回首条命中的修复提示；无命中返回 nil（界面不展示气泡）。
    static func hint(for message: String) -> String? {
        guard !message.isEmpty else { return nil }
        let lower = message.lowercased()
        for rule in rules where lower.contains(rule.pattern) { return rule.hint }
        return nil
    }

    /// 日志文本 → 阶段提示。批量解析时取**最后**一条命中，保证阶段只前进。
    static func phaseHint(for message: String) -> PhaseHint? {
        guard !message.isEmpty else { return nil }
        let lower = message.lowercased()
        var found: PhaseHint?
        for rule in phaseRules where lower.contains(rule.pattern) { found = rule.phase }
        return found
    }
}
