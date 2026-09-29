import Foundation

/// 解析层契约（`docs/contracts/kernel-output-contract.md` + architecture.md §4.2）。
/// 全部断言建立在 `Tests/Fixtures/` 的真实内核输出上。
///
/// 依赖 `LogHints` / `ProgressParser` / `OutputParser`，尚在落地中；
/// 用 `-D SF_PARSING_FULL` 打开，未打开时本文件不注册任何用例。
func registerParserTests() {
#if SF_PARSING_FULL
    suite("Parser") {

        test("log-header-levels") {
            for (text, level) in [("DEBUG", LogLevel.debug), ("INFO", LogLevel.info),
                                  ("WARN", LogLevel.warn), ("ERROR", LogLevel.error)] {
                let record = "10:02:11.004 \(text) : message body"
                let result = LogLineParser.parse(record, taskID: nil)
                expectTrue(result.matched, "\(text) 行必须匹配")
                expectEqual(result.entry?.level, level)
                expectEqual(result.entry?.message, "message body")
                expectEqual(result.entry?.timestamp, "10:02:11.004")
            }
        }

        test("log-header-unknown-level-falls-back-to-info") {
            let result = LogLineParser.parse("10:02:11.004 TRACE : x", taskID: nil)
            expectFalse(result.matched, "非四级字面量按契约不匹配，由调用方记 WARN 跳过")
        }

        test("log-header-unmatched-never-throws") {
            expectNoThrow {
                let result = LogLineParser.parse("Vid Kbps ━━ 0/1 0.00% -0.00Bps --:--:--", taskID: nil)
                expectFalse(result.matched)
                expectNil(result.entry)
            }
        }

        test("glued-fixture-yields-14-log-entries") {
            let parser = OutputParser()
            let result = parser.ingest(try Fixtures.data("kernel_progress_glued.txt"), isStderr: false)
            expectEqual(result.logs.count, 14, "真实样本实测 14 条日志（AC-01）")
            expectTrue(result.logs.allSatisfy { $0.level == .info || $0.level == .warn }, "11 INFO + 3 WARN")
            expectEqual(result.logs.filter { $0.level == .warn }.count, 3)
        }

        test("glued-log-message-never-contains-next-timestamp") {
            let parser = OutputParser()
            let result = parser.ingest(try Fixtures.data("kernel_progress_glued.txt"), isStderr: false)
            for entry in result.logs {
                expectEqual(RecordSplitter.timestampCount(entry.message), 0,
                            "message 不得吞进下一条日志：\(entry.message)")
            }
        }

        test("glued-fixture-yields-30-progress-frames") {
            let text = try Fixtures.text("kernel_progress_glued.txt")
            let frames = ProgressParser.parse(text)
            expectEqual(frames.count, 30, "真实样本可提取 30 个进度帧，不得丢帧（AC-01）")
        }

        test("ghost-frame-name-is-the-duplicated-first-frame") {
            // 上游首帧把轨道名输出两次（`Vid KbpsVid Kbps`），该 key 之后再不更新 → 幽灵轨道。
            let text = try Fixtures.text("kernel_progress_glued.txt")
            let frames = ProgressParser.parse(text)
            let ghosts = frames.filter { $0.name == "Vid KbpsVid Kbps" }
            expectEqual(ghosts.count, 1, "重复名只出现一次，正是幽灵轨道来源（AC-19）")
            expectEqual(frames.filter { $0.name == "Vid Kbps" }.count, 29)
        }

        test("negative-speed-and-percent-are-placeholders") {
            // 实测 `-0.00Bps`、`-0.00%`、`--:--:--`、字节字段整段缺失（AC-02）。
            let frames = ProgressParser.parse("Vid Kbps ━━━ 0/1 0.00% -0.00Bps --:--:--")
            expectEqual(frames.count, 1)
            guard let frame = frames.first else { return }
            expectNil(frame.speedBytesPerSecond, "负速度必须降级为未知")
            expectTrue(frame.speedUnknown, "负速度必须标记 speedUnknown")
            expectApproximately(frame.percent, 0, "百分比不得为负")
            expectNil(frame.etaSeconds, "--:--:-- 必须解析为 nil")
            expectNil(frame.bytesDone, "字节字段缺失不得崩溃")
            expectNil(frame.bytesTotal)
            expectEqual(frame.done, 0)
            expectEqual(frame.total, 1)
        }

        test("retry-count-suffix-is-parsed") {
            let frames = ProgressParser.parse("Vid Kbps ━━━ 0/1 0.00% -0.00Bps(1) --:--:--")
            expectEqual(frames.count, 1)
            expectEqual(frames.first?.retryCount, 1, "速度后缀 (1) 表示重试计数")
            let noRetry = ProgressParser.parse("Vid Kbps ━━━ 1/1 100.00% 1.00MB/1.00MB 12.00MBps 00:00:00")
            expectEqual(noRetry.first?.retryCount, 0, "无后缀时重试计数为 0")
        }

        test("byte-units-and-eta-are-decoded") {
            let frames = ProgressParser.parse("Aud zh-CN ━━━ 120/120 100.00% 4.21MB/4.21MB 1.05MBps 00:00:07")
            expectEqual(frames.count, 1)
            guard let frame = frames.first else { return }
            expectEqual(frame.name, "Aud zh-CN")
            expectEqual(frame.done, 120)
            expectEqual(frame.total, 120)
            expectApproximately(frame.percent, 100)
            expectNotNil(frame.bytesDone)
            expectTrue((frame.bytesDone ?? 0) > 4_000_000, "MB 单位必须换算为字节")
            expectEqual(frame.etaSeconds, 7)
            expectFalse(frame.speedUnknown)
        }

        test("glued-text-does-not-leak-into-track-name") {
            // `Start downloading...Vid Kbps` 若被吞进轨道名即为回归（契约 §3 注）。
            let frames = ProgressParser.parse("Start downloading...Vid Kbps ━━━ 0/1 0.00% -0.00Bps --:--:--")
            expectEqual(frames.count, 1)
            expectEqual(frames.first?.name, "Vid Kbps")
            let etaGlued = ProgressParser.parse("--:--:--Vid Kbps ━━━ 0/1 0.00% -0.00Bps --:--:--")
            expectEqual(etaGlued.first?.name, "Vid Kbps")
        }

        test("live-frames-total-keeps-growing") {
            let text = try Fixtures.text("kernel_live.txt")
            let frames = ProgressParser.parse(text)
            expectEqual(frames.count, 2)
            expectEqual(frames.first?.total, 16)
            expectEqual(frames.last?.total, 32, "直播播放列表刷新后 total 增长")
            expectNil(frames.first?.etaSeconds, "直播 ETA 恒为 --:--:--")
        }

        test("only-progress-no-log") {
            let parser = OutputParser()
            let result = parser.ingest(Data("Vid Kbps ━━━ 0/1 0.00% -0.00Bps --:--:--".utf8), isStderr: false)
            expectEqual(result.logs.count, 0, "无时间戳 → 纯进度流")
            expectEqual(result.tracks.count, 1)
        }

        test("only-log-no-progress") {
            let parser = OutputParser()
            let result = parser.ingest(Data("16:15:07.161 INFO : hello".utf8), isStderr: false)
            expectEqual(result.logs.count, 1)
            expectEqual(result.tracks.count, 0)
        }

        test("empty-and-half-line-inputs") {
            let parser = OutputParser()
            expectEqual(parser.ingest(Data(), isStderr: false).logs.count, 0, "空输入不得崩溃")
            let half = parser.ingest(Data("16:15:0".utf8), isStderr: false)
            expectEqual(half.logs.count, 0, "半个时间戳不得产出日志")
            expectEqual(half.tracks.count, 0)
        }

        test("flush-tail-emits-residual") {
            let parser = OutputParser()
            _ = parser.ingest(Data("16:15:07.161 INFO : Start downloading...".utf8), isStderr: false)
            let tail = parser.flushTail()
            expectEqual(tail.logs.count, 1, "进程退出时残留必须冲刷（AC-01）")
            expectEqual(tail.logs.first?.message, "Start downloading...")
        }

        test("utf8-truncated-multibyte-across-chunks") {
            // 进度条 `━` 是 3 字节：跨 chunk 截断不得产生替换字符或丢帧。
            let whole = "16:15:07.161 INFO : x Vid Kbps ━━━ 0/1 0.00% -0.00Bps --:--:--"
            var bytes = Array(whole.utf8)
            let cut = bytes.firstIndex(where: { $0 == 0xE2 })! + 1   // 落在 `━` 的第 1 字节后

            let wholeParser = OutputParser()
            let expected = wholeParser.ingest(Data(whole.utf8), isStderr: false)

            let splitParser = OutputParser()
            var logs = 0
            logs += splitParser.ingest(Data(bytes[0..<cut]), isStderr: false).logs.count
            logs += splitParser.ingest(Data(bytes[cut...]), isStderr: false).logs.count
            logs += splitParser.flushTail().logs.count

            expectEqual(logs, expected.logs.count, "分块解析结果必须与整块一致")
            expectEqual(splitParser.latestTracks.count, expected.tracks.count, "进度帧不得因截断丢失")
            expectFalse(splitParser.latestTracks.isEmpty)
        }

        test("stderr-stacktrace-becomes-one-error") {
            let parser = OutputParser()
            let result = parser.ingest(try Fixtures.data("kernel_stderr_stacktrace.txt"), isStderr: true)
            expectFalse(result.logs.isEmpty, "栈无时间戳也必须被记录")
            expectTrue(result.logs.allSatisfy { $0.level == .error }, "stderr 未捕获异常 → ERROR")
            expectTrue(result.logs.allSatisfy { $0.source == .stderr })
            expectContains(result.logs.first?.message ?? "", "Unhandled exception")
        }

        test("ansi-stripped-before-parsing") {
            let raw = try Fixtures.text("kernel_ansi.txt")
            expectTrue(raw.contains("\u{1B}"), "样本本身必须含 ESC，否则用例失效")
            let parser = OutputParser()
            let result = parser.ingest(try Fixtures.data("kernel_ansi.txt"), isStderr: false)
            for entry in result.logs {
                expectFalse(entry.message.contains("\u{1B}"), "ANSI 不得进入日志正文（AC-03）")
            }
            expectEqual(result.logs.count, 6)
        }

        test("ghost-track-evicted-after-stale-window") {
            let parser = OutputParser()
            let ghost = "Ghost ━━ 0/1 0.00% -0.00Bps --:--:--"
            let real = "Vid Kbps ━━ 0/1 0.00% -0.00Bps --:--:--"
            _ = parser.ingest(Data(timedRecord(0, ghost + real).utf8), isStderr: false)
            expectTrue(parser.latestTracks.contains { $0.name == "Ghost" }, "首帧尚在窗口内")
            for tick in 1...20 {
                _ = parser.ingest(Data(timedRecord(tick, real).utf8), isStderr: false)
            }
            expectFalse(parser.latestTracks.contains { $0.name == "Ghost" },
                        "只出现一次的 key 必须在 staleWindow=10 后被剔除（AC-19）")
            expectTrue(parser.latestTracks.contains { $0.name == "Vid Kbps" }, "活跃轨道不得被误删")
        }

        test("freeze-keeps-final-visible-set") {
            let parser = OutputParser()
            let ghost = "Ghost ━━ 0/1 0.00% -0.00Bps --:--:--"
            let real = "Vid Kbps ━━ 0/1 0.00% -0.00Bps --:--:--"
            _ = parser.ingest(Data(timedRecord(0, ghost + real).utf8), isStderr: false)
            parser.freeze()
            for tick in 1...20 {
                _ = parser.ingest(Data(timedRecord(tick, real).utf8), isStderr: false)
            }
            expectTrue(parser.latestTracks.contains { $0.name == "Ghost" },
                       "冻结后不得再剔除，否则终态会丢轨道")
        }

        test("track-done-never-regresses") {
            let parser = OutputParser()
            _ = parser.ingest(Data(timedRecord(0, "Vid Kbps ━━ 5/10 50.00% 1.00MBps 00:00:10").utf8), isStderr: false)
            _ = parser.ingest(Data(timedRecord(1, "Vid Kbps ━━ 3/10 30.00% 1.00MBps 00:00:20").utf8), isStderr: false)
            expectEqual(parser.latestTracks.first?.done, 5, "分片数不得回退")
        }
    }
#endif
}

#if SF_PARSING_FULL
/// 合成一条带时间戳的 record，tick 递增保证时间戳互不相同（切分锚点生效的前提）。
private func timedRecord(_ tick: Int, _ body: String) -> String {
    String(format: "16:%02d:%02d.%03d INFO : %@", 15 + tick / 60, tick % 60, tick % 1000, body)
}
#endif
