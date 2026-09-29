import Foundation
import Darwin

/// 一次 `posix_spawn` 的结果。进程组 ID 等于 PID（见 `ProcessHandle`）。
struct SpawnResult {
    let pid: pid_t
    let pgid: pid_t
    let stdoutFD: Int32
    let stderrFD: Int32
}

/// 启动失败的原因。
enum SpawnError: Error {
    case execFailed(String, errno: Int32)
    case pipeFailed(Int32)
}

/// 唯一允许创建子进程的地方。
///
/// 直接走 `posix_spawn` + `POSIX_SPAWN_SETPGROUP`，天然无 shell 注入面，
/// 因此**禁止**任何 `/bin/sh -c` 形式的调用（契约 §1.1）。
///
/// - Parameters:
///   - executable: 可执行文件绝对路径。
///   - arguments: 传给内核的实参（不含 executable 自身）。
///   - environment: 自定义环境变量；传 nil 则继承父进程环境。
func spawnGroup(
    executable: String,
    arguments: [String],
    environment: [String: String]?
) throws -> SpawnResult {
    var outPipe: [Int32] = [0, 0]
    var errPipe: [Int32] = [0, 0]
    guard pipe(&outPipe) == 0 else { throw SpawnError.pipeFailed(errno) }
    guard pipe(&errPipe) == 0 else {
        close(outPipe[0]); close(outPipe[1])
        throw SpawnError.pipeFailed(errno)
    }

    var fileActions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&fileActions)
    posix_spawn_file_actions_adddup2(&fileActions, outPipe[1], STDOUT_FILENO)
    posix_spawn_file_actions_adddup2(&fileActions, errPipe[1], STDERR_FILENO)
    posix_spawn_file_actions_addclose(&fileActions, outPipe[0])
    posix_spawn_file_actions_addclose(&fileActions, outPipe[1])
    posix_spawn_file_actions_addclose(&fileActions, errPipe[0])
    posix_spawn_file_actions_addclose(&fileActions, errPipe[1])

    var attr: posix_spawnattr_t?
    posix_spawnattr_init(&attr)
    let flags: Int32 = POSIX_SPAWN_SETPGROUP
    posix_spawnattr_setflags(&attr, Int16(flags))

    let allArgs = [executable] + arguments
    let argvPointers: [UnsafeMutablePointer<CChar>?] = allArgs.map { $0.withCString { strdup($0) } }
    var argv: [UnsafeMutablePointer<CChar>?] = argvPointers
    argv.append(nil)

    let envPointers: [UnsafeMutablePointer<CChar>?]? = environment.map { dict in
        dict.map { "\($0.key)=\($0.value)".withCString { strdup($0) } } + [nil]
    }

    var pid: pid_t = 0
    let status: Int32 = executable.withCString { pathPtr in
        posix_spawn(&pid, pathPtr, &fileActions, &attr, &argv, envPointers)
    }

    posix_spawn_file_actions_destroy(&fileActions)
    posix_spawnattr_destroy(&attr)
    argvPointers.forEach { free($0) }
    envPointers?.forEach { free($0) }

    if status != 0 {
        close(outPipe[0]); close(outPipe[1])
        close(errPipe[0]); close(errPipe[1])
        throw SpawnError.execFailed(executable, errno: status)
    }

    close(outPipe[1])
    close(errPipe[1])
    return SpawnResult(pid: pid, pgid: pid, stdoutFD: outPipe[0], stderrFD: errPipe[1])
}
