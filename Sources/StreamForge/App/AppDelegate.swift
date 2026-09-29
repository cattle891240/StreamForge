import AppKit
import SwiftUI

/// NSApplicationDelegate：启动装配、退出清理、Dock 行为（重新打开窗口、Dock 拖入文件）。
/// 只做 AppKit 侧的桥接，业务动作全部通过注入的闭包交给 `AppEnvironment`。
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// 由 `StreamForgeApp` 装配时注入。
    var onDidLaunch: (() -> Void)?
    var onWillTerminate: (() -> Void)?
    var onOpenFiles: (([URL]) -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        onDidLaunch?()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        onWillTerminate?()
        // 进程收尾是同步的（SIGTERM 已发出），给内核 1 秒缓冲后再退出主循环。
        return .terminateNow
    }

    /// 点击 Dock 图标：窗口被关闭后重新拉起主窗口，而不是"点了没反应"。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        if let window = NSApp.windows.first(where: { $0.canBecomeKey }) {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// Dock 图标拖入文件（design.md 附录 A.5）：与主窗口拖拽走同一个入口。
    func application(_ application: NSApplication, open urls: [URL]) {
        onOpenFiles?(urls)
    }
}
