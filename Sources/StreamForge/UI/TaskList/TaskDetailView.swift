import SwiftUI
import AppKit

/// 详情区：概览 / 分片 / 日志 三段 + 底部操作（design.md 附录 A.1 / C.3）。
/// 轨道进度分别展示，不按任务聚合，避免多轨道串台（R5）。
struct TaskDetailView: View {

    enum DetailTab: String, CaseIterable, Identifiable {
        case overview
        case tracks
        case log

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: return "概览"
            case .tracks: return "分片"
            case .log: return "日志"
            }
        }
    }

    let task: DownloadTask?
    @EnvironmentObject private var env: AppEnvironment
    @State private var tab: DetailTab = .overview

    var body: some View {
        Group {
            if let task {
                detail(task)
            } else {
                VStack(spacing: SFSpace.s2) {
                    Text("未选择任务")
                        .font(.headline)
                    Text("在左侧选中一个任务，查看分片进度与日志。")
                        .font(.footnote)
                        .foregroundStyle(SFColor.labelSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func detail(_ task: DownloadTask) -> some View {
        VStack(alignment: .leading, spacing: SFSpace.s3) {
            header(task)
            Picker("分区", selection: $tab) {
                ForEach(DetailTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch tab {
            case .overview: overview(task)
            case .tracks: trackTable(task)
            case .log: LogPanelView(task: task, logStore: env.logStore)
            }

            hints(task)
            actions(task)
        }
        .padding(SFSpace.s4)
        .frame(minWidth: 380)
    }

    private func header(_ task: DownloadTask) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SFSpace.s2) {
            Text(task.displayTitle)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            StatusPillView(phase: task.phase)
        }
    }

    // MARK: - 概览

    private func overview(_ task: DownloadTask) -> some View {
        ScrollView {
            Form {
                Section("来源") {
                    LabeledContent("地址") {
                        Text(task.input.displayText)
                            .font(.footnote)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    LabeledContent("类型") { Text(task.input.isLocalFile ? "本地清单文件" : "网络链接") }
                    LabeledContent("直播") { Text(task.options.isLive ? "是" : "否") }
                }
                Section("输出") {
                    LabeledContent("保存目录") {
                        Text(task.saveDir).font(.footnote).textSelection(.enabled).truncationMode(.middle)
                    }
                    LabeledContent("文件名模板") {
                        Text(task.options.saveName.isEmpty ? SFValue.placeholder : task.options.saveName)
                    }
                    LabeledContent("已下载 / 总大小") {
                        Text("\(SFValue.bytes(task.progress.bytesDone)) / \(SFValue.bytes(task.progress.bytesTotal))")
                            .monospacedDigit()
                    }
                    LabeledContent("线程数") { Text("\(task.options.threadCount)").monospacedDigit() }
                }
                Section("传输") {
                    LabeledContent("当前速度") {
                        Text(SFValue.rate(task.progress.speedBytesPerSecond, unknown: false)).monospacedDigit()
                    }
                    LabeledContent("已用时") { Text(DurationFormatter.clock(Int(task.elapsedSeconds()))).monospacedDigit() }
                    LabeledContent("预计剩余") { Text(SFValue.eta(task.progress.etaSeconds)).monospacedDigit() }
                    LabeledContent("重试次数") { Text("\(task.progress.retryCount)").monospacedDigit() }
                    LabeledContent("退出码") { Text(exitText(task)).monospacedDigit() }
                }
                Section("命令行") {
                    Text(env.queue.commandPreview(for: task.id) ?? SFValue.placeholder)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        copyCommand(task)
                    } label: {
                        Label("复制命令行", systemImage: SFSymbol.copy)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .formStyle(.grouped)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - 分片

    private func trackTable(_ task: DownloadTask) -> some View {
        Group {
            if task.progress.tracks.isEmpty {
                VStack(spacing: SFSpace.s2) {
                    Text("还没有分片进度")
                        .font(.headline)
                    Text("内核输出首个进度帧后，这里会按视频 / 音频 / 字幕分别列出。")
                        .font(.footnote)
                        .foregroundStyle(SFColor.labelSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(rows(of: task)) {
                    TableColumn("轨道") { row in
                        Label(row.track.name, systemImage: SFTrackIcon.symbol(for: row.track.name))
                            .lineLimit(1)
                    }
                    .width(min: 120, ideal: 160)
                    TableColumn("进度") { row in
                        ProgressBarView(phase: task.phase, fraction: row.track.percent / 100, height: 4)
                    }
                    .width(min: 80, ideal: 120)
                    TableColumn("分片") { row in
                        Text(SFValue.segments(done: row.track.done, total: row.track.total)).monospacedDigit()
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("大小") { row in
                        Text(SFValue.bytes(row.track.bytesTotal)).monospacedDigit()
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn("速度") { row in
                        Text(SFValue.rate(row.track.speedBytesPerSecond, unknown: row.track.speedUnknown)).monospacedDigit()
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn("剩余") { row in
                        Text(SFValue.eta(row.track.etaSeconds)).monospacedDigit()
                    }
                    .width(min: 60, ideal: 80)
                }
                .frame(maxHeight: 240)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 说明与操作

    @ViewBuilder
    private func hints(_ task: DownloadTask) -> some View {
        if task.options.isLive, task.phase.canPause {
            hint(SFSymbol.dependencyMissing, SFColor.warning,
                 "直播任务不支持暂停：挂起期间播放列表仍在刷新，恢复后必然丢失片段。可改用「停止」保留已下载分片。")
        }
        if case .stopped = task.phase {
            hint(SFSymbol.statusStopped, SFColor.warning,
                 "暂停超过 80 秒已自动降级为停止，已下载的分片保留在临时目录，可用「重试」继续。")
        }
        if case .finished(.failed) = task.phase, let error = task.lastError {
            hint(SFSymbol.statusFailed, SFColor.danger, error)
        }
    }

    private func hint(_ symbol: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SFSpace.s2) {
            Image(systemName: symbol).foregroundStyle(color).accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundStyle(SFColor.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actions(_ task: DownloadTask) -> some View {
        HStack(spacing: SFSpace.s2) {
            switch task.phase {
            case .preparing, .downloading, .merging:
                if !task.options.isLive {
                    Button("暂停") { env.pause(task.id) }.buttonStyle(.bordered)
                }
                Button("停止") { env.stopKeepingTemp(task.id) }.buttonStyle(.bordered)
            case .paused:
                Button("继续") { env.resume(task.id) }.buttonStyle(.borderedProminent)
                Button("停止") { env.stopKeepingTemp(task.id) }.buttonStyle(.bordered)
            case .stopped:
                Button("重试") { env.retry(task.id) }.buttonStyle(.borderedProminent)
            case .queued:
                Button("开始") { env.resume(task.id) }.buttonStyle(.borderedProminent)
            case .finished:
                Button("重新下载") { env.retry(task.id) }.buttonStyle(.borderedProminent)
                Button("在访达中显示") { reveal(task) }.buttonStyle(.bordered)
            }
            Spacer()
            Button("移除") { env.remove(task.id) }
                .buttonStyle(.bordered)
                .foregroundStyle(SFColor.danger)
        }
    }

    // MARK: - 数据

    private struct TrackRow: Identifiable {
        let id: String
        let track: TrackProgress
    }

    private func rows(of task: DownloadTask) -> [TrackRow] {
        task.progress.tracks.map { TrackRow(id: $0.name, track: $0) }
    }

    /// 终态只信退出码：0 = 完成，非 0 = 失败，被信号终止单列（ADR-004）。
    private func exitText(_ task: DownloadTask) -> String {
        if let signal = task.terminationSignal { return "信号 \(signal)" }
        guard let code = task.exitCode else { return SFValue.placeholder }
        return "\(code)"
    }

    private func copyCommand(_ task: DownloadTask) {
        guard let text = env.queue.commandPreview(for: task.id) else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
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
}
