import SwiftUI

/// 输出设置：保存名 / 命名模板 / 混流（`-M`）/ 合并开关。
/// 字段与 `cli-argument-contract.md` §3.6 与 §4 一一对应。
struct OutputSettingsView: View {
    @ObservedObject var settings: AppSettings

    private static let patternVariables = [
        "<SaveName>", "<Id>", "<Codecs>", "<Language>", "<Resolution>", "<Bandwidth>",
        "<MediaType>", "<Channels>", "<FrameRate>", "<VideoRange>", "<GroupId>", "<Ext>"
    ]

    var body: some View {
        Form {
            Section("文件名") {
                FormField("默认保存名",
                          help: "留空时按链接末段推导。重试任务必须与首次完全一致，否则无法复用已下载的分片。") {
                    TextField("", text: $settings.defaultOptions.saveName, prompt: Text("由链接推导"))
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                }
                FormField("命名模板",
                          help: "用于多轨道输出的子文件名。建议至少包含一个唯一变量（如 <Id>），避免轨道同名互相覆盖。") {
                    TextField("", text: $settings.defaultOptions.savePattern,
                              prompt: Text("<SaveName>.<Resolution>.<Ext>"))
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                }
                Menu("插入变量") {
                    ForEach(Self.patternVariables, id: \.self) { variable in
                        Button(variable) { settings.defaultOptions.savePattern += variable }
                    }
                }
                .menuStyle(.borderlessButton)
            }

            Section("混流") {
                Toggle("完成后混流为单一文件", isOn: muxEnabled)
                if !settings.defaultOptions.muxAfterDone.isEmpty {
                    FormField("容器格式") {
                        Picker("", selection: muxFormat) {
                            Text("mp4").tag("mp4")
                            Text("mkv").tag("mkv")
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 160, alignment: .leading)
                    }
                    FormField("混流器", help: "mkvmerge 需要单独安装，并在下方填写它的路径。") {
                        Picker("", selection: muxMuxer) {
                            Text("ffmpeg").tag("ffmpeg")
                            Text("mkvmerge").tag("mkvmerge")
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 160, alignment: .leading)
                    }
                    FormField("混流器路径",
                              help: "路径里若含冒号需要转义，建议把二进制放在不含冒号的目录下。") {
                        TextField("", text: muxBinPath, prompt: Text("留空则自动查找"))
                            .textFieldStyle(.roundedBorder)
                    }
                    Toggle("混流时跳过字幕", isOn: muxSkipSub)
                    Toggle("混流后保留源文件", isOn: muxKeep)
                    muxImportSection
                }
            }

            Section("合并") {
                Toggle("只下载分片，不合并", isOn: $settings.defaultOptions.skipMerge)
                Text("开启后不调用 ffmpeg，输出目录里只有分片文件。")
                    .font(.caption)
                    .foregroundStyle(SFColor.labelSecondary)
                Toggle("使用二进制合并", isOn: $settings.defaultOptions.binaryMerge)
                Toggle("ffmpeg 合并时用 concat 分离器", isOn: $settings.defaultOptions.useFFmpegConcatDemuxer)
                FormField("ffmpeg 路径", help: "留空则使用依赖检测找到的 ffmpeg。") {
                    HStack(spacing: SFSpace.s2) {
                        TextField("", text: $settings.defaultOptions.ffmpegBinaryPath,
                                  prompt: Text("/opt/homebrew/bin/ffmpeg"))
                            .textFieldStyle(.roundedBorder)
                        Button { pickFFmpeg() } label: {
                            Label("选择…", systemImage: SFSymbol.toolFilm)
                        }
                    }
                }
            }

            Section("元数据") {
                Toggle("写入 meta.json", isOn: $settings.defaultOptions.writeMetaJSON)
                Toggle("文件名不加日期信息", isOn: $settings.defaultOptions.noDateInfo)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, SFSpace.s2)
    }

    @ViewBuilder
    private var muxImportSection: some View {
        ForEach(0..<settings.defaultOptions.muxImports.count, id: \.self) { index in
            HStack(spacing: SFSpace.s2) {
                Image(systemName: SFSymbol.headerList)
                    .imageScale(.small)
                    .foregroundStyle(SFColor.labelSecondary)
                TextField("外部轨道（--mux-import）", text: muxImportBinding(at: index))
                    .font(.system(.caption, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                Button { removeMuxImport(at: index) } label: {
                    Image(systemName: SFSymbol.remove)
                }
                .buttonStyle(.borderless)
            }
        }
        Button { settings.defaultOptions.muxImports.append("") } label: {
            Label("添加外部轨道", systemImage: SFSymbol.newTask)
        }
        .buttonStyle(.borderless)
    }

    private func pickFFmpeg() {
        if let picked = PanelPicker.chooseFile(current: settings.defaultOptions.ffmpegBinaryPath) {
            settings.defaultOptions.ffmpegBinaryPath = picked
        }
    }

    // MARK: - `-M` 复合参数的分量绑定

    private var muxEnabled: Binding<Bool> {
        Binding(get: { !settings.defaultOptions.muxAfterDone.isEmpty },
                set: { settings.defaultOptions.muxAfterDone = $0 ? MuxSetting(raw: "format=mp4").raw : "" })
    }

    private var muxFormat: Binding<String> {
        Binding(get: { MuxSetting(raw: settings.defaultOptions.muxAfterDone).format },
                set: { newValue in
                    var parsed = MuxSetting(raw: settings.defaultOptions.muxAfterDone)
                    parsed.format = newValue == "mkv" ? "mkv" : "mp4"
                    settings.defaultOptions.muxAfterDone = parsed.raw
                })
    }

    private var muxMuxer: Binding<String> {
        Binding(get: { MuxSetting(raw: settings.defaultOptions.muxAfterDone).muxer },
                set: { newValue in
                    var parsed = MuxSetting(raw: settings.defaultOptions.muxAfterDone)
                    parsed.muxer = newValue == "mkvmerge" ? "mkvmerge" : "ffmpeg"
                    settings.defaultOptions.muxAfterDone = parsed.raw
                })
    }

    private var muxBinPath: Binding<String> {
        Binding(get: { MuxSetting(raw: settings.defaultOptions.muxAfterDone).binPath },
                set: { newValue in
                    var parsed = MuxSetting(raw: settings.defaultOptions.muxAfterDone)
                    parsed.binPath = newValue
                    settings.defaultOptions.muxAfterDone = parsed.raw
                })
    }

    private var muxSkipSub: Binding<Bool> {
        Binding(get: { MuxSetting(raw: settings.defaultOptions.muxAfterDone).skipSub },
                set: { newValue in
                    var parsed = MuxSetting(raw: settings.defaultOptions.muxAfterDone)
                    parsed.skipSub = newValue
                    settings.defaultOptions.muxAfterDone = parsed.raw
                })
    }

    private var muxKeep: Binding<Bool> {
        Binding(get: { MuxSetting(raw: settings.defaultOptions.muxAfterDone).keep },
                set: { newValue in
                    var parsed = MuxSetting(raw: settings.defaultOptions.muxAfterDone)
                    parsed.keep = newValue
                    settings.defaultOptions.muxAfterDone = parsed.raw
                })
    }

    private func muxImportBinding(at index: Int) -> Binding<String> {
        Binding(get: {
            index < settings.defaultOptions.muxImports.count ? settings.defaultOptions.muxImports[index] : ""
        }, set: { newValue in
            guard index < settings.defaultOptions.muxImports.count else { return }
            settings.defaultOptions.muxImports[index] = newValue
        })
    }

    private func removeMuxImport(at index: Int) {
        guard index < settings.defaultOptions.muxImports.count else { return }
        settings.defaultOptions.muxImports.remove(at: index)
    }
}

/// `-M format=mp4:muxer=ffmpeg:bin_path=PATH:skip_sub=BOOL:keep=BOOL` 的结构化读写。
/// 布尔分量按契约 §1.3 输出 `True` / `False` 字面值。
private struct MuxSetting {
    var enabled = false
    var format = "mp4"
    var muxer = "ffmpeg"
    var binPath = ""
    var skipSub = false
    var keep = false

    init(raw: String) {
        guard !raw.isEmpty else { return }
        enabled = true
        for pair in raw.split(separator: ":").map(String.init) {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "format": format = kv[1]
            case "muxer": muxer = kv[1]
            case "bin_path": binPath = kv[1]
            case "skip_sub": skipSub = kv[1].lowercased() == "true"
            case "keep": keep = kv[1].lowercased() == "true"
            default: break
            }
        }
    }

    var raw: String {
        guard enabled else { return "" }
        var parts = ["format=\(format)", "muxer=\(muxer)"]
        if !binPath.isEmpty { parts.append("bin_path=\(binPath)") }
        parts.append("skip_sub=\(skipSub ? "True" : "False")")
        parts.append("keep=\(keep ? "True" : "False")")
        return parts.joined(separator: ":")
    }
}
