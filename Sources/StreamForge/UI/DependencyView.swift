import SwiftUI
import AppKit

/// 依赖状态与修复指引（design.md 附录 A.4 / architecture.md §6）。
/// 版本号必须来自实际 `-v` 输出；每张卡只给一条推荐命令，其余收进 Menu。
struct DependencyView: View {

    @EnvironmentObject private var env: AppEnvironment

    private var tools: [ExternalTool] { ToolKind.allCases.compactMap { env.dependencies.tool($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if env.dependencies.isProbing && tools.isEmpty {
                HStack(spacing: SFSpace.s2) {
                    ProgressView().controlSize(.small)
                    Text("正在检测命令行工具...")
                        .font(.footnote)
                        .foregroundStyle(SFColor.labelSecondary)
                }
                .padding(SFSpace.s4)
            }
            ScrollView {
                LazyVStack(spacing: SFSpace.s3) {
                    ForEach(tools) { tool in
                        ToolCard(tool: tool,
                                 guidance: env.dependencies.guidance(for: tool),
                                 onInstallPathChosen: { path in chooseManualPath(tool.kind, path: path) })
                    }
                }
                .padding(SFSpace.s4)
            }
        }
        .frame(minWidth: SFSize.dependencySheetWidth, idealWidth: SFSize.dependencySheetWidth, maxWidth: SFSize.dependencySheetWidth, minHeight: 340, idealHeight: 460, maxHeight: 620)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: SFSpace.s3) {
            Text("依赖检测")
                .font(.headline)
            if let date = env.dependencies.lastProbeDate {
                (Text("上次检测：") + Text(date, style: .time))
                    .font(.caption)
                    .foregroundStyle(SFColor.labelSecondary)
            }
            Spacer()
            Button {
                env.dependencies.probe(overrides: env.settings.toolPaths)
            } label: {
                Label("重新检测", systemImage: SFSymbol.retry)
            }
            .disabled(env.dependencies.isProbing)
        }
        .padding(SFSpace.s4)
    }

    /// 手动指定路径：写回设置并立即重新探测（architecture.md §6 探测顺序第 1 项）。
    private func chooseManualPath(_ kind: ToolKind, path: String) {
        env.settings.toolPaths[kind] = path
        env.persistSettings()
        env.dependencies.probe(overrides: env.settings.toolPaths)
    }
}

// MARK: - 单张依赖卡

private struct ToolCard: View {
    let tool: ExternalTool
    let guidance: DependencyResolver.FixGuidance
    let onInstallPathChosen: (String) -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: SFSpace.s2) {
            HStack(alignment: .firstTextBaseline, spacing: SFSpace.s2) {
                Image(systemName: statusSymbol)
                    .imageScale(.large)
                    .foregroundStyle(statusColor)
                    .accessibilityHidden(true)
                Text(tool.kind.displayName)
                    .font(.headline)
                Spacer()
                Text(tool.status.displayName)
                    .font(.footnote)
                    .foregroundStyle(SFColor.labelSecondary)
            }

            Text(guidance.headline)
                .font(.footnote)
                .foregroundStyle(SFColor.label)
                .fixedSize(horizontal: false, vertical: true)

            if let path = tool.path {
                Text(path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(SFColor.labelSecondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            if !guidance.command.isEmpty {
                VStack(alignment: .leading, spacing: SFSpace.s1) {
                    Text(guidance.command)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(SFSpace.s2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SFColor.surfaceInset, in: RoundedRectangle(cornerRadius: SFRadius.sm))
                    HStack(spacing: SFSpace.s2) {
                        Button {
                            copyCommand()
                        } label: {
                            Label(copied ? "已复制" : "复制命令", systemImage: SFSymbol.copy)
                        }
                        .disabled(copied)

                        if let url = guidance.documentURL {
                            Link(destination: url) {
                                Label("打开下载页", systemImage: SFSymbol.help)
                            }
                        }
                        Button("选择文件…") {
                            if let path = PanelPicker.chooseFile(current: tool.path ?? "/usr/local/bin") {
                                onInstallPathChosen(path)
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(SFSpace.s4)
        .background(SFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: SFRadius.md))
        .overlay(RoundedRectangle(cornerRadius: SFRadius.md).stroke(SFColor.border))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tool.kind.displayName) \(tool.status.displayName)")
    }

    private var statusSymbol: String {
        switch tool.status {
        case .ok: return SFSymbol.dependencyOK
        case .notFound, .unverified: return SFSymbol.dependencyMissing
        default: return SFSymbol.dependencyBroken
        }
    }

    private var statusColor: Color {
        switch tool.status {
        case .ok: return SFColor.success
        case .notFound, .unverified: return SFColor.warning
        default: return SFColor.danger
        }
    }

    private func copyCommand() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(guidance.command, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
