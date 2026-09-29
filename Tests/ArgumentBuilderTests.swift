import Foundation

/// 参数构建契约（`docs/contracts/cli-argument-contract.md` + architecture.md §4.1）。
/// 依赖 Engine 的 `ArgumentBuilder` / `ArgumentRules`，用 `-D SF_ENGINE_READY` 打开。
func registerArgumentBuilderTests() {
#if SF_ENGINE_READY
    suite("ArgumentBuilder") {

        test("required-arguments-always-present") {
            let argv = try build(argumentsFor: DownloadOptions())
            expectTrue(argv.contains("--no-ansi-color"))
            expectTrue(argv.contains("--disable-update-check"))
            expectTrue(argv.contains("--tmp-dir"))
            expectTrue(argv.contains("--save-dir"))
            expectTrue(argv.contains("--save-name"))
        }

        test("input-value-precedes-all-options") {
            let argv = try build(argumentsFor: DownloadOptions())
            let inputIndex = argv.firstIndex(of: "https://example.com/master.m3u8")
            expectNotNil(inputIndex, "输入源必须在 argv 中")
            guard let inputIndex else { return }
            expectTrue(argv[0..<inputIndex].allSatisfy { !$0.hasPrefix("--") },
                       "输入源之前不得出现任何选项：\(preview(Array(argv[0...inputIndex])))")
        }

        test("empty-string-options-are-omitted") {
            var options = DownloadOptions()
            options.baseURL = ""
            options.savePattern = ""
            options.maxSpeed = ""
            let argv = try build(argumentsFor: options)
            expectFalse(argv.contains("--base-url"), "空值不得输出（契约 §1.4）")
            expectFalse(argv.contains("--save-pattern"))
            expectFalse(argv.contains("--max-speed"))
        }

        test("upstream-default-false-switches-are-omitted") {
            var options = DownloadOptions()
            options.binaryMerge = false
            options.subOnly = false
            options.mp4RealTimeDecryption = false
            let argv = try build(argumentsFor: options)
            expectFalse(argv.contains("--binary-merge"))
            expectFalse(argv.contains("--sub-only"))
            expectFalse(argv.contains("--mp4-real-time-decryption"))
        }

        test("upstream-default-true-switches-turned-off-emit-False") {
            // AC-11：上游默认 true 的三项，UI 关闭时必须显式传 `=False`。
            var options = DownloadOptions()
            options.checkSegmentsCount = false
            options.delAfterDone = false
            options.useSystemProxy = false
            let argv = try build(argumentsFor: options)
            expectTrue(argv.contains("--check-segments-count=False"), "实际：\(preview(argv))")
            expectTrue(argv.contains("--del-after-done=False"))
            expectTrue(argv.contains("--use-system-proxy=False"))
        }

        test("upstream-default-true-switches-kept-on-emit-True") {
            var options = DownloadOptions()
            options.checkSegmentsCount = true
            options.delAfterDone = true
            options.useSystemProxy = true
            let argv = try build(argumentsFor: options)
            expectTrue(argv.contains("--check-segments-count=True"))
            expectTrue(argv.contains("--del-after-done=True"))
            expectTrue(argv.contains("--use-system-proxy=True"))
        }

        test("boolean-values-are-strict-True-False-literals") {
            // 上游把非布尔值判为 `Unrecognized command or argument` 而整体失败（契约 §1.3）。
            let forbidden: Set<String> = ["true", "false", "TRUE", "FALSE", "1", "0", "yes", "no", "maybe"]
            var options = DownloadOptions()
            options.concurrentDownload = true
            options.checkSegmentsCount = false
            let argv = try build(argumentsFor: options)
            for token in argv {
                expectFalse(forbidden.contains(token), "布尔值必须是 True/False 字面量，实际出现：\(token)")
            }
        }

        test("leading-dash-user-value-is-rejected") {
            // AC-10：以 `-` 开头的取值会被上游当成选项解析。
            var options = DownloadOptions()
            options.saveName = "--save-name"
            expectThrows(ArgumentError.self) { _ = try build(argumentsFor: options) }

            var headerOptions = DownloadOptions()
            headerOptions.headers = ["-H: evil"]
            expectThrows(ArgumentError.self) { _ = try build(argumentsFor: headerOptions) }

            var proxyOptions = DownloadOptions()
            proxyOptions.customProxy = "-http://127.0.0.1:8888"
            expectThrows(ArgumentError.self) { _ = try build(argumentsFor: proxyOptions) }
        }

        test("leading-dash-value-is-exposed-by-options") {
            // 校验的输入源本身：所有用户输入字段都必须进入 userProvidedValues。
            var options = DownloadOptions()
            options.headers = ["-H: evil"]
            expectTrue(options.userProvidedValues.contains { $0.value.hasPrefix("-") },
                       "非法取值必须能被 AC-10 校验枚举到")
        }

        test("headers-are-emitted-one-per-occurrence") {
            var options = DownloadOptions()
            options.headers = ["Referer: https://a.example", "Cookie: k=v"]
            let argv = try build(argumentsFor: options)
            expectEqual(argv.filter { $0 == "-H" || $0 == "--header" }.count, 2)
        }

        test("paths-and-log-file") {
            var options = DownloadOptions()
            options.keepLogFile = true
            let argv = try build(argumentsFor: options)
            expectTrue(argv.contains("--log-file-path"))
            let noLog = try build(argumentsFor: DownloadOptions())
            expectFalse(noLog.contains("--log-file-path"), "未开启保留日志时不得传")
        }

        test("group-order-paths-before-performance") {
            var options = DownloadOptions()
            options.threadCount = 16
            let argv = try build(argumentsFor: options)
            let tmpIndex = argv.firstIndex(of: "--tmp-dir")
            let threadIndex = argv.firstIndex(of: "--thread-count")
            expectNotNil(tmpIndex)
            expectNotNil(threadIndex)
            if let tmpIndex, let threadIndex {
                expectTrue(tmpIndex < threadIndex, "路径类必须排在性能类之前（契约 §1.2）")
            }
        }

        test("preview-string-is-escaped-argv") {
            // 命令预览与实际执行必须同源（契约 §6）。
            let argv = try build(argumentsFor: DownloadOptions())
            let preview = ShellEscaping.join(["/usr/local/bin/N_m3u8DL-RE"] + argv)
            expectTrue(preview.hasPrefix("/usr/local/bin/N_m3u8DL-RE "))
            expectContains(preview, "https://example.com/master.m3u8")
        }
    }
#endif
}

#if SF_ENGINE_READY
private func build(argumentsFor options: DownloadOptions) throws -> [String] {
    let input = InputSource.url("https://example.com/master.m3u8")
    // 契约：keepLogFile 开启时 TaskQueue 才会给 layout 传入 logFile（见 TaskQueue.start）。
    // 这里固定给一个路径，使 keepLogFile 成为唯一变量。
    let layout = TaskLayout(tmpDir: "/tmp/streamforge-tmp", saveDir: "/tmp/streamforge-save", logFile: "/tmp/streamforge-save/task.log")
    return try buildArguments(input: input, options: options, layout: layout)
}
#endif
