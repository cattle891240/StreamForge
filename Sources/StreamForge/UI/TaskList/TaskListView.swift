import SwiftUI
import AppKit

/// 任务列表：行内直接呈现进度与实时数字，用户不选中也能读（design.md §7 允许 5）。
struct TaskListView: View {

    @EnvironmentObject private var env: AppEnvironment

    let filter: TaskFilter
    let searchText: String

    @State private var clipboardHasLink = false

    private var visible: [DownloadTask] {
        env.queue.tasks.filter { filter.matches($0) && matchesSearch($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let reason = env.queue.blockedReason { blockedBanner(reason) }
            ZStack {
                List(selection: $env.selectedTaskID) {
                    ForEach(visible) { task in
                        TaskRowView(task: task)
                            .tag(task.id)
                            .contextMenu { contextMenu(for: task) }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                if visible.isEmpty { emptyState }
            }
        }
        .onAppear { clipboardHasLink = Self.clipboardContainsLink() }
    }

    // MARK: - 依赖缺失横幅

    private func blockedBanner(_ reason: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SFSpace.s2) {
            Image(systemName: SFSymbol.dependencyMissing)
                .foregroundStyle(SFColor.warning)
                .accessibilityHidden(true)
            Text(reason)
                .font(.footnote)
                .foregroundStyle(SFColor.label)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("查看依赖状态") { env.dependencySheetPresented = true }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, SFSpace.s4)
        .padding(.vertical, SFSpace.s2)
        .background(SFColor.surface)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: SFSpace.s3) {
            Image(systemName: SFSymbol.emptyTray)
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(SFColor.labelTertiary)
                .accessibilityHidden(true)
            Text("还没有下载任务")
                .font(.headline)
            Text("把 .m3u8 链接或本地文件拖到这里，或按 Command-N 新建。")
                .font(.footnote)
                .foregroundStyle(SFColor.labelSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: SFSpace.s3) {
                Button("新建任务") { env.composerPresented = true }
                    .buttonStyle(.borderedProminent)
                Button("从剪贴板导入") { importFromClipboard() }
                    .disabled(!clipboardHasLink)
                if !clipboardHasLink {
                    Text("剪贴板中没有链接")
                        .font(.caption)
                        .foregroundStyle(SFColor.labelSecondary)
                }
            }
        }
        .padding(SFSpace.s8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 右键菜单

    @ViewBuilder
    private func contextMenu(for task: DownloadTask) -> some View {
        if task.phase.canPause, !task.options.isLive {
            Button("暂停") { env.pause(task.id) }
        }
        if task.phase.canResume {
            Button("重试（保留已下载分片）") { env.retry(task.id) }
        }
        if task.phase.canPause {
            Button("停止（保留已下载分片）") { env.stopKeepingTemp(task.id) }
        }
        Button("复制原始链接") { copyLink(task) }
        Button("在访达中显示") { reveal(task) }
        Divider()
        Button("移除") { env.remove(task.id) }
    }

    // MARK: - 动作

    private func matchesSearch(_ task: DownloadTask) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return task.displayTitle.localizedCaseInsensitiveContains(query)
            || task.input.displayText.localizedCaseInsensitiveContains(query)
    }

    private func copyLink(_ task: DownloadTask) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(task.input.argumentValue, forType: .string)
    }

    private func reveal(_ task: DownloadTask) {
        let directory = URL(fileURLWithPath: task.saveDir)
        let candidate = directory.appendingPathComponent(task.options.saveName)
        if FileManager.default.fileExists(atPath: candidate.path) {
            NSWorkspace.shared.activateFileViewerSelecting([candidate])
        } else {
            NSWorkspace.shared.open(directory)
        }
    }

    private func importFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              let source = DropReceiver.firstSource(in: text) else { return }
        env.createTask(input: source,
                       options: env.settings.defaultOptions,
                       saveDir: nil,
                       saveName: nil)
    }

    private static func clipboardContainsLink() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string) else { return false }
        return DropReceiver.firstSource(in: text) != nil
    }
}
