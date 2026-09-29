import Foundation

/// 依赖探测的**纯判定逻辑**（architecture.md §6）。
/// `ToolProbe` 把 I/O 事实翻译成状态与修复指引，故可完全在命令行覆盖；
/// 涉及 `DependencyResolver` 真实 I/O 的用例用 `-D SF_ENGINE_READY` 打开。
func registerDependencyProbeTests() {
    suite("DependencyProbe") {

        test("status-matrix-priority-order") {
            let minimum = ToolKind.nre.minimumVersion
            expectEqual(ToolProbe.status(exists: false, executable: false, runsSuccessfully: false,
                                         quarantined: false, versionText: nil, minimumVersion: minimum),
                        .notFound)
            expectEqual(ToolProbe.status(exists: true, executable: false, runsSuccessfully: false,
                                         quarantined: false, versionText: nil, minimumVersion: minimum),
                        .notExecutable)
            expectEqual(ToolProbe.status(exists: true, executable: true, runsSuccessfully: true,
                                         quarantined: true, versionText: "0.6.0", minimumVersion: minimum),
                        .quarantined, "隔离属性优先于版本判定（AC-13）")
            expectEqual(ToolProbe.status(exists: true, executable: true, runsSuccessfully: false,
                                         quarantined: false, versionText: "0.6.0", minimumVersion: minimum),
                        .archMismatch, "跑不起来 → 架构不匹配")
            expectEqual(ToolProbe.status(exists: true, executable: true, runsSuccessfully: true,
                                         quarantined: false, versionText: nil, minimumVersion: minimum),
                        .unverified(nil), "取不到版本 → 未验证但不硬阻断")
            expectEqual(ToolProbe.status(exists: true, executable: true, runsSuccessfully: true,
                                         quarantined: false, versionText: "0.6.0", minimumVersion: minimum),
                        .ok)
        }

        test("version-below-minimum-is-unverified-but-usable") {
            let status = ToolProbe.status(exists: true, executable: true, runsSuccessfully: true,
                                          quarantined: false, versionText: "N_m3u8DL-RE 0.5.9 beta",
                                          minimumVersion: ToolKind.nre.minimumVersion)
            expectEqual(status, .unverified("0.5.9"))
            expectTrue(status.isUsable, "低于下限仍允许使用，只常驻提示（架构 §6）")
        }

        test("minimum-version-0.6.0-and-missing-segment-is-zero") {
            expectEqual(ToolKind.nre.minimumVersion, "0.6.0", "本机实测版本即下限")
            expectEqual(ToolProbe.status(exists: true, executable: true, runsSuccessfully: true,
                                         quarantined: false, versionText: "0.6",
                                         minimumVersion: "0.6.0"),
                        .ok, "缺位段视为 0")
        }

        test("version-parsing-from-real-output") {
            expectEqual(ToolProbe.parseVersion(from: "N_m3u8DL-RE 0.6.0+df70f0b\nsecond line"), "0.6.0")
            expectEqual(ToolProbe.parseVersion(from: "ffmpeg version 7.1.1 Copyright (c) 2000-2025"), "7.1.1")
            expectNil(ToolProbe.parseVersion(from: "N_m3u8DL-RE (Beta version) 20260628"),
                      "无点号版本号不得误判")
            expectNil(ToolProbe.parseVersion(from: ""))
        }

        test("version-argument-differs-per-tool") {
            expectEqual(ToolKind.nre.versionArgument, "--version", "内核用 --version")
            expectEqual(ToolKind.ffmpeg.versionArgument, "-version", "ffmpeg 系用 -version")
            expectEqual(ToolKind.mp4decrypt.versionArgument, "-version")
        }

        test("required-tools") {
            expectTrue(ToolKind.nre.isRequired)
            expectTrue(ToolKind.ffmpeg.isRequired, "ffmpeg 在需要合并时必需")
            expectFalse(ToolKind.mp4decrypt.isRequired)
            expectFalse(ToolKind.shakaPackager.isRequired)
        }

        test("candidate-paths-order-and-dedupe") {
            let paths = ToolProbe.candidatePaths(for: .nre,
                                                 extraDirectories: ["/opt/custom", "/usr/local/bin"])
            expectEqual(paths.first, "/opt/custom/N_m3u8DL-RE", "额外目录优先")
            expectEqual(Set(paths).count, paths.count, "候选路径必须去重")
            for directory in ["/usr/local/bin", "/opt/homebrew/bin", "/opt/local/bin", "/usr/bin", "/Applications"] {
                expectTrue(paths.contains("\(directory)/N_m3u8DL-RE"), "缺少候选目录 \(directory)")
            }
            let home = NSHomeDirectory()
            expectTrue(paths.contains("\(home)/.local/bin/N_m3u8DL-RE"))
            expectTrue(paths.contains("\(home)/bin/N_m3u8DL-RE"))
            expectTrue(paths.contains("\(home)/Applications/N_m3u8DL-RE"))
        }

        test("repair-commands-are-copy-pasteable") {
            let nre = ExternalTool(kind: .nre, path: nil, version: nil, status: .notFound)
            let command = ToolProbe.repairCommand(for: nre)
            expectNotNil(command, "缺失必须给出可一键复制的修复命令（AC-12）")
            expectContains(command ?? "", "xattr -dr com.apple.quarantine")
            expectContains(command ?? "", "N_m3u8DL-RE")

            expectEqual(ToolProbe.repairCommand(for: ExternalTool(kind: .ffmpeg, path: nil,
                                                                  version: nil, status: .notFound)),
                        "brew install ffmpeg")
            expectNil(ToolProbe.repairCommand(for: ExternalTool(kind: .nre, path: "/usr/local/bin/N_m3u8DL-RE",
                                                                version: "0.6.0", status: .ok)),
                      "可用状态不得展示修复按钮")
        }

        test("quarantine-clear-command-quotes-path") {
            let command = ToolProbe.quarantineClearCommand(path: "/opt/my tools/N_m3u8DL-RE")
            expectContains(command, "xattr -dr com.apple.quarantine")
            expectContains(command, "'/opt/my tools/N_m3u8DL-RE'", "含空格路径必须转义（AC-13）")
        }

        test("status-usability") {
            expectTrue(ExternalToolStatus.ok.isUsable)
            expectTrue(ExternalToolStatus.unverified("0.5.0").isUsable)
            expectFalse(ExternalToolStatus.notFound.isUsable)
            expectFalse(ExternalToolStatus.notExecutable.isUsable)
            expectFalse(ExternalToolStatus.quarantined.isUsable)
            expectFalse(ExternalToolStatus.archMismatch.isUsable)
        }

        test("status-display-names-are-chinese") {
            expectEqual(ExternalToolStatus.notFound.displayName, "未找到")
            expectEqual(ExternalToolStatus.quarantined.displayName, "被隔离")
            expectEqual(ExternalToolStatus.archMismatch.displayName, "架构不匹配")
            expectEqual(ExternalToolStatus.unverified(nil).displayName, "版本未验证")
        }

        test("version-comparator-basics") {
            expectTrue(VersionComparator.isAtLeast("0.6.0", "0.6.0"))
            expectTrue(VersionComparator.isAtLeast("0.6.1", "0.6.0"))
            expectFalse(VersionComparator.isAtLeast("0.5.9", "0.6.0"))
            expectTrue(VersionComparator.isAtLeast("0.10.0", "0.6.0"), "数值比较而非字典序")
            expectEqual(VersionComparator.compare("0.6", "0.6.0"), .orderedSame)
            expectEqual(VersionComparator.extract(from: "v1.2.3-beta"), "1.2.3")
        }
    }

#if SF_ENGINE_READY
    suite("DependencyResolver") {
        // 只断言同步可见的初值：真实探测是异步且依赖本机 PATH，
        // 命令行里跑会变成"空跑通过"的假阳性，故不放进默认用例集。
        test("initial-state-blocks-task-submission") {
            let resolver = DependencyResolver()
            expectNil(resolver.tool(.nre))
            expectFalse(resolver.downloadEngineReady, "未探测通过前不得放行任务（AC-12）")
            expectFalse(resolver.isProbing)
        }
    }
#endif
}
