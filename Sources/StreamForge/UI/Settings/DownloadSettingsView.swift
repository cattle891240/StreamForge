import SwiftUI

/// 下载设置：线程数 / 重试 / 超时 / 限速 / 并发下载 / 上游默认 true 的开关。
/// 字段与 `cli-argument-contract.md` §3.2、§3.6 一一对应。
struct DownloadSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("传输") {
                FormField("线程数（每个文件）",
                          help: "单个文件内的并发连接数。站点限速严格或容易 403 时调低更稳。") {
                    Stepper(value: $settings.defaultOptions.threadCount, in: 1...32) {
                        Text("\(settings.defaultOptions.threadCount) 线程")
                    }
                }
                FormField("失败重试次数",
                          help: "单个分片下载失败后的重试次数，0 表示不重试直接失败。") {
                    Stepper(value: $settings.defaultOptions.downloadRetryCount, in: 0...20) {
                        Text("\(settings.defaultOptions.downloadRetryCount) 次")
                    }
                }
                FormField("请求超时（秒）",
                          help: "与暂停强相关：暂停持续超过这个值，在途请求会被服务端断开。ADR-003 的 80 秒守卫据此计算。") {
                    Stepper(value: $settings.defaultOptions.httpRequestTimeout, in: 10...600, step: 5) {
                        Text("\(settings.defaultOptions.httpRequestTimeout) 秒")
                    }
                }
            }

            Section("限速") {
                Toggle("限制下载速度", isOn: speedLimitEnabled)
                if !settings.defaultOptions.maxSpeed.isEmpty {
                    FormField("上限",
                              help: "限速是启动参数：改动只对之后新建的任务生效，正在跑的任务不受影响。") {
                        HStack(spacing: SFSpace.s2) {
                            Slider(value: speedLimitValue, in: 1...200, step: 1)
                            Picker("", selection: speedLimitUnit) {
                                Text("MB/s").tag("M")
                                Text("KB/s").tag("K")
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 88)
                            Text(SpeedLimit.text(settings.defaultOptions.maxSpeed))
                                .font(.system(.footnote, design: .monospaced))
                                .monospacedDigit()
                                .frame(width: 76, alignment: .trailing)
                        }
                    }
                }
            }

            Section("并发与校验") {
                Toggle("同时下载音视频字幕轨", isOn: $settings.defaultOptions.concurrentDownload)
                Text("开启后各轨道并行拉取，速度更快，内存与连接数占用也更高。")
                    .font(.caption)
                    .foregroundStyle(SFColor.labelSecondary)
                Toggle("完成后删除临时分片", isOn: $settings.defaultOptions.delAfterDone)
                Text("内核默认开启。关闭可保留分片用于排查，但会占用磁盘。")
                    .font(.caption)
                    .foregroundStyle(SFColor.labelSecondary)
                Toggle("校验分片数量", isOn: $settings.defaultOptions.checkSegmentsCount)
                Text("内核默认开启。关闭后可以下载分片清单不完整的源，代价是可能缺片。")
                    .font(.caption)
                    .foregroundStyle(SFColor.labelSecondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, SFSpace.s2)
    }

    private var speedLimitEnabled: Binding<Bool> {
        Binding(get: { !settings.defaultOptions.maxSpeed.isEmpty },
                set: { settings.defaultOptions.maxSpeed = $0 ? "15M" : "" })
    }

    private var speedLimitValue: Binding<Double> {
        Binding(get: { SpeedLimit.value(settings.defaultOptions.maxSpeed) },
                set: { settings.defaultOptions.maxSpeed =
                       SpeedLimit.compose(value: $0, unit: SpeedLimit.unit(settings.defaultOptions.maxSpeed)) })
    }

    private var speedLimitUnit: Binding<String> {
        Binding(get: { SpeedLimit.unit(settings.defaultOptions.maxSpeed) },
                set: { settings.defaultOptions.maxSpeed =
                       SpeedLimit.compose(value: SpeedLimit.value(settings.defaultOptions.maxSpeed), unit: $0) })
    }
}

/// 内核限速形如 `15M` / `100K`（契约 §3.2）。UI 只做数字与单位的拆分组合，不引入额外状态。
private enum SpeedLimit {
    static let units = ["M", "K"]

    static func value(_ raw: String) -> Double {
        guard let last = raw.last, units.contains(String(last)) else { return 15 }
        return min(max(Double(raw.dropLast()) ?? 15, 1), 200)
    }

    static func unit(_ raw: String) -> String {
        guard let last = raw.last, units.contains(String(last)) else { return "M" }
        return String(last)
    }

    static func compose(value: Double, unit: String) -> String {
        "\(Int(min(max(value, 1), 200)))\(unit)"
    }

    static func text(_ raw: String) -> String {
        "\(Int(value(raw))) \(unit(raw) == "M" ? "MB" : "KB")/s"
    }
}
