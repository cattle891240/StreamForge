import Foundation

/// 目录约定。所有目录在首次使用时创建；不做沙箱（需要执行任意外部二进制并写用户自选目录）。
enum Paths {
    static func cachesRoot() -> String {
        directory(base: .cachesDirectory, name: Defaults.cachesFolderName)
    }

    static func applicationSupportRoot() -> String {
        directory(base: .applicationSupportDirectory, name: Defaults.appSupportFolderName)
    }

    static func logsRoot() -> String {
        directory(base: .libraryDirectory, name: "Logs/" + Defaults.logsFolderName)
    }

    /// 每任务独立 tmp：便于取消后清理与重试复用（ADR-003 要求重试时路径完全一致）。
    static func tmpDir(taskID: UUID) -> String {
        (cachesRoot() as NSString).appendingPathComponent("tmp/" + taskID.uuidString)
    }

    static func defaultSaveDir() -> String {
        let home = NSHomeDirectory()
        return (home as NSString).appendingPathComponent(Defaults.saveDirRelativePath)
    }

    static func logFile(taskID: UUID) -> String {
        (logsRoot() as NSString).appendingPathComponent(taskID.uuidString + ".log")
    }

    static func historyFile() -> String {
        (applicationSupportRoot() as NSString).appendingPathComponent(Defaults.historyFileName)
    }

    static func ensureExists(_ path: String) {
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            try? FileManager.default.createDirectory(atPath: path,
                                                     withIntermediateDirectories: true)
        }
    }

    /// 由 URL 推导默认保存名：取末段文件名去扩展名，失败时退化为时间戳。
    static func derivedSaveName(from input: InputSource) -> String {
        let raw: String
        switch input {
        case .url(let value):
            guard let url = URL(string: value) else { return "streamforge" }
            raw = url.lastPathComponent.isEmpty ? url.host ?? "streamforge" : url.lastPathComponent
        case .localFile(let url):
            raw = url.lastPathComponent
        }
        let trimmed = (raw as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "streamforge" : trimmed
    }

    private static func directory(base: FileManager.SearchPathDirectory, name: String) -> String {
        let roots = NSSearchPathForDirectoriesInDomains(base, .userDomainMask, true)
        let root = roots.first ?? NSTemporaryDirectory()
        return (root as NSString).appendingPathComponent(name)
    }
}
