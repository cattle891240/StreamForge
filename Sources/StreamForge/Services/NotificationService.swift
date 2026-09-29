import Foundation
import UserNotifications

/// 系统通知。首次投递前请求授权；多条队列完成合并为一条，禁止 N 条通知刷屏（design.md §9.3）。
final class NotificationService {

    enum Category {
        case success
        case failure

        var identifier: String {
            switch self {
            case .success: return "STREAMFORGE.SUCCESS"
            case .failure: return "STREAMFORGE.FAILURE"
            }
        }
    }

    private let center: UNUserNotificationCenter
    private var authorized = false
    private var pendingCompletions: [CompletedTaskNotice] = []
    private let mergeWindow: TimeInterval = 3
    private var flushWorkItem: DispatchWorkItem?

    struct CompletedTaskNotice {
        let name: String
        let detail: String
    }

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorizationIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            self?.authorized = granted
        }
    }

    /// 成功通知合并：合并窗口内的多条合并为「{N} 个任务已完成」。
    func notifySuccess(name: String, detail: String) {
        pendingCompletions.append(CompletedTaskNotice(name: name, detail: detail))
        flushWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushCompletions() }
        flushWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + mergeWindow, execute: work)
    }

    func notifyFailure(name: String, detail: String) {
        post(category: .failure, title: "下载失败", subtitle: name, body: detail)
    }

    private func flushCompletions() {
        let batch = pendingCompletions
        pendingCompletions.removeAll()
        guard !batch.isEmpty else { return }
        if batch.count == 1, let only = batch.first {
            post(category: .success, title: "下载完成", subtitle: only.name, body: only.detail)
        } else {
            let names = batch.prefix(3).map { $0.name }.joined(separator: "、")
            let tail = batch.count > 3 ? " 等" : ""
            post(category: .success, title: "\(batch.count) 个任务已完成",
                 subtitle: names + tail, body: "")
        }
    }

    private func post(category: Category, title: String, subtitle: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.categoryIdentifier = category.identifier
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            guard let error = error else { return }
            NSLog("[StreamForge] 通知投递失败：%@", error.localizedDescription)
        }
    }
}
