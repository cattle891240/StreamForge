import Foundation

/// 暂停策略（ADR-003，AC-04/05/06/07）与进程退出码解码（architecture.md §4.1）。
/// 用 `ProcessControlling` 协议替身，不真起进程。依赖 Engine / Services，
/// 用 `-D SF_ENGINE_READY` 打开。
func registerPauseControllerTests() {
#if SF_ENGINE_READY
    suite("Pause") {

        test("live-task-cannot-pause") {
            let (controller, control, queue) = makeController(timeout: 100, isLive: true)
            expectFalse(controller.canPause, "直播任务必须禁用暂停（AC-06）")
            controller.beginPause()
            drain(queue)
            expectEqual(control.calls, [], "被禁用时不得发出任何信号")
        }

        test("guard-seconds-follow-timeout-and-hard-limit") {
            expectEqual(makeController(timeout: 100, isLive: false).0.guardSeconds, 80,
                        "默认超时 100s × 0.8 = 80s")
            expectEqual(makeController(timeout: 50, isLive: false).0.guardSeconds, 40)
            expectEqual(makeController(timeout: 500, isLive: false).0.guardSeconds, 80,
                        "不得超过 80s 硬上限（AC-05）")
            expectEqual(PauseController.hardLimitSeconds, 80)
        }

        test("begin-pause-suspends-process-group") {
            let (controller, control, queue) = makeController(timeout: 100, isLive: false)
            controller.beginPause()
            drain(queue)
            expectEqual(control.calls, ["suspend"], "P1 必须是 SIGSTOP 挂起进程组（AC-04）")
        }

        test("end-pause-resumes-and-accumulates") {
            let (controller, control, queue) = makeController(timeout: 100, isLive: false)
            controller.beginPause()
            drain(queue)
            controller.endPause()
            drain(queue)
            expectEqual(control.calls, ["suspend", "resume"])
            expectTrue(controller.accumulatedPauseSeconds > 0, "暂停时长必须累加，供 UI 扣除已用时")
        }

        test("stop-preserving-sends-cont-before-term") {
            // AC-07：先 SIGCONT 再 SIGTERM，否则停止中的进程收不到终止信号。
            let (controller, control, queue) = makeController(timeout: 100, isLive: false)
            controller.beginPause()
            drain(queue)
            controller.stopPreservingProgress()
            drain(queue)
            expectEqual(control.calls, ["suspend", "resume", "terminate"])
        }

        test("auto-convert-to-stopped-after-guard") {
            // 守卫时长 0.8s（httpRequestTimeout = 1），超时后必须回调转 P2。
            let (controller, control, _) = makeController(timeout: 1, isLive: false)
            var converted = false
            controller.onAutoConvert = { converted = true }
            controller.beginPause()
            let deadline = Date().addingTimeInterval(5)
            while !converted && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            expectTrue(converted, "超过守卫时长必须自动降级为「已停止（可重试）」（AC-05）")
            expectTrue(control.calls.contains("resume"), "降级前必须先恢复进程组")
        }

        test("end-pause-cancels-guard-timer") {
            let (controller, _, _) = makeController(timeout: 1, isLive: false)
            var converted = false
            controller.onAutoConvert = { converted = true }
            controller.beginPause()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            controller.endPause()
            let deadline = Date().addingTimeInterval(1.5)
            while Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            expectFalse(converted, "正常恢复后守卫定时器必须撤销，不得误降级")
        }
    }

    suite("ExitStatus") {

        test("normal-exit-zero") {
            let status = ProcessExit(rawStatus: 0 << 8)
            expectNil(status.signal)
            expectEqual(status.code, 0)
        }

        test("normal-exit-nonzero") {
            expectEqual(ProcessExit(rawStatus: 1 << 8).code, 1)
            expectEqual(ProcessExit(rawStatus: 42 << 8).code, 42)
            expectEqual(ProcessExit(rawStatus: 255 << 8).code, 255, "退出码取低 8 位")
            expectNil(ProcessExit(rawStatus: 1 << 8).signal)
        }

        test("terminated-by-signal") {
            // WIFEXITED / WEXITSTATUS 在 Swift 不可用，必须手工解码。
            expectEqual(ProcessExit(rawStatus: 15).signal, 15, "SIGTERM")
            expectNil(ProcessExit(rawStatus: 15).code, "被信号终止时不得产出退出码")
            expectEqual(ProcessExit(rawStatus: 9).signal, 9, "SIGKILL")
            expectNil(ProcessExit(rawStatus: 9).code)
        }

        test("stopped-status-is-not-a-clean-exit") {
            // 契约只定义了 `& 0x7f != 0 → 信号`；WIFSTOPPED（0x7f）会落进该分支。
            // 显式固定这一行为，避免将来有人顺手把它当成退出码 0。
            let stopped = ProcessExit(rawStatus: (17 << 8) | 0x7f)
            expectEqual(stopped.signal, 0x7f)
            expectNil(stopped.code)
        }

        test("decoding-matches-waitpid-semantics") {
            for code in [0, 1, 7, 128, 255] {
                let status = ProcessExit(rawStatus: Int32(code << 8))
                expectEqual(status.code, code)
                expectNil(status.signal)
            }
            for signal in [Int32(1), 2, 9, 15] {
                let status = ProcessExit(rawStatus: signal)
                expectEqual(status.signal, signal)
                expectNil(status.code)
            }
        }
    }
#endif
}

#if SF_ENGINE_READY
private final class RecordingProcessControl: ProcessControlling {
    private(set) var calls: [String] = []
    func suspend() { calls.append("suspend") }
    func resume() { calls.append("resume") }
    func terminate() { calls.append("terminate") }
    func forceKill() { calls.append("forceKill") }
}

private func makeController(timeout: Int, isLive: Bool)
    -> (PauseController, RecordingProcessControl, DispatchQueue) {
    let control = RecordingProcessControl()
    let queue = DispatchQueue(label: "com.streamforge.test.pause")
    let controller = PauseController(control: control,
                                     httpRequestTimeout: timeout,
                                     isLive: isLive,
                                     queue: queue)
    return (controller, control, queue)
}

/// 排空控制器所在的串行队列，使断言可确定地观察到信号序列。
private func drain(_ queue: DispatchQueue) {
    queue.sync {}
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
}
#endif
