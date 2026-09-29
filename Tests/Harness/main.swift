import Foundation

/// 显式注册入口（ADR-006）：Swift 没有 XCTest 的运行时发现机制，
/// 新增 `XxxTests.swift` 必须在此注册，否则永不执行。
///
/// 依赖尚未落地的分组由编译开关保护，落地后给 `Scripts/test.sh` 加上对应 `-D`：
///   `-D SF_PARSING_FULL`  Parsing 的 LogHints / ProgressParser / OutputParser 已就绪
///   `-D SF_ENGINE_READY`  Engine（ArgumentBuilder / ProcessHandle）与 Services 已就绪
@main
struct TestMain {
    static func main() {
        registerSplitterTests()
        registerFormatterTests()
        registerRingBufferTests()
        registerDependencyProbeTests()
        registerParserTests()
        registerArgumentBuilderTests()
        registerPauseControllerTests()

        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--list") {
            TestRunner.shared.list()
            exit(0)
        }
        var filter: String?
        if let index = args.firstIndex(of: "--filter"), index + 1 < args.count {
            filter = args[index + 1]
        } else if let plain = args.first, !plain.hasPrefix("--") {
            filter = plain
        }
        exit(TestRunner.shared.run(filter: filter) ? 0 : 1)
    }
}
