import Foundation

/// 极简测试 harness（ADR-006）：本机 CLT SDK 无 `XCTest.framework`，SwiftPM 亦不可用，
/// 因此测试 = 普通可执行文件 + 断言收集 + 退出码。禁止 import SwiftUI。
public final class TestRunner {
    public static let shared = TestRunner()

    struct Failure {
        let text: String
        let file: String
        let line: UInt
    }

    private struct TestCase {
        let suite: String
        let name: String
        let body: () throws -> Void
    }

    private var cases: [TestCase] = []
    private var suiteStack: [String] = []
    private var currentSuite = "Ungrouped"
    private var pending: [Failure] = []
    private var crash: String?

    private init() {}

    public var registeredCount: Int { cases.count }

    public func beginSuite(_ name: String) {
        suiteStack.append(currentSuite)
        currentSuite = name
    }

    public func endSuite() {
        currentSuite = suiteStack.popLast() ?? "Ungrouped"
    }

    public func add(_ name: String, _ body: @escaping () throws -> Void) {
        cases.append(TestCase(suite: currentSuite, name: name, body: body))
    }

    public func fail(_ text: String, file: StaticString, line: UInt) {
        pending.append(Failure(text: text, file: String(describing: file), line: line))
    }

    public func list() {
        for item in cases { print("\(item.suite)/\(item.name)") }
    }

    @discardableResult
    public func run(filter: String? = nil) -> Bool {
        let keyword = (filter?.isEmpty ?? true) || filter == "--filter" ? nil : filter
        let selected = cases.filter { item in
            guard let keyword else { return true }
            return "\(item.suite)/\(item.name)".localizedCaseInsensitiveContains(keyword)
        }
        var passed = 0
        var failed = 0
        let startedAt = Date()

        for item in selected {
            pending = []
            do {
                try item.body()
            } catch {
                pending.append(Failure(text: "抛出异常：\(error)", file: "", line: 0))
            }
            if pending.isEmpty {
                passed += 1
                print("PASS  \(item.suite)/\(item.name)")
            } else {
                failed += 1
                print("FAIL  \(item.suite)/\(item.name)")
                for failure in pending {
                    let location = failure.file.isEmpty
                        ? ""
                        : "\((failure.file as NSString).lastPathComponent):\(failure.line)  "
                    print("      \(location)\(failure.text)")
                }
            }
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        print(String(repeating: "-", count: 52))
        print(String(format: "%d passed, %d failed  (%.2fs)", passed, failed, elapsed))
        return failed == 0
    }
}

public func suite(_ name: String, _ body: () -> Void) {
    TestRunner.shared.beginSuite(name)
    body()
    TestRunner.shared.endSuite()
}

public func test(_ name: String, _ body: @escaping () throws -> Void) {
    TestRunner.shared.add(name, body)
}

public func expectTrue(_ cond: Bool, _ hint: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if !cond {
        TestRunner.shared.fail(hint.isEmpty ? "期望为 true" : hint, file: file, line: line)
    }
}

public func expectFalse(_ cond: Bool, _ hint: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if cond {
        TestRunner.shared.fail(hint.isEmpty ? "期望为 false" : hint, file: file, line: line)
    }
}

public func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ hint: String = "",
                                      file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected {
        let head = hint.isEmpty ? "" : "\(hint)："
        TestRunner.shared.fail("\(head)期望 \(describe(expected))，实际 \(describe(actual))", file: file, line: line)
    }
}

public func expectNil<T>(_ value: T?, _ hint: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if let value {
        let head = hint.isEmpty ? "" : "\(hint)："
        TestRunner.shared.fail("\(head)期望 nil，实际 \(describe(value))", file: file, line: line)
    }
}

public func expectNotNil<T>(_ value: T?, _ hint: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if value == nil {
        TestRunner.shared.fail(hint.isEmpty ? "期望非 nil，实际 nil" : "\(hint)：期望非 nil", file: file, line: line)
    }
}

public func expectContains(_ text: String, _ substring: String, _ hint: String = "",
                           file: StaticString = #filePath, line: UInt = #line) {
    if !text.contains(substring) {
        let head = hint.isEmpty ? "" : "\(hint)："
        TestRunner.shared.fail("\(head)期望包含 \(describe(substring))，实际 \(describe(text))", file: file, line: line)
    }
}

/// 近似相等，用于 clamp / 浮点聚合结果。
public func expectApproximately(_ actual: Double, _ expected: Double, tolerance: Double = 1e-6,
                                _ hint: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if !(actual - expected).magnitude.isLessThanOrEqualTo(tolerance) {
        let head = hint.isEmpty ? "" : "\(hint)："
        TestRunner.shared.fail("\(head)期望 ≈\(expected)，实际 \(actual)", file: file, line: line)
    }
}

public func expectThrows<E: Error>(_ expected: E.Type, _ body: () throws -> Void, _ hint: String = "",
                                   file: StaticString = #filePath, line: UInt = #line) {
    do {
        try body()
        let head = hint.isEmpty ? "" : "\(hint)："
        TestRunner.shared.fail("\(head)期望抛出 \(expected)，实际未抛出", file: file, line: line)
    } catch let error as E {
        _ = error
    } catch {
        TestRunner.shared.fail("期望抛出 \(expected)，实际 \(error)", file: file, line: line)
    }
}

public func expectNoThrow(_ body: () throws -> Void, _ hint: String = "",
                          file: StaticString = #filePath, line: UInt = #line) {
    do {
        try body()
    } catch {
        let head = hint.isEmpty ? "" : "\(hint)："
        TestRunner.shared.fail("\(head)不应抛出，实际 \(error)", file: file, line: line)
    }
}

/// 测试样本目录。以本文件的编译期路径定位，不依赖当前工作目录。
public enum Fixtures {
    private static let here = #filePath

    public static var directory: String {
        ((here as NSString).deletingLastPathComponent as NSString).appendingPathComponent("../Fixtures")
    }

    public static func path(_ name: String) -> String {
        (directory as NSString).appendingPathComponent(name)
    }

    public static func text(_ name: String) throws -> String {
        try String(contentsOfFile: path(name), encoding: .utf8)
    }

    public static func data(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path(name)))
    }
}

/// 统一的值描述。Optional 保留 `Optional(...)`，便于定位"本该 nil 却有值"。
public func describe<T>(_ value: T) -> String {
    String(describing: value)
}

/// 打印数组的前若干个元素描述，失败信息里便于对照。
public func preview<T>(_ items: [T], limit: Int = 6) -> String {
    let head = items.prefix(limit).map { describe($0) }
    let more = items.count > limit ? ", …(\(items.count))" : ""
    return "[" + head.joined(separator: ", ") + more + "]"
}
