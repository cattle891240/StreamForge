import SwiftUI

/// 解密设置：Key 列表、解密引擎与二进制路径、自定义 HLS 参数。
/// 字段与 `cli-argument-contract.md` §3.5 一一对应。
struct DecryptionSettingsView: View {
    @ObservedObject var settings: AppSettings

    private static let hlsMethods = [
        "AES_128", "AES_128_ECB", "CENC", "CHACHA20",
        "NONE", "SAMPLE_AES", "SAMPLE_AES_CTR", "UNKNOWN"
    ]

    var body: some View {
        Form {
            Section("解密 Key") {
                ForEach(0..<settings.defaultOptions.keys.count, id: \.self) { index in
                    HStack(spacing: SFSpace.s2) {
                        Image(systemName: SFSymbol.groupDecryption)
                            .imageScale(.small)
                            .foregroundStyle(SFColor.labelSecondary)
                        TextField("KID:KEY 或 KEY", text: keyBinding(at: index))
                            .font(.system(.caption, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                        Button { removeKey(at: index) } label: {
                            Image(systemName: SFSymbol.remove)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("删除第 \(index + 1) 条 Key")
                    }
                }
                Button { settings.defaultOptions.keys.append("") } label: {
                    Label("添加 Key", systemImage: SFSymbol.newTask)
                }
                .buttonStyle(.borderless)
                Text("十六进制格式。不写 KID 时该 Key 应用于全部轨道。")
                    .font(.caption)
                    .foregroundStyle(SFColor.labelSecondary)

                FormField("Key 文本文件", help: "每行一条 Key 的文件路径，适合 Key 较多的场景。") {
                    HStack(spacing: SFSpace.s2) {
                        TextField("", text: $settings.defaultOptions.keyTextFile,
                                  prompt: Text("/Users/me/keys.txt"))
                            .textFieldStyle(.roundedBorder)
                        Button { pickKeyFile() } label: {
                            Label("选择…", systemImage: SFSymbol.folder)
                        }
                    }
                }
            }

            Section("解密引擎") {
                FormField("引擎", help: "ffmpeg 引擎会在二进制路径为空时回退到依赖检测到的 ffmpeg。") {
                    Picker("", selection: $settings.defaultOptions.decryptionEngine) {
                        Text("MP4DECRYPT").tag(DownloadOptions.DecryptionEngine.mp4decrypt)
                        Text("FFMPEG").tag(DownloadOptions.DecryptionEngine.ffmpeg)
                        Text("SHAKA_PACKAGER").tag(DownloadOptions.DecryptionEngine.shakaPackager)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 200, alignment: .leading)
                }
                FormField("引擎二进制路径", help: "留空则由依赖检测自动寻找。") {
                    HStack(spacing: SFSpace.s2) {
                        TextField("", text: $settings.defaultOptions.decryptionBinaryPath,
                                  prompt: Text("/opt/homebrew/bin/mp4decrypt"))
                            .textFieldStyle(.roundedBorder)
                        Button { pickBinary() } label: {
                            Label("选择…", systemImage: SFSymbol.folder)
                        }
                    }
                }
                Toggle("MP4 实时解密", isOn: $settings.defaultOptions.mp4RealTimeDecryption)
            }

            Section("自定义 HLS 加密") {
                FormField("加密方式", help: "留空由内核从清单里自动识别。") {
                    Picker("", selection: $settings.defaultOptions.customHLSMethod) {
                        Text("自动识别").tag("")
                        ForEach(Self.hlsMethods, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 200, alignment: .leading)
                }
                FormField("Key（文件或十六进制或 Base64）") {
                    TextField("", text: $settings.defaultOptions.customHLSKey)
                        .font(.system(.caption, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }
                FormField("IV（文件或十六进制或 Base64）") {
                    TextField("", text: $settings.defaultOptions.customHLSIV)
                        .font(.system(.caption, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, SFSpace.s2)
    }

    private func keyBinding(at index: Int) -> Binding<String> {
        Binding(get: {
            index < settings.defaultOptions.keys.count ? settings.defaultOptions.keys[index] : ""
        }, set: { newValue in
            guard index < settings.defaultOptions.keys.count else { return }
            settings.defaultOptions.keys[index] = newValue
        })
    }

    private func removeKey(at index: Int) {
        guard index < settings.defaultOptions.keys.count else { return }
        settings.defaultOptions.keys.remove(at: index)
    }

    private func pickKeyFile() {
        if let picked = PanelPicker.chooseFile(current: settings.defaultOptions.keyTextFile) {
            settings.defaultOptions.keyTextFile = picked
        }
    }

    private func pickBinary() {
        if let picked = PanelPicker.chooseFile(current: settings.defaultOptions.decryptionBinaryPath) {
            settings.defaultOptions.decryptionBinaryPath = picked
        }
    }
}
