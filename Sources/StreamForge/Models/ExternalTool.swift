import Foundation

enum ToolKind: String, Codable, CaseIterable {
    case nre = "N_m3u8DL-RE"
    case ffmpeg
    case mp4decrypt
    case shakaPackager = "shaka-packager"

    var executableName: String { rawValue }

    /// 探测版本用的参数。内核用 `--version`，ffmpeg 系用 `-version`。
    var versionArgument: String {
        switch self {
        case .nre: return "--version"
        default: return "-version"
        }
    }

    var isRequired: Bool {
        switch self {
        case .nre, .ffmpeg: return true
        default: return false
        }
    }

    var minimumVersion: String {
        switch self {
        case .nre: return "0.6.0"
        default: return "0.0.0"
        }
    }

    var downloadURL: String {
        switch self {
        case .nre: return "https://github.com/nilaoda/N_m3u8DL-RE/releases"
        case .ffmpeg: return "https://brew.sh"
        case .mp4decrypt: return "https://www.bento4.com/downloads/"
        case .shakaPackager: return "https://github.com/shaka-project/shaka-packager/releases"
        }
    }
}

enum ExternalToolStatus: Equatable {
    case ok
    case notFound
    case notExecutable
    case quarantined
    case archMismatch
    case unverified(String?)

    var displayName: String {
        switch self {
        case .ok: return "可用"
        case .notFound: return "未找到"
        case .notExecutable: return "不可执行"
        case .quarantined: return "被隔离"
        case .archMismatch: return "架构不匹配"
        case .unverified(let version):
            if let version { return "版本未验证（\(version)）" }
            return "版本未验证"
        }
    }

    var isUsable: Bool {
        switch self {
        case .ok, .unverified: return true
        default: return false
        }
    }
}

struct ExternalTool: Identifiable, Equatable {
    var id: ToolKind { kind }
    var kind: ToolKind
    var path: String?
    var version: String?
    var status: ExternalToolStatus
    var detail: String?

    var isUsable: Bool { status.isUsable }
}

/// 依赖探测的**纯判定逻辑**。`Services/DependencyProbe` 负责 I/O（存在性、执行、xattr），
/// 再调用本枚举把事实翻译成状态与修复指引——这样判定规则可被命令行测试覆盖。
enum ToolProbe {
    static let candidateDirectories = [
        "/usr/local/bin",
        "/opt/homebrew/bin",
        "/opt/local/bin",
        "/usr/bin",
        "/Applications"
    ]

    /// 候选路径 = 候选目录 × 可执行文件名，附加用户目录由调用方传入。
    static func candidatePaths(for kind: ToolKind, extraDirectories: [String] = []) -> [String] {
        let home = NSHomeDirectory()
        let userDirs = ["\(home)/.local/bin", "\(home)/bin", "\(home)/Applications"]
        let directories = extraDirectories + candidateDirectories + userDirs
        var seen = Set<String>()
        var result: [String] = []
        for directory in directories where !directory.isEmpty {
            let path = (directory as NSString).appendingPathComponent(kind.executableName)
            if !seen.contains(path) {
                seen.insert(path)
                result.append(path)
            }
        }
        return result
    }

    /// 从 `--version` 输出抽取版本（取首个形如 `1.2`/`1.2.3` 的片段）。
    static func parseVersion(from output: String) -> String? {
        guard let firstLine = output.split(separator: "\n").first else { return nil }
        return VersionComparator.extract(from: String(firstLine))
    }

    /// 三步校验结果 → 状态。判定顺序即优先级，勿调换。
    static func status(exists: Bool,
                       executable: Bool,
                       runsSuccessfully: Bool,
                       quarantined: Bool,
                       versionText: String?,
                       minimumVersion: String) -> ExternalToolStatus {
        if !exists { return .notFound }
        if !executable { return .notExecutable }
        if quarantined { return .quarantined }
        if !runsSuccessfully { return .archMismatch }
        guard let text = versionText, let version = parseVersion(from: text) else {
            return .unverified(nil)
        }
        if VersionComparator.isAtLeast(version, minimumVersion) { return .ok }
        return .unverified(version)
    }

    static func quarantineClearCommand(path: String) -> String {
        "xattr -dr com.apple.quarantine \(ShellEscaping.quote(path))"
    }

    /// 可一键复制的修复命令。未知状态返回 nil（界面不展示空按钮）。
    static func repairCommand(for tool: ExternalTool) -> String? {
        switch tool.status {
        case .ok:
            return nil
        case .notFound:
            switch tool.kind {
            case .nre:
                return """
                curl -L -o /tmp/NRE.tar.gz https://github.com/nilaoda/N_m3u8DL-RE/releases/download/v0.6.0-beta/N_m3u8DL-RE_v0.6.0-beta_osx-arm64_20260629.tar.gz
                tar -xzf /tmp/NRE.tar.gz -C /tmp
                sudo mkdir -p /usr/local/bin && sudo mv /tmp/N_m3u8DL-RE /usr/local/bin/
                sudo xattr -dr com.apple.quarantine /usr/local/bin/N_m3u8DL-RE
                chmod +x /usr/local/bin/N_m3u8DL-RE
                """
            case .ffmpeg:
                return "brew install ffmpeg"
            default:
                return "brew install \(tool.kind.executableName)"
            }
        case .notExecutable:
            guard let path = tool.path else { return nil }
            return "chmod +x \(ShellEscaping.quote(path))"
        case .quarantined:
            guard let path = tool.path else { return nil }
            return quarantineClearCommand(path: path)
        case .archMismatch:
            return "重新安装与本机架构匹配的 \(tool.kind.executableName)：\(tool.kind.downloadURL)"
        case .unverified:
            return "建议升级 \(tool.kind.executableName) 到 \(tool.kind.minimumVersion) 或更高：\(tool.kind.downloadURL)"
        }
    }
}
