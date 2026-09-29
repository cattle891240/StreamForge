import SwiftUI

/// 应用入口。只做装配：环境对象、主窗口 Scene、菜单栏命令、设置窗口（architecture.md §3）。
@main
struct StreamForgeApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// 引用类型，作为 `let` 在 init 中创建一次，生命周期与应用等长。
    /// 使用 `let` 而非 `@StateObject`，以便在 init 的逃逸闭包中捕获实例本身而非 `self`。
    private let env = AppEnvironment()

    @MainActor
    init() {
        // 委托早于任何 AppKit 回调装配，启动与退出路径都不会漏。
        // 捕获局部强引用 `environment`，避免逃逸闭包捕获值类型的 `self`。
        let environment = env
        appDelegate.onDidLaunch = { Task { @MainActor in environment.bootstrap() } }
        appDelegate.onWillTerminate = { Task { @MainActor in environment.prepareForTermination() } }
        appDelegate.onOpenFiles = { urls in
            Task { @MainActor in
                for source in DropReceiver.sources(fromFileURLs: urls) {
                    environment.createTask(input: source,
                                           options: environment.settings.defaultOptions,
                                           saveDir: nil,
                                           saveName: nil)
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(env)
                .environmentObject(env.settings)
                .frame(minWidth: SFSize.windowMinWidth, minHeight: SFSize.windowMinHeight)
                .preferredColorScheme(appearanceOverride)
        }
        .commands { AppCommands(env: env) }
        Settings {
            SettingsView()
                .environmentObject(env.settings)
        }
    }

    /// 外观覆盖：跟随系统时返回 nil，交给系统决定（design.md §8.2 零 colorScheme 分支）。
    private var appearanceOverride: ColorScheme? {
        switch env.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
