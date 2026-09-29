import SwiftUI

/// 设置窗口容器。分组顺序固定：通用 / 下载 / 网络 / 解密 / 输出 / 直播 / 高级。
/// 依赖注入：App 需以 `.environmentObject(AppSettings)` 注入，本视图不自建实例。
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var confirmingReset = false

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                GeneralSettingsView(settings: settings)
                    .tabItem { Label("通用", systemImage: SFSymbol.settings) }
                DownloadSettingsView(settings: settings)
                    .tabItem { Label("下载", systemImage: SFSymbol.groupDownload) }
                NetworkSettingsView(settings: settings)
                    .tabItem { Label("网络", systemImage: SFSymbol.groupNetwork) }
                DecryptionSettingsView(settings: settings)
                    .tabItem { Label("解密", systemImage: SFSymbol.groupDecryption) }
                OutputSettingsView(settings: settings)
                    .tabItem { Label("输出", systemImage: SFSymbol.groupOutput) }
                LiveSettingsView(settings: settings)
                    .tabItem { Label("直播", systemImage: SFSymbol.groupLive) }
                AdvancedSettingsView(settings: settings)
                    .tabItem { Label("高级", systemImage: SFSymbol.groupAdvanced) }
            }
            Divider()
            HStack(spacing: SFSpace.s2) {
                Button(role: .destructive) { confirmingReset = true } label: {
                    Text("重置为默认值")
                }
                Spacer()
                Text("改动立即生效，只作用于之后新建的任务")
                    .font(.caption)
                    .foregroundStyle(SFColor.labelSecondary)
            }
            .padding(SFSpace.s4)
        }
        .frame(minWidth: 560, minHeight: 440)
        .alert("重置为默认值", isPresented: $confirmingReset) {
            Button("重置", role: .destructive) { resetToDefaults() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("保存目录、并发上限、高级下载参数与界面偏好都会恢复为默认值。已创建的任务不受影响。")
        }
    }

    private func resetToDefaults() {
        let fresh = AppSettings.Snapshot()
        settings.apply(fresh)
        SettingsStore().save(fresh)
    }
}
