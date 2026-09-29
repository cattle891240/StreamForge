import SwiftUI
import AppKit

/// 新建任务 Sheet（design.md 附录 A.2）。高级选项用 `DisclosureGroup` 收在一屏内，不再开二级 Sheet。
struct NewTaskSheet: View {

    enum SourceMode: String, CaseIterable, Identifiable {
        case url
        case file

        var id: String { rawValue }

        var title: String {
            switch self {
            case .url: return "输入链接"
            case .file: return "选择本地文件"
            }
        }
    }

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var mode: SourceMode = .url
    @State private var urlText = ""
    @State private var filePath = ""
    @State private var saveDir = ""
    @State private var saveName = ""
    @State private var startImmediately = true
    @State private var threadCount = Defaults.threadCount
    @State private var retryCount = Defaults.downloadRetryCount
    @State private var isLive = false
    @State private var defaultsLoaded = false
    @State private var relativePathWarning = false
    @State private var sourceError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                sourceSection
                outputSection
                Section {
                    Toggle("开始后立即下载", isOn: $startImmediately)
                    DisclosureGroup("高级选项") {
                        Stepper("线程数（每个文件）：\(threadCount)", value: $threadCount, in: 1...32)
                        Stepper("失败重试次数：\(retryCount)", value: $retryCount, in: 0...10)
                        Toggle("按直播录制处理（禁用暂停）", isOn: $isLive)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            footer
        }
        .frame(width: SFSize.sheetWidth)
        .onAppear(perform: loadDefaults)
    }

    // MARK: - 区块

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("新建下载任务")
                .font(.headline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: SFSymbol.close)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, SFSpace.s4)
        .padding(.vertical, SFSpace.s3)
    }

    private var sourceSection: some View {
        Section("来源") {
            Picker("来源", selection: $mode) {
                ForEach(SourceMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: SFSpace.s1) {
                if mode == .url {
                    TextField("https://example.com/index.m3u8", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .onSubmit { urlText = trimmedURL }
                } else {
                    HStack(spacing: SFSpace.s2) {
                        Text(filePath.isEmpty ? "未选择文件" : filePath)
                            .font(.footnote)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(filePath.isEmpty ? SFColor.labelSecondary : SFColor.label)
                        Spacer()
                        Button("选择本地文件…") { chooseFile() }
                    }
                }
                if let sourceError {
                    HStack(spacing: SFSpace.s1) {
                        Image(systemName: SFSymbol.dependencyMissing).imageScale(.small)
                        Text(sourceError).font(.footnote)
                    }
                    .foregroundStyle(SFColor.danger)
                }
            }

            HStack(spacing: SFSpace.s2) {
                Button("从剪贴板粘贴") { pasteFromClipboard() }
                    .buttonStyle(.borderless)
                Spacer()
            }

            if relativePathWarning {
                HStack(alignment: .firstTextBaseline, spacing: SFSpace.s1) {
                    Image(systemName: SFSymbol.dependencyMissing)
                        .foregroundStyle(SFColor.warning)
                    Text("这个清单引用了相对路径的本地分片，建议连同分片所在目录一起放在同一文件夹下。")
                        .font(.caption)
                        .foregroundStyle(SFColor.labelSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var outputSection: some View {
        Section("输出") {
            LabeledContent("另存到") {
                HStack(spacing: SFSpace.s2) {
                    Text(saveDir)
                        .font(.footnote)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("选择目录…") { chooseDirectory() }
                }
            }
            LabeledContent("文件名模板") {
                TextField("%title_%quality", text: $saveName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("输出文件名模板")
                    .accessibilityHint("留空则按链接或文件名推导")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: SFSpace.s2) {
            Spacer()
            Button("取消") { dismiss() }
            Button("开始下载") { submit() }
                .buttonStyle(.borderedProminent)
                .disabled(!isSourceValid)
        }
        .padding(SFSpace.s4)
    }

    // MARK: - 校验与提交

    private var trimmedURL: String {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSourceValid: Bool {
        switch mode {
        case .url: return trimmedURL.hasPrefix("http://") || trimmedURL.hasPrefix("https://")
        case .file: return !filePath.isEmpty
        }
    }

    private func submit() {
        guard isSourceValid else {
            sourceError = mode == .url
                ? (trimmedURL.isEmpty ? "请填写 m3u8 链接或选择一个本地文件。" : "链接格式不正确。需要以 http:// 或 https:// 开头。")
                : "请填写 m3u8 链接或选择一个本地文件。"
            return
        }
        var options = env.settings.defaultOptions
        options.saveName = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
        options.threadCount = threadCount
        options.downloadRetryCount = retryCount
        options.isLive = isLive

        let input: InputSource
        switch mode {
        case .url: input = .url(trimmedURL)
        case .file: input = .localFile(URL(fileURLWithPath: filePath))
        }
        env.createTask(input: input,
                       options: options,
                       saveDir: saveDir,
                       saveName: options.saveName.isEmpty ? nil : options.saveName,
                       start: startImmediately)
        dismiss()
    }

    // MARK: - 面板与剪贴板

    private func loadDefaults() {
        guard !defaultsLoaded else { return }
        defaultsLoaded = true
        let options = env.settings.defaultOptions
        saveDir = env.settings.defaultSaveDir
        threadCount = options.threadCount
        retryCount = options.downloadRetryCount
        isLive = options.isLive
    }

    private func chooseDirectory() {
        if let path = PanelPicker.chooseDirectory(current: saveDir) {
            saveDir = path
            env.settings.defaultSaveDir = path
            env.persistSettings()
        }
    }

    private func chooseFile() {
        guard let path = PanelPicker.chooseFile(current: filePath) else { return }
        filePath = path
        mode = .file
        relativePathWarning = Self.usesRelativeSegments(at: path)
    }

    private func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        if let source = DropReceiver.firstSource(in: text) {
            switch source {
            case .url(let value):
                mode = .url
                urlText = value
            case .localFile(let url):
                mode = .file
                filePath = url.path
                relativePathWarning = Self.usesRelativeSegments(at: url.path)
            }
        }
    }

    /// 清单里出现非 http、非绝对路径的分片引用时给出提示（design.md 附录 A.5）。
    private static func usesRelativeSegments(at path: String) -> Bool {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("http") || line.hasPrefix("/") { continue }
            return true
        }
        return false
    }
}
