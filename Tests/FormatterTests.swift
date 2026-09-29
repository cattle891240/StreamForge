import Foundation

/// `Util` 层的纯函数：字节 / 速度 / 时长格式化与命令预览转义。
/// 缺失值、负值、非有限值一律渲染占位符（AC-02）。
func registerFormatterTests() {
    suite("Formatter") {

        test("bytes-placeholder-for-missing-and-negative") {
            expectEqual(ByteFormatter.bytes(nil), "--")
            expectEqual(ByteFormatter.bytes(-1), "--", "负值不得渲染负号")
            expectEqual(ByteFormatter.bytes(Int64.min), "--")
        }

        test("bytes-units") {
            expectEqual(ByteFormatter.bytes(0), "0 B")
            expectEqual(ByteFormatter.bytes(512), "512 B")
            expectEqual(ByteFormatter.bytes(1023), "1023 B", "不足 1KB 仍按 B 显示")
            expectEqual(ByteFormatter.bytes(1024), "1.00 KB")
            expectEqual(ByteFormatter.bytes(1536), "1.50 KB")
            expectEqual(ByteFormatter.bytes(1024 * 1024), "1.00 MB")
            expectEqual(ByteFormatter.bytes(1024 * 1024 * 1024), "1.00 GB")
            expectEqual(ByteFormatter.bytes(Int64(1024) * 1024 * 1024 * 1024), "1.00 TB")
        }

        test("speed-placeholder-for-unknown-negative-nan") {
            expectEqual(ByteFormatter.speed(nil), "--")
            expectEqual(ByteFormatter.speed(-0.001), "--", "内核会输出 -0.00Bps（AC-02）")
            expectEqual(ByteFormatter.speed(Double.nan), "--", "NaN 不得泄漏到界面")
            expectEqual(ByteFormatter.speed(Double.infinity), "--")
        }

        test("speed-unit-suffix") {
            expectEqual(ByteFormatter.speed(0), "0 B/s")
            expectEqual(ByteFormatter.speed(1024), "1.00 KB/s")
            expectEqual(ByteFormatter.speed(1_048_576), "1.00 MB/s")
        }

        test("kernel-byte-unit-multipliers") {
            expectEqual(ByteFormatter.multiplier(for: "B"), 1)
            expectEqual(ByteFormatter.multiplier(for: "KB"), 1024)
            expectEqual(ByteFormatter.multiplier(for: "MB"), 1024 * 1024)
            expectEqual(ByteFormatter.multiplier(for: "GB"), 1024 * 1024 * 1024)
            expectEqual(ByteFormatter.multiplier(for: "TB"), 1024 * 1024 * 1024 * 1024)
            expectEqual(ByteFormatter.multiplier(for: "kb"), 1024, "大小写不敏感")
            expectNil(ByteFormatter.multiplier(for: "Mbps"), "位/秒单位不得误判为字节单位")
            expectNil(ByteFormatter.multiplier(for: ""))
        }

        test("eta-placeholder-and-clock") {
            expectEqual(DurationFormatter.eta(nil), "--")
            expectEqual(DurationFormatter.eta(-1), "--")
            expectEqual(DurationFormatter.eta(0), "00:00:00")
            expectEqual(DurationFormatter.eta(7), "00:00:07")
            expectEqual(DurationFormatter.eta(59), "00:00:59")
            expectEqual(DurationFormatter.eta(60), "00:01:00")
            expectEqual(DurationFormatter.eta(3661), "01:01:01")
            expectEqual(DurationFormatter.clock(0), "00:00:00")
        }

        test("compact-duration") {
            expectEqual(DurationFormatter.compact(7), "0:07")
            expectEqual(DurationFormatter.compact(65), "1:05")
            expectEqual(DurationFormatter.compact(3599), "59:59")
            expectEqual(DurationFormatter.compact(3600), "01:00:00", "超过 1 小时退回等宽时钟")
            expectEqual(DurationFormatter.compact(-5), "0:00")
        }

        test("parse-clock") {
            expectEqual(DurationFormatter.parseClock("00:00:07"), 7)
            expectEqual(DurationFormatter.parseClock("01:02:03"), 3723)
            expectEqual(DurationFormatter.parseClock("100:00:00"), 360_000)
            expectNil(DurationFormatter.parseClock("--:--:--"), "内核未就绪的 ETA 必须解析为 nil")
            expectNil(DurationFormatter.parseClock("1:2"))
            expectNil(DurationFormatter.parseClock("ab:cd:ef"))
            expectNil(DurationFormatter.parseClock("-1:00:00"))
        }

        test("eta-round-trip") {
            for seconds in [0, 1, 59, 60, 3661, 86_399] {
                let text = DurationFormatter.eta(seconds)
                expectEqual(DurationFormatter.parseClock(text), seconds, "\(text) 必须可回解")
            }
            expectNil(DurationFormatter.parseClock(DurationFormatter.eta(nil)), "占位符不得被解析为 0")
        }

        test("shell-escaping-quote") {
            expectEqual(ShellEscaping.quote(""), "''")
            expectEqual(ShellEscaping.quote("abcXYZ019-_./=:,"), "abcXYZ019-_./=:,", "安全字符不转义")
            expectEqual(ShellEscaping.quote("a b"), "'a b'")
            expectEqual(ShellEscaping.quote("it's"), "'it'\\''s'")
            expectEqual(ShellEscaping.quote("/opt/my tools/bin"), "'/opt/my tools/bin'")
        }

        test("shell-escaping-join") {
            expectEqual(ShellEscaping.join(["/usr/local/bin/N_m3u8DL-RE", "https://a.example/m.m3u8"]),
                        "/usr/local/bin/N_m3u8DL-RE https://a.example/m.m3u8")
            expectEqual(ShellEscaping.join(["-H", "Referer: https://a.example"]),
                        "-H 'Referer: https://a.example'")
        }
    }
}
