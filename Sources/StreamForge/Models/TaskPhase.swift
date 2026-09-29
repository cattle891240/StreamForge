import Foundation

enum TaskOutcome: String, Codable, Equatable {
    case succeeded
    case failed
    case cancelled
}

/// 任务阶段。终态（`finished`）**只由进程退出码判定**，关键词仅用于中间阶段展示（ADR-004 §6）。
enum TaskPhase: Equatable {
    case queued
    case preparing
    case downloading
    case paused
    case stopped(reusable: Bool)
    case merging
    case finished(TaskOutcome)

    var isTerminal: Bool {
        if case .finished = self { return true }
        return false
    }

    /// 进程可能仍在运行（取消时必须发信号）。
    var mayHaveLiveProcess: Bool {
        switch self {
        case .downloading, .paused, .merging, .preparing: return true
        default: return false
        }
    }

    var canPause: Bool {
        switch self {
        case .downloading, .merging, .preparing: return true
        default: return false
        }
    }

    var canResume: Bool {
        switch self {
        case .paused: return true
        case .stopped(let reusable): return reusable
        default: return false
        }
    }

    var displayName: String {
        switch self {
        case .queued: return "排队中"
        case .preparing: return "准备中"
        case .downloading: return "下载中"
        case .paused: return "已暂停"
        case .stopped: return "已停止（可重试）"
        case .merging: return "合并中"
        case .finished(.succeeded): return "已完成"
        case .finished(.failed): return "失败"
        case .finished(.cancelled): return "已取消"
        }
    }

    var outcome: TaskOutcome? {
        if case .finished(let outcome) = self { return outcome }
        return nil
    }
}
