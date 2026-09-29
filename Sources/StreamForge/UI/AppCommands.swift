import SwiftUI
import AppKit

/// 菜单栏命令（design.md §9.4 快捷键表）。动作作用于主窗口选中的任务，
/// 选中态放在 `AppEnvironment` 里，菜单与窗口共享同一份真相。
struct AppCommands: Commands {

    let env: AppEnvironment

    private var selected: DownloadTask? { env.selectedTask() }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建任务") { env.composerPresented = true }
                .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("任务") {
            Button("暂停 / 继续") { togglePauseResume() }
                .keyboardShortcut(" ", modifiers: [])
                .disabled(selected == nil)

            Button("停止（保留已下载分片）") {
                guard let id = env.selectedTaskID else { return }
                env.stopKeepingTemp(id)
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(selected?.phase.canPause != true)

            Button("重新下载") {
                guard let id = env.selectedTaskID else { return }
                env.retry(id)
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(selected == nil)

            Button("移除任务") {
                guard let id = env.selectedTaskID else { return }
                env.remove(id)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(selected == nil)

            Divider()

            Button("在访达中显示") { revealInFinder() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(selected == nil)

            Button("复制原始链接") { copySource() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(selected == nil)
        }

        CommandGroup(after: .appInfo) {
            Button("依赖状态") { env.dependencySheetPresented = true }
                .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }

    // MARK: - 动作

    private func togglePauseResume() {
        guard let task = selected else { return }
        if task.phase == .downloading || task.phase == .merging {
            guard !task.options.isLive else { return }
            env.pause(task.id)
        } else {
            env.resume(task.id)
        }
    }

    private func revealInFinder() {
        guard let task = selected else { return }
        let directory = URL(fileURLWithPath: task.saveDir)
        let candidate = directory.appendingPathComponent(task.options.saveName)
        let target = FileManager.default.fileExists(atPath: candidate.path) ? candidate : directory
        if FileManager.default.fileExists(atPath: target.path) {
            NSWorkspace.shared.activateFileViewerSelecting([target])
        } else {
            NSWorkspace.shared.open(directory)
        }
    }

    private func copySource() {
        guard let task = selected else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(task.input.argumentValue, forType: .string)
    }
}
