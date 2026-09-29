import Foundation

/// `RecordSplitter` 契约：时间戳 lookahead 切分。
/// 真实样本 `kernel_progress_glued.txt` 4623 字节仅 8 个 `\n`、0 个 `\r`——
/// 按行解析必然丢帧，本文件全部断言都建立在真实样本上（AC-01）。
func registerSplitterTests() {
    suite("Splitter") {

        test("empty-input") {
            expectEqual(RecordSplitter.split("").count, 0, "空输入不得产出 record")
            expectEqual(RecordSplitter.timestampCount(""), 0)
        }

        test("no-timestamp-pure-progress") {
            let text = "Vid Kbps ━━━━━━ 0/1 0.00% -0.00Bps --:--:--"
            expectEqual(RecordSplitter.split(text).count, 0, "纯进度帧无时间戳 → 无日志 record")
            expectEqual(RecordSplitter.timestampCount(text), 0)
        }

        test("single-record") {
            let text = "16:15:07.161 INFO : hello"
            let records = RecordSplitter.split(text)
            expectEqual(records.count, 1)
            expectEqual(records.first, text)
        }

        test("leading-residue-dropped") {
            // 进程刚启动时的半个进度帧：第一个时间戳之前的残留必须丢弃。
            let text = "Vid Kbps ━━━ 0/1 0.00% -0.00Bps --:--:--16:15:07.161 INFO : Start downloading..."
            let records = RecordSplitter.split(text)
            expectEqual(records.count, 1)
            expectEqual(records.first, "16:15:07.161 INFO : Start downloading...")
            expectFalse(records.first?.contains("Vid Kbps") ?? true, "残留不得混入 record")
        }

        test("glued-record-count-equals-timestamp-count") {
            let text = try Fixtures.text("kernel_progress_glued.txt")
            let records = RecordSplitter.split(text)
            expectEqual(RecordSplitter.timestampCount(text), 14, "真实样本实测 14 条日志")
            expectEqual(records.count, 14, "日志条数必须等于时间戳个数，不得丢帧")
        }

        test("glued-split-is-lossless") {
            // 零宽断言切分不吞掉任何字符：拼接后必须与原文完全一致。
            let text = try Fixtures.text("kernel_progress_glued.txt")
            let records = RecordSplitter.split(text)
            expectEqual(records.joined(), text, "切分必须无损")
            expectEqual(records.joined().count, text.count)
        }

        test("glued-every-record-has-exactly-one-timestamp") {
            let text = try Fixtures.text("kernel_progress_glued.txt")
            for record in RecordSplitter.split(text) {
                expectEqual(RecordSplitter.timestampCount(record), 1, "单条 record 不得含下一个时间戳")
                expectTrue(hasTimestampPrefix(record), "record 必须以时间戳开头：\(preview([record]))")
            }
        }

        test("glued-record-carries-glued-progress-block") {
            // 日志 message 之后紧跟粘连的进度块，不得被切走。
            let text = try Fixtures.text("kernel_progress_glued.txt")
            let records = RecordSplitter.split(text)
            let start = records.first { $0.contains("Start downloading...") }
            expectNotNil(start, "样本中必须存在 Start downloading 这条日志")
            expectContains(start ?? "", "Vid Kbps", "进度块必须留在同一 record 内")
            expectContains(start ?? "", "━", "进度条字符不得丢失")
        }

        test("glued-newlines-are-fewer-than-records") {
            // 反向加固：换行符远少于 record 数，证明按行解析必然失败。
            let text = try Fixtures.text("kernel_progress_glued.txt")
            let newlines = text.filter { $0 == "\n" }.count
            expectEqual(newlines, 8, "实测样本只有 8 个换行")
            expectEqual(text.filter { $0 == "\r" }.count, 0, "实测样本 0 个回车")
            expectTrue(RecordSplitter.split(text).count > newlines, "record 数必须多于行数")
        }

        test("mutation-consuming-split-loses-anchors") {
            // 变异加固：把 lookahead `(?=...)` 换成消费式匹配后，锚点本身被吞掉，
            // 必须出现"record 不再以时间戳开头"与"内容变短"两处差异，否则本用例失效。
            let text = try Fixtures.text("kernel_progress_glued.txt")
            let good = RecordSplitter.split(text)
            let mutant = splitByConsumingSeparator(text)
            expectTrue(good.allSatisfy { hasTimestampPrefix($0) }, "正例：每条 record 都以时间戳开头")
            expectFalse(mutant.allSatisfy { hasTimestampPrefix($0) }, "反例：消费式切分必须吞掉时间戳")
            expectTrue(mutant.joined().count < text.count, "反例：消费式切分必须丢字符")
            expectTrue(mutant.count == good.count, "反例仍能切出同样条数——差异只在内容，故必须靠内容断言")
        }

        test("ansi-fixture-records") {
            let raw = try Fixtures.text("kernel_ansi.txt")
            let cleaned = OutputNormalizer().stripANSI(raw)
            expectFalse(cleaned.contains("\u{1B}"), "ANSI 必须在切分前剥离（AC-03）")
            expectEqual(cleaned.contains("[?25"), false)
            expectEqual(RecordSplitter.split(cleaned).count, 6)
            expectEqual(RecordSplitter.timestampCount(cleaned), 6)
        }

        test("ansi-escape-spanning-chunks") {
            // 半个 CSI 序列跨 chunk：不得残留转义片段，也不得吞掉正文。
            let first = "\u{1B}[?25l16:15:07.161 INFO : a"
            let second = "\u{1B}[?12l16:15:07.193 INFO : b"
            let normalizer = OutputNormalizer()
            let cleaned = normalizer.stripANSI(first) + normalizer.stripANSI(second)
            expectFalse(cleaned.contains("\u{1B}"), "跨 chunk 的半个转义序列也必须剥离干净")
            expectEqual(RecordSplitter.timestampCount(cleaned), 2)
        }

        test("log-levels-fixture-records") {
            let text = try Fixtures.text("kernel_log_levels.txt")
            let records = RecordSplitter.split(text)
            expectEqual(records.count, 14)
            expectTrue(records.contains { $0.contains("DEBUG :") }, "必须切出 DEBUG 行")
            expectTrue(records.contains { $0.contains("ERROR :") }, "必须切出 ERROR 行")
            expectTrue(records.contains { $0.hasSuffix("Save Name: 示例视频") },
                       "中文消息不得被切坏：\(preview(records))")
        }

        test("live-fixture-records") {
            let text = try Fixtures.text("kernel_live.txt")
            expectEqual(RecordSplitter.split(text).count, 10)
            expectEqual(RecordSplitter.timestampCount(text), 10)
        }

        test("stderr-stacktrace-has-no-records") {
            // .NET 栈没有时间戳：split 返回空，调用方必须整体降级为一条 ERROR。
            let text = try Fixtures.text("kernel_stderr_stacktrace.txt")
            expectEqual(RecordSplitter.split(text).count, 0)
            expectEqual(RecordSplitter.timestampCount(text), 0)
            expectContains(text, "Unhandled exception")
        }

        test("timestamp-count-ignores-clock-like-text") {
            // 只有时间戳没有级别（如 ETA 00:00:00）不得被当成日志锚点。
            let text = "Vid Kbps ━━ 1/1 100.00% 1.00MB/1.00MB 12.00MBps 00:00:00"
            expectEqual(RecordSplitter.timestampCount(text), 0)
            expectEqual(RecordSplitter.split(text).count, 0)
        }

        test("record-boundary-at-utf16-multibyte") {
            // 中文 + 进度条 `━`（3 字节）混排：record 边界不得落在多字节字符中间。
            let text = "10:02:11.601 INFO : Save Name: 示例视频1━10:02:11.612 INFO : Start downloading..."
            let records = RecordSplitter.split(text)
            expectEqual(records.count, 2)
            expectEqual(records[0], "10:02:11.601 INFO : Save Name: 示例视频1━")
            expectEqual(records[1], "10:02:11.612 INFO : Start downloading...")
        }
    }
}

private func hasTimestampPrefix(_ text: String) -> Bool {
    guard let regex = ParserPatterns.makeRegex(#"^\d{2}:\d{2}:\d{2}\.\d{3}\s+(?:INFO|WARN|DEBUG|ERROR)\s*:"#) else {
        return false
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.firstMatch(in: text, options: [], range: range) != nil
}

/// 反例切分：消费式分隔符会把锚点本身吃掉（ADR-006「变异加固」）。
private func splitByConsumingSeparator(_ text: String) -> [String] {
    guard let regex = ParserPatterns.makeRegex(ParserPatterns.recordSplitConsuming) else { return [] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let marked = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "\u{1}")
    return marked.split(separator: "\u{1}", omittingEmptySubsequences: true).map(String.init)
}
