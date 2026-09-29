import SwiftUI
import AppKit

/// 日志面板：等宽滚动文本 + 级别过滤 + 复制全部 + 清空 + 跳到底部（design.md §8.6 / 附录 A.1）。
/// 日志由 `LogStore` 成批合并后 bump `revision`，这里只依赖 revision，不逐行刷新。
struct LogPanelView: View {

    let task: DownloadTask
    @ObservedObject var logStore: LogStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var minimumLevel: LogLevel = .debug
    @State private var followTail = true
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: SFSpace.s2) {
            toolbar
            if logStore.isTruncated(for: task.id) {
                Text("日志超过 \(LogStore.capacity) 行，这里只显示最近 2000 行。")
                    .font(.caption)
                    .foregroundStyle(SFColor.labelSecondary)
            }
            if filtered.isEmpty {
                emptyState
            } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: SFSpace.s1) {
                        ForEach(filtered) { entry in
                            LogRowView(entry: entry).id(entry.id)
                        }
                    }
                    .padding(.vertical, SFSpace.s1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SFColor.surfaceInset)
                .overlay(RoundedRectangle(cornerRadius: SFRadius.sm).stroke(SFColor.border))
                .onChange(of: filtered.last?.id) { newest in
                    guard followTail, let newest else { return }
                    if reduceMotion {
                        proxy.scrollTo(newest, anchor: .bottom)
                    } else {
                        withAnimation(.easeOut(duration: SFMotion.base)) {
                            proxy.scrollTo(newest, anchor: .bottom)
                        }
                    }
                }
            }
            }
        }
        .accessibilityLabel("下载日志")
    }

    private var toolbar: some View {
        HStack(spacing: SFSpace.s2) {
            Picker("级别", selection: $minimumLevel) {
                Text("全部").tag(LogLevel.debug)
                Text("信息").tag(LogLevel.info)
                Text("警告").tag(LogLevel.warn)
                Text("错误").tag(LogLevel.error)
            }
            .labelsHidden()
            .frame(width: 96)
            Toggle("跟随滚动", isOn: $followTail)
                .toggleStyle(.switch)
                .controlSize(.small)
            Spacer()
            Button {
                copyAll()
            } label: {
                Label(copied ? "已复制" : "复制全部", systemImage: SFSymbol.copy)
            }
            .buttonStyle(.borderless)
            .disabled(copied || filtered.isEmpty)
            Button {
                logStore.removeAll(for: task.id)
            } label: {
                Label("清空", systemImage: SFSymbol.remove)
            }
            .buttonStyle(.borderless)
            .disabled(filtered.isEmpty)
        }
    }

    /// 读取 `revision` 建立刷新依赖：日志是成批合并写入的（design.md §9.5 坑 5）。
    private var filtered: [LogEntry] {
        _ = logStore.revision
        return logStore.visibleEntries(for: task.id).filter { $0.level.rank >= minimumLevel.rank }
    }

    private var emptyState: some View {
        Text("暂无日志输出")
            .font(.footnote)
            .foregroundStyle(SFColor.labelSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copyAll() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(logStore.plainText(for: task.id), forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
