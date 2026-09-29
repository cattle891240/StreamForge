import SwiftUI

/// 通用设置：保存目录、队列并发、通知、外观、日志留存。
/// architecture.md §8.6：全局偏好（目录 / 通知 / 外观）集中在本组。
struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("保存位置") {
                FormField("默认保存目录",
                          help: "新建任务时预先填入这里。任务创建后，它的保存目录不再随本设置变动。") {
                    HStack(spacing: SFSpace.s2) {
                        TextField("", text: $settings.defaultSaveDir, prompt: Text(Paths.defaultSaveDir()))
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                        Button { pickSaveDir() } label: {
                            Label("选择…", systemImage: SFSymbol.folder)
                        }
                    }
                }
            }

            Section("队列") {
                FormField("最大并发任务数",
                          help: "同时运行的上限。超出的任务排队等待，有任务结束后自动递补。") {
                    Stepper(value: $settings.maxConcurrentTasks, in: 1...8) {
                        Text("\(settings.maxConcurrentTasks) 个")
                    }
                }
                Toggle("取消任务时删除临时分片", isOn: $settings.deleteTempOnCancel)
                Text("关闭后保留分片目录，便于手动重试或排查。")
                    .font(.caption)
                    .foregroundStyle(SFColor.labelSecondary)
            }

            Section("通知") {
                Toggle("任务完成时通知", isOn: $settings.notifyOnSuccess)
                Toggle("任务失败时通知", isOn: $settings.notifyOnFailure)
                Text("首次投递时系统会请求授权；多条任务同时完成会合并为一条通知。")
                    .font(.caption)
                    .foregroundStyle(SFColor.labelSecondary)
            }

            Section("外观") {
                FormField("主题", help: "跟随系统会随 macOS 的浅色 / 深色切换自动变化。") {
                    Picker("", selection: $settings.appearance) {
                        Text("跟随系统").tag(AppearancePreference.system)
                        Text("浅色").tag(AppearancePreference.light)
                        Text("深色").tag(AppearancePreference.dark)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 200, alignment: .leading)
                }
            }

            Section("日志") {
                Toggle("把内核日志写入文件", isOn: kernelLogBinding)
                Text(Paths.logsRoot())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(SFColor.labelSecondary)
                    .textSelection(.enabled)
                Text("不写入文件时，日志只保留在内存里（每任务上限 \(Defaults.logBufferCapacity) 条）。")
                    .font(.caption)
                    .foregroundStyle(SFColor.labelSecondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, SFSpace.s2)
    }

    /// 全局开关与默认任务参数同源：关掉就不再给内核传 `--log-file-path`。
    private var kernelLogBinding: Binding<Bool> {
        Binding(get: { settings.keepKernelLogFile },
                set: { settings.keepKernelLogFile = $0
                       settings.defaultOptions.keepLogFile = $0 })
    }

    private func pickSaveDir() {
        if let picked = PanelPicker.chooseDirectory(current: settings.defaultSaveDir) {
            settings.defaultSaveDir = picked
        }
    }
}
