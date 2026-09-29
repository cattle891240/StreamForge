import SwiftUI

/// 网络设置：代理、自定义请求头、Cookie、BaseURL。
/// 字段与 `cli-argument-contract.md` §3.3 一一对应。
struct NetworkSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("代理") {
                Toggle("使用系统代理", isOn: $settings.defaultOptions.useSystemProxy)
                FormField("自定义代理",
                          help: "形如 http://127.0.0.1:8888。与系统代理互斥：一旦填写，系统代理会自动关闭。") {
                    TextField("", text: customProxyBinding, prompt: Text("http://127.0.0.1:8888"))
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                }
                Text("关闭系统代理后，内核会显式收到 `--use-system-proxy False`。")
                    .font(.caption)
                    .foregroundStyle(SFColor.labelSecondary)
            }

            Section("请求头") {
                ForEach(0..<settings.defaultOptions.headers.count, id: \.self) { index in
                    HStack(spacing: SFSpace.s2) {
                        Image(systemName: SFSymbol.headerList)
                            .imageScale(.small)
                            .foregroundStyle(SFColor.labelSecondary)
                        TextField("名称: 值", text: headerBinding(at: index))
                            .textFieldStyle(.roundedBorder)
                        Button { removeHeader(at: index) } label: {
                            Image(systemName: SFSymbol.remove)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("删除第 \(index + 1) 条请求头")
                    }
                }
                Button { settings.defaultOptions.headers.append("") } label: {
                    Label("添加请求头", systemImage: SFSymbol.newTask)
                }
                .buttonStyle(.borderless)
            }

            Section("Cookie 与来源") {
                FormField("Cookie", help: "等价于一条 `Cookie: ...` 请求头，改这里会同步请求头列表。") {
                    TextField("", text: cookieBinding, prompt: Text("token=xxx; session=yyy"))
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                }
                FormField("BaseURL",
                          help: "清单里是相对地址时，用它补全分片前缀。留空则由内核自行推导。") {
                    TextField("", text: $settings.defaultOptions.baseURL,
                              prompt: Text("https://example.com/hls/"))
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                }
                Toggle("请求时追加额外的 URL 参数", isOn: $settings.defaultOptions.appendURLParams)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, SFSpace.s2)
    }

    /// 互斥规则（契约 §5）：填写自定义代理即代表放弃系统代理。
    private var customProxyBinding: Binding<String> {
        Binding(get: { settings.defaultOptions.customProxy },
                set: { newValue in
                    settings.defaultOptions.customProxy = newValue
                    if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        settings.defaultOptions.useSystemProxy = false
                    }
                })
    }

    private var cookieBinding: Binding<String> {
        Binding(get: {
            let hit = settings.defaultOptions.headers.first { Self.isCookie($0) }
            guard let hit else { return "" }
            return String(hit.dropFirst("Cookie:".count)).trimmingCharacters(in: .whitespaces)
        }, set: { newValue in
            var kept = settings.defaultOptions.headers.filter { !Self.isCookie($0) }
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { kept.insert("Cookie: \(trimmed)", at: 0) }
            settings.defaultOptions.headers = kept
        })
    }

    private func headerBinding(at index: Int) -> Binding<String> {
        Binding(get: {
            index < settings.defaultOptions.headers.count ? settings.defaultOptions.headers[index] : ""
        }, set: { newValue in
            guard index < settings.defaultOptions.headers.count else { return }
            settings.defaultOptions.headers[index] = newValue
        })
    }

    private func removeHeader(at index: Int) {
        guard index < settings.defaultOptions.headers.count else { return }
        settings.defaultOptions.headers.remove(at: index)
    }

    private static func isCookie(_ header: String) -> Bool {
        header.lowercased().hasPrefix("cookie:")
    }
}
