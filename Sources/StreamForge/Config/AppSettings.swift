import Foundation
import Combine

enum AppearancePreference: String, Codable, CaseIterable {
    case system
    case light
    case dark
}

/// 全局设置。**禁止 import SwiftUI**（AC-15）：仅依赖 Combine 的 ObservableObject。
final class AppSettings: ObservableObject {
    /// 持久化快照。与 `@Published` 字段一一对应，避免给每个属性写 Codable 样板。
    struct Snapshot: Codable, Equatable {
        var maxConcurrentTasks: Int = Defaults.maxConcurrentTasks
        var defaultSaveDir: String = Paths.defaultSaveDir()
        var deleteTempOnCancel: Bool = true
        var appearance: AppearancePreference = .system
        var notifyOnSuccess: Bool = true
        var notifyOnFailure: Bool = true
        var keepKernelLogFile: Bool = false
        var toolPaths: [ToolKind: String] = [:]
        var defaultOptions: DownloadOptions = DownloadOptions()
    }

    @Published var maxConcurrentTasks: Int = Defaults.maxConcurrentTasks
    @Published var defaultSaveDir: String = Paths.defaultSaveDir()
    @Published var deleteTempOnCancel: Bool = true
    @Published var appearance: AppearancePreference = .system
    @Published var notifyOnSuccess: Bool = true
    @Published var notifyOnFailure: Bool = true
    @Published var keepKernelLogFile: Bool = false
    @Published var toolPaths: [ToolKind: String] = [:]
    @Published var defaultOptions: DownloadOptions = DownloadOptions()

    var snapshot: Snapshot {
        Snapshot(maxConcurrentTasks: clampedConcurrency,
                 defaultSaveDir: defaultSaveDir,
                 deleteTempOnCancel: deleteTempOnCancel,
                 appearance: appearance,
                 notifyOnSuccess: notifyOnSuccess,
                 notifyOnFailure: notifyOnFailure,
                 keepKernelLogFile: keepKernelLogFile,
                 toolPaths: toolPaths,
                 defaultOptions: defaultOptions)
    }

    /// 并发上限硬夹在 1...8，避免 UI 输入异常值导致队列永远空转。
    var clampedConcurrency: Int {
        min(max(maxConcurrentTasks, 1), 8)
    }

    func apply(_ snapshot: Snapshot) {
        maxConcurrentTasks = snapshot.maxConcurrentTasks
        defaultSaveDir = snapshot.defaultSaveDir
        deleteTempOnCancel = snapshot.deleteTempOnCancel
        appearance = snapshot.appearance
        notifyOnSuccess = snapshot.notifyOnSuccess
        notifyOnFailure = snapshot.notifyOnFailure
        keepKernelLogFile = snapshot.keepKernelLogFile
        toolPaths = snapshot.toolPaths
        defaultOptions = snapshot.defaultOptions
    }

    func toolPath(for kind: ToolKind) -> String? {
        if let configured = toolPaths[kind], !configured.isEmpty { return configured }
        return nil
    }
}
