import SwiftUI
import AppKit

extension DownloadTask {
    /// 列表与详情的展示名：优先用户指定的保存名，其次来源文件名 / 链接。
    var displayTitle: String {
        let name = options.saveName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? input.displayText : name
    }
}

/// 任务行：三行式（文件名 / 进度 / 状态+指标），行高 ≥ 56pt（design.md 附录 C.2）。
/// 颜色只出现在状态图标与进度条上；文件名、大小、速度、ETA 一律 label / labelSecondary。
struct TaskRowView: View {

    let task: DownloadTask
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        HStack(alignment: .center, spacing: SFSpace.s3) {
            VStack(alignment: .leading, spacing: SFSpace.s1) {
                titleLine
                progressLine
                statusLine
            }
            .frame(minWidth: 0)
            controls
        }
        .frame(minHeight: SFSize.taskRowMinHeight)
        .padding(.vertical, SFSpace.s1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(task.displayTitle)
        .accessibilityValue(accessibilityValue)
    }

    // MARK: - 三行

    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: SFSpace.s2) {
            Text(task.displayTitle)
                .font(.body)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(SFColor.label)
            Spacer(minLength: SFSpace.s2)
            Text(SFValue.bytes(task.progress.bytesTotal))
                .font(.system(.footnote, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(SFColor.labelSecondary)
        }
    }

    /// 已完成不显示进度条，改为一行完成摘要（design.md §4.4）。
    private var progressLine: some View {
        Group {
            if task.phase == .finished(.succeeded) {
                Text("已完成 · 用时 \(DurationFormatter.compact(Int(task.elapsedSeconds()))) · 平均 \(averageSpeed)")
                    .font(.footnote)
                    .foregroundStyle(SFColor.labelSecondary)
            } else {
                ProgressBarView(phase: task.phase, fraction: fraction)
                Spacer(minLength: 0)
            }
        }
    }

    private var statusLine: some View {
        HStack(spacing: SFSpace.s2) {
            StatusPillView(phase: task.phase)
            if task.options.isLive {
                Text("直播")
                    .font(.caption)
                    .foregroundStyle(SFColor.labelSecondary)
            }
            if task.progress.retryCount > 0 {
                Label("重试中 \(task.progress.retryCount)", systemImage: SFSymbol.retry)
                    .font(.caption)
                    .foregroundStyle(SFColor.warning)
            }
            Spacer(minLength: 0)
            StatBadgeView.speed(bytesPerSecond: task.progress.speedBytesPerSecond)
            Text("·").foregroundStyle(SFColor.labelSecondary).font(.footnote)
            StatBadgeView.eta(seconds: task.progress.etaSeconds)
            Text("·").foregroundStyle(SFColor.labelSecondary).font(.footnote)
            StatBadgeView.segments(done: task.progress.segmentDone, total: task.progress.segmentTotal)
        }
        .lineLimit(1)
    }

    // MARK: - 控制按钮

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: SFSpace.s1) {
            switch task.phase {
            case .preparing, .downloading, .merging:
                if !task.options.isLive { controlButton(SFSymbol.pause, "暂停", "暂停 \(task.displayTitle)") { env.pause(task.id) } }
                controlButton(SFSymbol.stop, "停止", "停止 \(task.displayTitle) 并保留已下载分片") { env.stopKeepingTemp(task.id) }
            case .paused:
                controlButton(SFSymbol.start, "继续", "继续 \(task.displayTitle)") { env.resume(task.id) }
                controlButton(SFSymbol.stop, "停止", "停止 \(task.displayTitle) 并保留已下载分片") { env.stopKeepingTemp(task.id) }
            case .stopped:
                controlButton(SFSymbol.retry, "重试", "重试 \(task.displayTitle)（保留已下载分片）") { env.retry(task.id) }
            case .queued:
                controlButton(SFSymbol.start, "开始", "开始 \(task.displayTitle)") { env.resume(task.id) }
            case .finished:
                controlButton(SFSymbol.reveal, "在访达中显示", "在访达中显示 \(task.displayTitle)") { reveal() }
                controlButton(SFSymbol.remove, "移除", "移除 \(task.displayTitle)") { env.remove(task.id) }
            }
        }
        .buttonStyle(.borderless)
        .imageScale(.medium)
        .foregroundStyle(SFColor.labelSecondary)
    }

    private func controlButton(_ symbol: String, _ help: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: SFSize.inlineHit, height: SFSize.inlineHit)
        }
        .help(help)
        .accessibilityLabel(label)
    }

    // MARK: - 数据

    /// 总量未知时传 nil 走不确定形态，禁止 `value / 0`（design.md §9.5 坑 4）。
    private var fraction: Double? {
        guard task.progress.segmentTotal > 0 else { return nil }
        return task.progress.percent / 100
    }

    private var averageSpeed: String {
        let seconds = task.elapsedSeconds()
        guard seconds > 0, let total = task.progress.bytesTotal else { return SFValue.placeholder }
        return SFValue.rate(Double(total) / seconds, unknown: false)
    }

    private var accessibilityValue: String {
        "\(task.phase.displayName)，已完成 \(SFValue.percent(task.progress.percent))，速度 \(SFValue.rate(task.progress.speedBytesPerSecond, unknown: false))，剩余 \(SFValue.eta(task.progress.etaSeconds))"
    }

    private func reveal() {
        let directory = URL(fileURLWithPath: task.saveDir)
        let candidate = directory.appendingPathComponent(task.options.saveName)
        if FileManager.default.fileExists(atPath: candidate.path) {
            NSWorkspace.shared.activateFileViewerSelecting([candidate])
        } else {
            NSWorkspace.shared.open(directory)
        }
    }
}
