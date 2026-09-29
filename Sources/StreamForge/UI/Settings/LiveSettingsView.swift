import SwiftUI

/// 直播设置。字段与 `cli-argument-contract.md` §3.7 一一对应。
/// 直播任务禁用暂停（ADR-003 / AC-06），组内给出说明而不是隐藏开关。
struct LiveSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("录制时长与等待") {
                FormField("最长录制时长",
                          help: "到点自动结束录制并进入合并。设为 0 表示不限时长，需要手动停止。") {
                    Stepper(value: recordLimitMinutes, in: 0...720, step: 5) {
                        Text(recordLimitMinutes.wrappedValue == 0
                             ? "不限时" : "\(recordLimitMinutes.wrappedValue) 分钟")
                    }
                }
                FormField("结束后等待新分片（秒）",
                          help: "播放列表迟迟不更新时的等待上限。设为 0 表示不额外等待。") {
                    Stepper(value: liveWaitTime, in: 0...600, step: 5) {
                        Text(liveWaitTime.wrappedValue == 0
                             ? "不等待" : "\(liveWaitTime.wrappedValue) 秒")
                    }
                }
                FormField("并行拉取分片数", help: "直播同时拉取的分片数量，内核默认 16。") {
                    Stepper(value: liveTakeCount, in: 1...64) {
                        Text("\(liveTakeCount.wrappedValue) 个")
                    }
                }
            }

            Section("录制方式") {
                Toggle("按点播方式录制", isOn: $settings.defaultOptions.livePerformAsVOD)
                Text("开启后按已确定的清单一次性下载，不进行实时追帧。")
                    .font(.caption)
                    .foregroundStyle(SFColor.labelSecondary)
                Toggle("实时合并已录制分片", isOn: $settings.defaultOptions.liveRealTimeMerge)
                Toggle("边录边混流（管道方式）", isOn: $settings.defaultOptions.livePipeMux)
                Toggle("保留直播分片", isOn: $settings.defaultOptions.liveKeepSegments)
                Text("内核默认开启。关闭可在合并后释放磁盘，代价是无法回看原始分片。")
                    .font(.caption)
                    .foregroundStyle(SFColor.labelSecondary)
                Toggle("用音频时间轴修正 VTT 字幕", isOn: $settings.defaultOptions.liveFixVTTByAudio)
            }

            Section("暂停") {
                Text("直播任务不支持暂停：暂停期间播放列表仍在刷新，恢复后必然丢片段。直播任务的暂停按钮降级为「停止」。")
                    .font(.caption)
                    .foregroundStyle(SFColor.labelSecondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, SFSpace.s2)
    }

    // MARK: - 字符串 / 可选数值 ↔ 控件的换算

    private var recordLimitMinutes: Binding<Int> {
        Binding(get: { Self.minutes(from: settings.defaultOptions.liveRecordLimit) },
                set: { settings.defaultOptions.liveRecordLimit =
                       $0 <= 0 ? "" : String(format: "%02d:%02d:00", $0 / 60, $0 % 60) })
    }

    private var liveWaitTime: Binding<Int> {
        Binding(get: { settings.defaultOptions.liveWaitTime ?? 0 },
                set: { settings.defaultOptions.liveWaitTime = $0 > 0 ? $0 : nil })
    }

    private var liveTakeCount: Binding<Int> {
        Binding(get: { settings.defaultOptions.liveTakeCount ?? 16 },
                set: { settings.defaultOptions.liveTakeCount = $0 })
    }

    /// `HH:mm:ss` → 分钟。格式不符时按不限时处理。
    private static func minutes(from value: String) -> Int {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return 0 }
        return parts[0] * 60 + parts[1]
    }
}
