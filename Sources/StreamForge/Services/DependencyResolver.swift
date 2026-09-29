import Foundation
import Combine

/// 外部依赖探测、校验与修复指引（architecture.md §6）。
/// 探测顺序：用户显式路径 → 上次成功路径 → 候选目录 × 文件名 → PATH 逐段。
/// 每步校验：可执行 → 能跑起来（2s 超时）→ 隔离属性。
final class DependencyResolver: ObservableObject {

    static let minVerifiedVersion = "0.6.0"

    @Published private(set) var tools: [ToolKind: ExternalTool] = [:]
    @Published private(set) var isProbing = false
    @Published private(set) var lastProbeDate: Date?

    private let fileManager = FileManager.default
    private var lastGoodPaths: [ToolKind: String] = [:]

    init() {}

    // MARK: - 探测

    func probe(overrides: [ToolKind: String], completion: (() -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in self?.isProbing = true }
        let queue = DispatchQueue(label: "com.streamforge.dependency", qos: .utility)
        let snapshot = overrides
        queue.async { [weak self] in
            guard let self = self else { return }
            var result: [ToolKind: ExternalTool] = [:]
            for kind in ToolKind.allCases {
                let tool = self.probeOne(kind: kind, override: snapshot[kind])
                if let path = tool.path { self.lastGoodPaths[kind] = path }
                result[kind] = tool
            }
            DispatchQueue.main.async {
                self.tools = result
                self.isProbing = false
                self.lastProbeDate = Date()
                completion?()
            }
        }
    }

    func tool(_ kind: ToolKind) -> ExternalTool? { tools[kind] }

    /// 必需依赖缺失集合。N_m3u8DL-RE 恒必需；ffmpeg 只在需要合并时必需（由调用方判断）。
    var missingRequired: [ExternalTool] {
        ToolKind.allCases.compactMap { kind in
            guard kind == .nre || kind == .ffmpeg else { return nil }
            guard let tool = tools[kind] else { return nil }
            switch tool.status {
            case .ok: return nil
            default: return tool
            }
        }
    }

    var downloadEngineReady: Bool {
        guard let tool = tools[.nre] else { return false }
        return tool.status == .ok
    }

    func resolvedExecutable(_ kind: ToolKind) -> String? {
        guard let tool = tools[kind], tool.status == .ok else { return nil }
        return tool.path
    }

    // MARK: - 单步探测

    private func probeOne(kind: ToolKind, override: String?) -> ExternalTool {
        let candidates = candidatePaths(for: kind, override: override)
        guard let path = candidates.first(where: { isExecutable(at: $0) }) else {
            return ExternalTool(kind: kind, status: .notFound)
        }
        if isQuarantined(at: path) {
            return ExternalTool(kind: kind, path: path, status: .quarantined)
        }
        guard let rawVersion = runVersionProbe(kind: kind, path: path) else {
            return ExternalTool(kind: kind, path: path, status: .notExecutable)
        }
        let version = extractVersion(rawVersion)
        guard let version = version else {
            return ExternalTool(kind: kind, path: path, status: .unverified(rawVersion))
        }
        if VersionComparator.compare(version, DependencyResolver.minVerifiedVersion) == .orderedAscending {
            return ExternalTool(kind: kind, path: path, version: version, status: .unverified(version))
        }
        return ExternalTool(kind: kind, path: path, version: version, status: .ok)
    }

    private func candidatePaths(for kind: ToolKind, override: String?) -> [String] {
        var paths: [String] = []
        if let override = override, !override.isEmpty { paths.append(override) }
        if let cached = lastGoodPaths[kind] { paths.append(cached) }
        let dirs = ["/usr/local/bin", "/opt/homebrew/bin", "/opt/local/bin",
                    NSHomeDirectory() + "/.local/bin", NSHomeDirectory() + "/bin",
                    "/Applications", NSHomeDirectory() + "/Applications", "/usr/bin"]
        for dir in dirs {
            for name in kind.executableNames {
                paths.append((dir as NSString).appendingPathComponent(name))
            }
        }
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for segment in envPath.split(separator: ":") {
            for name in kind.executableNames {
                paths.append((String(segment) as NSString).appendingPathComponent(name))
            }
        }
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    private func isExecutable(at path: String) -> Bool {
        fileManager.isExecutableFile(atPath: path) && access(path, X_OK) == 0
    }

    private func isQuarantined(at path: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        task.arguments = ["-p", "com.apple.quarantine", path]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    /// 版本探测：内核 `--version`，ffmpeg `-version`，2 秒超时。
    private func runVersionProbe(kind: ToolKind, path: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = kind.versionArguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }

        let semaphore = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            task.waitUntilExit()
            group.leave()
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 2) == .timedOut {
            task.terminate()
            return nil
        }
        group.wait()
        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.components(separatedBy: .newlines).first
    }

