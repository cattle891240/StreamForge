import SwiftUI

/// 高级设置：内核输出语言、URL 处理器、字幕、分片范围、实验性开关。
/// 字段与 `cli-argument-contract.md` §3.4 / §3.8 / §3.9 一一对应。
struct AdvancedSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("内核") {
                FormField("内核输出语言",
                          help: "只影响 N_m3u8DL-RE 打印到日志的语言，StreamForge 界面始终是简体中文。") {
                    Picker("", selection: $settings.defaultOptions.uiLanguage) {
                        Text("跟随内核默认").tag(Optional<DownloadOptions.UILanguage>.none)
                        Text("简体中文").tag(Optional(DownloadOptions.UILanguage.zhCN))
                        Text("繁體中文").tag(Optional(DownloadOptions.UILanguage.zhTW))
                        Text("English").tag(Optional(DownloadOptions.UILanguage.enUS))
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 200, alignment: .leading)
                }
                FormField("内核日志级别",
                          help: "DEBUG 会输出海量请求细节，足以淹没日志面板，排查问题时再开。") {
                    Picker("", selection: $settings.defaultOptions.logLevel) {
                        Text("INFO").tag(DownloadOptions.KernelLogLevel.info)
                        Text("DEBUG").tag(DownloadOptions.KernelLogLevel.debug)
                        Text("WARN").tag(DownloadOptions.KernelLogLevel.warn)
                        Text("ERROR").tag(DownloadOptions.KernelLogLevel.error)
                        Text("OFF").tag(DownloadOptions.KernelLogLevel.off)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 160, alignment: .leading)
                }
                Toggle("关闭内核启动时的更新检查", isOn: $settings.defaultOptions.disableUpdateCheck)
                Text("默认关闭检查，避免每次启动任务都产生一次意外的联网请求。")
                    .font(.caption)
                    .foregroundStyle(SFColor.labelSecondary)
            }

            Section("轨道筛选") {
                FormField("广告分片关键词",
                          help: "匹配到的分片会被跳过。这是一段正则表达式，例如 ^AD_ 。") {
                    TextField("", text: $settings.defaultOptions.adKeyword, prompt: Text("^AD_"))
                        .font(.system(.caption, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("自动选择最佳轨道", isOn: $settings.defaultOptions.autoSelect)
                Toggle("只下载字幕", isOn: $settings.defaultOptions.subOnly)
            }

            Section("字幕") {
                FormField("字幕格式") {
                    Picker("", selection: $settings.defaultOptions.subFormat) {
                        Text("SRT").tag(DownloadOptions.SubtitleFormat.srt)
                        Text("VTT").tag(DownloadOptions.SubtitleFormat.vtt)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 160, alignment: .leading)
                }
                Toggle("自动修正字幕时间轴", isOn: $settings.defaultOptions.autoSubtitleFix)
            }

            Section("范围与实验性") {
                FormField("自定义分片范围",
                          help: "形如 0-10、10-、-99 或 05:00-20:00。直播任务下无效。") {
                    TextField("", text: $settings.defaultOptions.customRange, prompt: Text("0-10"))
                        .font(.system(.caption, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("允许 HLS 多个 EXT-X-MAP", isOn: $settings.defaultOptions.allowHLSMultiExtMap)
                Text("实验性参数。仅在处理多初始化段的异常清单时开启。")
                    .font(.caption)
                    .foregroundStyle(SFColor.labelSecondary)
                FormField("URL 处理器参数",
                          help: "高阶用法：交给 URL 处理器的 key=value 参数，留空表示不使用。") {
                    TextField("", text: $settings.defaultOptions.urlProcessorArgs,
                              prompt: Text("key=value"))
                        .font(.system(.caption, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, SFSpace.s2)
    }
}
