import SwiftUI

/// 侧栏状态过滤。八个状态全部可单独过滤（SPEC §8），计数用系统 `.badge()` 原生渲染。
enum TaskFilter: String, CaseIterable, Identifiable {
    case all
    case preparing
    case downloading
    case paused
    case stopped
    case merging
    case succeeded
    case failed
    case canceled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .preparing: return "准备中"
        case .downloading: return "下载中"
        case .paused: return "已暂停"
        case .stopped: return "已停止"
        case .merging: return "合并中"
        case .succeeded: return "已完成"
        case .failed: return "失败"
        case .canceled: return "已取消"
        }
    }

    var symbol: String {
        switch self {
        case .all: return SFSymbol.headerList
        case .preparing: return SFSymbol.statusPreparing
        case .downloading: return SFSymbol.statusDownloading
        case .paused: return SFSymbol.statusPaused
        case .stopped: return SFSymbol.statusStopped
        case .merging: return SFSymbol.statusMerging
        case .succeeded: return SFSymbol.statusDone
        case .failed: return SFSymbol.statusFailed
        case .canceled: return SFSymbol.statusCanceled
        }
    }

    /// 状态色只出现在图标上，文字一律 label（The State-Is-Color Rule）。
    var color: Color {
        switch self {
        case .all: return SFColor.labelSecondary
        case .preparing, .paused, .canceled: return SFColor.neutral
        case .downloading: return SFColor.accent
        case .stopped, .merging: return SFColor.warning
        case .succeeded: return SFColor.success
        case .failed: return SFColor.danger
        }
    }

    func matches(_ task: DownloadTask) -> Bool {
        switch self {
        case .all: return true
        case .preparing: return task.phase == .queued || task.phase == .preparing
        case .downloading: return task.phase == .downloading
        case .paused: return task.phase == .paused
        case .stopped:
            if case .stopped = task.phase { return true }
            return false
        case .merging: return task.phase == .merging
        case .succeeded: return task.phase == .finished(.succeeded)
        case .failed: return task.phase == .finished(.failed)
        case .canceled: return task.phase == .finished(.cancelled)
        }
    }

    static func counts(from tasks: [DownloadTask]) -> [TaskFilter: Int] {
        var result: [TaskFilter: Int] = [.all: tasks.count]
        for filter in TaskFilter.allCases where filter != .all {
            result[filter, default: 0] = tasks.filter { filter.matches($0) }.count
        }
        return result
    }
}

/// 侧栏：单级列表，无嵌套、无分组标题（design.md 附录 A.1）。
struct SidebarView: View {
    @Binding var filter: TaskFilter
    let counts: [TaskFilter: Int]

    var body: some View {
        List(selection: $filter) {
            ForEach(TaskFilter.allCases) { item in
                Label {
                    Text(item.title)
                } icon: {
                    Image(systemName: item.symbol)
                        .imageScale(.medium)
                        .foregroundStyle(item.color)
                }
                .badge(counts[item, default: 0])
                .tag(item)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
        .accessibilityLabel("任务状态过滤")
    }
}
