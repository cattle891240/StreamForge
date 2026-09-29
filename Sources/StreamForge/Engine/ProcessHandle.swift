import Foundation
import Darwin

/// 子进程退出状态解码。
/// 注意：`WIFEXITED` / `WEXITSTATUS` 在 Swift 中不可用，必须手工解码（ADR-004 §6）。
struct ProcessExit {
    let rawStatus: Int32

    /// 被信号终止时返回信号编号；正常退出时为 nil。
    var signal: Int32? {
        rawStatus & 0x7f != 0 ? rawStatus & 0x7f : nil
    }

    /// 正常退出时的退出码（取低 8 位）；被信号终止时为 nil。
    var code: Int? {
        rawStatus & 0x7f == 0 ? Int((rawStatus >> 8) & 0xff) : nil
    }

    init(rawStatus: Int32) {
        self.rawStatus = rawStatus
    }
}

/// 对子进程（及其进程组）的控制句柄。
/// 通过 `posix_spawn` 的 `POSIX_SPAWN_SETPGROUP` 标志，子进程成为新进程组的组长，
/// 组 ID 等于其 PID，因此可直接用 PID 作为 `killpg` 的目标。
final class ProcessHandle {
    let pid: pid_t
    private let pgid: pid_t

    init(pid: pid_t) {
        self.pid = pid
        self.pgid = pid
    }

    /// P1：挂起整个进程组（SIGSTOP），使下载线程与内核子进程一起冻结。
    func suspend() {
        _ = killpg(pgid, SIGSTOP)
    }

    /// 恢复整个进程组（SIGCONT）。
    func resume() {
        _ = killpg(pgid, SIGCONT)
    }

    /// 终止：先恢复（SIGCONT）再发 SIGTERM，保证处于暂停中的进程也能收到信号（AC-07）。
    func terminate() {
        resume()
        _ = killpg(pgid, SIGTERM)
    }

    /// 强制杀死：SIGKILL，不可被捕获。
    func forceKill() {
        _ = killpg(pgid, SIGKILL)
    }

    /// 进程是否仍然存在。
    func isAlive() -> Bool {
        kill(pid, 0) == 0
    }

    /// 阻塞等待进程退出，返回解码后的状态。
    func wait() -> ProcessExit {
        var status: Int32 = 0
        _ = waitpid(pid, &status, 0)
        return ProcessExit(rawStatus: status)
    }
}