    private func extractVersion(_ raw: String?) -> String? {
        guard let raw = raw else { return nil }
        let pattern = #"(\d+\.\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let range = Range(match.range(at: 1), in: raw) else { return nil }
        return String(raw[range])
    }

    // MARK: - 修复指引

    struct FixGuidance {
        let headline: String
        let command: String
        let documentURL: URL?
    }

    /// 每张卡只给一条推荐命令（认知负荷：一个决策点可见选项不超过 4 个）。
    func guidance(for tool: ExternalTool) -> FixGuidance {
        switch tool.status {
        case .ok:
            return FixGuidance(headline: "已就绪", command: "", documentURL: nil)
        case .notFound:
            return FixGuidance(headline: tool.kind.missingHeadline,
                               command: tool.kind.installCommand,
                               documentURL: tool.kind.documentURL)
        case .notExecutable:
            return FixGuidance(headline: "找到文件但无法执行。可能是架构不匹配或缺少执行权限。",
                               command: "chmod +x \(tool.path ?? "<路径>")",
                               documentURL: tool.kind.documentURL)
        case .quarantined:
            return FixGuidance(headline: "被 Gatekeeper 隔离，macOS 会阻止它启动。",
                               command: "sudo xattr -dr com.apple.quarantine \(tool.path ?? "<路径>")",
                               documentURL: nil)
        case .unverified(let version):
            return FixGuidance(headline: "检测到 \(tool.kind.displayName) \(version ?? "未知版本")，需要 \(DependencyResolver.minVerifiedVersion) 或更高。",
                               command: tool.kind.installCommand,
                               documentURL: tool.kind.documentURL)
        case .archMismatch:
            return FixGuidance(headline: "二进制架构与本机不匹配。请下载与本机芯片一致的版本。",
                               command: tool.kind.installCommand,
                               documentURL: tool.kind.documentURL)
        }
    }
}

extension ToolKind {
    var displayName: String {
        switch self {
        case .nre: return "N_m3u8DL-RE"
        case .ffmpeg: return "ffmpeg"
        case .mp4decrypt: return "mp4decrypt"
        case .shakaPackager: return "shaka-packager"
        }
    }

    var executableNames: [String] {
        switch self {
        case .nre: return ["N_m3u8DL-RE"]
        case .ffmpeg: return ["ffmpeg"]
        case .mp4decrypt: return ["mp4decrypt"]
        case .shakaPackager: return ["shaka-packager", "packager"]
        }
    }

    var versionArguments: [String] {
        switch self {
        case .nre: return ["--version"]
        default: return ["-version"]
        }
    }

    var missingHeadline: String {
        switch self {
        case .nre: return "未找到 N_m3u8DL-RE。StreamForge 需要它来分析 m3u8 清单。"
        case .ffmpeg: return "未找到 ffmpeg。合并音视频需要它，缺失时只下载分片不合并。"
        case .mp4decrypt: return "未找到 mp4decrypt。解密引擎选择 MP4DECRYPT 时需要它。"
        case .shakaPackager: return "未找到 shaka-packager。解密引擎选择 SHAKA_PACKAGER 时需要它。"
        }
    }

    var installCommand: String {
        switch self {
        case .nre: return "brew install nilaoda/x/n_m3u8dl-re"
        case .ffmpeg: return "brew install ffmpeg"
        case .mp4decrypt: return "brew install bento4"
        case .shakaPackager: return "brew install shaka-packager"
        }
    }

    var documentURL: URL? {
        switch self {
        case .nre: return URL(string: "https://github.com/nilaoda/N_m3u8DL-RE/releases")
        case .ffmpeg: return URL(string: "https://brew.sh")
        case .mp4decrypt: return URL(string: "https://www.bento4.com/downloads/")
        case .shakaPackager: return URL(string: "https://github.com/shaka-project/shaka-packager/releases")
        }
    }
}
