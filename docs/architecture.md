# StreamForge 架构设计

> 本文是 StreamForge（N_m3u8DL-RE 的 macOS 原生 SwiftUI 客户端）的架构契约。
> 前端工程师 / 下载内核工程师 / DevOps 均以本文 + `docs/contracts/` + `docs/decisions/` 为唯一依据。
> 与实现冲突时：**先改本文，再改代码**（活规格）。

| 项 | 值 |
|---|---|
| 项目 | StreamForge |
| 形态 | macOS 原生 App（SwiftUI，非跨平台壳） |
| 语言 / 编译器 | Swift 6.1.2（swiftlang-6.1.2.1.2），**语言模式固定 `-swift-version 5`** |
| 构建 | `swiftc` 直接编译 + shell 脚本（**禁止 SwiftPM**） |
| SDK | 显式锁定，优先 `MacOSX15.5.sdk`（见 ADR-001） |
| 部署目标 | macOS 13.0（`x86_64-apple-macosx13.0` / `arm64-apple-macosx13.0`） |
| 第三方依赖 | **零**。仅系统框架：SwiftUI / AppKit / Foundation / Darwin / UserNotifications / CoreGraphics |
| 内核 | N_m3u8DL-RE 0.6.0+df70f0b（Beta 20260628），MIT，外部依赖，不捆绑 |
| 图标 | SF Symbols（**禁止 emoji 作功能图标**，专家团 P0-1） |
| 配色 | 语义色 + 系统强调色（**禁止紫→粉渐变**，专家团 P0-2） |

---

## 1. 范围（in / out）

### 1.1 本次包含

- 新建任务：URL 输入、本地 `m3u8/mpd/ism` 文件选择、拖拽添加
- 任务队列：并发上限可配（默认 2），排队 / 启动 / 暂停 / 继续 / 取消 / 重试
- 实时进度：百分比、速度、ETA、分片 `已下载/总数`、多轨道（视频/音频/字幕）分别展示
- 日志面板：实时内核输出，按级别着色，可复制，RingBuffer 上限
- 外部依赖检测与修复引导（N_m3u8DL-RE、ffmpeg；可选 mp4decrypt / shaka-packager）
- 高级设置面板：线程数、重试、限速、代理、请求头、Cookie、解密 Key、文件名模板、直播选项
- 完成后系统通知（成功 / 失败）
- 深色模式（跟随系统 + 手动覆盖）
- 打包：`.app` bundle + dmg + GitHub Actions

### 1.2 明确不做（out-of-scope，杜绝镀金）

| 不做 | 原因 |
|---|---|
| 内嵌浏览器 / 网页自动嗅探 m3u8 | 需要 JS 渲染引擎，本质是浏览器插件，非 MVP |
| 账号体系、云同步、遥测 | 无服务端，违反隐私最小化 |
| 内嵌下载内核或自行实现 HLS/DASH 解析 | 重复造轮子，且上游 MIT 已可用 |
| 跨平台（Windows / Linux） | 用户明确要 macOS 原生 |
| 跨进程重启的"断点续传"保证 | 上游未公开承诺该能力，见 ADR-003 |
| 任务级动态改参（运行中改线程数/限速） | 上游这些是启动参数，运行中不可变 |
| 多语言 UI（i18n） | MVP 只做简体中文；`--ui-language` 仅透传给内核输出语言 |
| 插件 / 脚本扩展系统 | 无需求 |

---

## 2. 分层架构

```
┌──────────────────────────────────────────────────────────────┐
│  UI 层 (SwiftUI)                                              │
│  Views / Components / Theme                                   │
│  只做：渲染、事件转发、调用 Service；不含业务规则、不含进程知识 │
└───────────────┬──────────────────────────────────────────────┘
                │ 依赖（单向）
┌───────────────▼──────────────────────────────────────────────┐
│  业务层 (Services)                                            │
│  TaskQueue / TaskCoordinator / PauseController /               │
│  DependencyResolver / NotificationService / LogStore          │
│  只做：状态机、并发调度、编排；不 import SwiftUI               │
└───────┬───────────────────────────────┬──────────────────────┘
        │                               │
┌───────▼──────────────┐   ┌────────────▼─────────────────────┐
│  内核层 (Engine)      │   │  解析层 (Parsing)                 │
│  ProcessSpawner      │   │  OutputNormalizer / RecordSplitter │
│  ProcessHandle       │   │  LogLineParser / ProgressParser    │
│  OutputPump          │   │  OutputParser（状态机门面）        │
│  DownloadRunner      │   │  纯函数、无 I/O、无副作用           │
│  ArgumentBuilder     │   └────────────┬───────────────────────┘
└───────┬──────────────┘                │
        │                               │
┌───────▼───────────────────────────────▼──────────────────────┐
│  数据层 (Models + Config)                                     │
│  DownloadTask / TaskProgress / DownloadOptions / AppSettings   │
│  Persistence（UserDefaults + JSON）                            │
└──────────────────────────────────────────────────────────────┘
        ▲
┌───────┴──────────────────────────────────────────────────────┐
│  基础设施 (Util)  ByteFormatter / ShellEscaping / RingBuffer …  │
└──────────────────────────────────────────────────────────────┘
```

### 2.1 依赖铁律（出现即不合格）

1. 依赖**只能向下**：`UI → Services → Engine/Parsing → Models/Config → Util`。
2. **`Engine` / `Parsing` / `Services` 禁止 `import SwiftUI`**——它们必须能在命令行测试可执行文件里编译运行（见 §7）。
3. **`Models` / `Config` 禁止 `import SwiftUI`**（唯一例外：`AppSettings` 若需 `Color` 则改为存字符串枚举）。
4. **UI 层禁止直接调 `ProcessSpawner` / `ArgumentBuilder`**，必须经 `TaskCoordinator`。
5. **解析层禁止抛异常影响进程生命周期**：解析失败 → 记录 `LogEntry(level:.warn)`，绝不让任务崩溃（ADR-004）。
6. `Util` 只放无业务、无副作用的纯函数。
7. 跨模块只走对方 Service 接口，不跨层直连。

---

## 3. 目录结构与文件职责

> 单文件 **≤ 300 行**（不含空行与注释），入口文件只装配（< 100 行）。
> 行数为预算上限，非目标。

```
StreamForge/
├── VERSION                          # 版本号唯一真源（纯文本，如 1.0.0）
├── README.md
├── LICENSE                          # MIT（与上游一致，含上游版权声明）
├── NOTICE.md                        # 上游归属与许可声明
├── CHANGELOG.md
├── .gitignore
├── .swift-version                   # 6.1.2
├── Sources/StreamForge/
│   ├── App/
│   │   ├── StreamForgeApp.swift          # @main，只装配 Scene 与 AppEnvironment（≤60 行）
│   │   ├── AppDelegate.swift             # NSApplicationDelegate：退出清理、通知授权、Dock 行为
│   │   └── AppEnvironment.swift          # 依赖注入根：持有 TaskQueue/AppSettings/DependencyResolver
│   ├── Models/
│   │   ├── DownloadTask.swift            # 任务实体（值类型 + Identifiable）
│   │   ├── TaskPhase.swift               # 阶段枚举 + 终态判定
│   │   ├── TaskProgress.swift            # 任务级进度快照（聚合多轨道）
│   │   ├── TrackProgress.swift           # 单轨道进度（name/done/total/pct/bytes/speed/eta）
│   │   ├── DownloadOptions.swift         # 高级参数模型（Codable，字段与参数表 1:1）
│   │   ├── InputSource.swift             # .url(String) / .localFile(URL)
│   │   ├── LogEntry.swift                # 日志条目（ts/level/message/taskID）
│   │   ├── ExternalTool.swift            # 依赖描述：kind/path/version/status/quarantined
│   │   └── TaskHistoryRecord.swift       # 历史记录（仅元数据，用于"再次下载"）
│   ├── Config/
│   │   ├── Defaults.swift                # 全部默认值常量（线程 8 / 重试 3 / 超时 100 / 并发 2 …）
│   │   ├── AppSettings.swift             # ObservableObject + @Published 全局设置
│   │   ├── SettingsStore.swift           # UserDefaults 读写、版本迁移、Codable 编解码
│   │   ├── Paths.swift                   # 目录约定：tmp / save / log / support
│   │   └── HistoryStore.swift            # 历史 JSON 落盘（Application Support）
│   ├── Engine/
│   │   ├── ProcessSpawner.swift          # posix_spawn + POSIX_SPAWN_SETPGROUP + 双管道（≤180 行）
│   │   ├── ProcessHandle.swift           # killpg SIGSTOP/SIGCONT/SIGTERM/SIGKILL + 状态解码（≤120 行）
│   │   ├── OutputPump.swift              # DispatchSource 读管道 → 增量字节回调（≤120 行）
│   │   ├── DownloadRunner.swift          # 单任务进程生命周期：启动→泵→退出→收尾（≤250 行）
│   │   ├── ArgumentBuilder.swift         # DownloadOptions + InputSource → [String] argv（≤260 行）
│   │   └── ArgumentRules.swift           # 参数规则表：开关型/取值型/互斥/最小内核版本约束（≤200 行）
│   ├── Parsing/
│   │   ├── ParserPatterns.swift          # 全部正则常量集中一处（≤120 行）
│   │   ├── OutputNormalizer.swift        # ANSI 剥离 + UTF-8 增量解码（≤120 行）
│   │   ├── RecordSplitter.swift          # 时间戳 lookahead 切分（≤100 行）
│   │   ├── LogLineParser.swift           # 日志行 → LogEntry（≤100 行）
│   │   ├── ProgressParser.swift          # 粘连进度块 → [TrackProgress]（≤180 行）
│   │   ├── OutputParser.swift            # 门面：字节流 → (日志, 进度, 阶段)（≤160 行）
│   │   └── LogHints.swift                # 错误关键词 → 用户可懂的修复提示（≤100 行）
│   ├── Services/
│   │   ├── TaskQueue.swift               # 队列调度、并发上限、优先级（≤200 行）
│   │   ├── TaskCoordinator.swift         # 单任务状态机 + 编排 Runner/PauseController（≤260 行）
│   │   ├── PauseController.swift         # 暂停策略 P1/P2 与时长守卫（≤160 行）
│   │   ├── DependencyProbe.swift         # 可执行性/版本/隔离属性探测（≤180 行）
│   │   ├── DependencyResolver.swift      # 候选路径搜索 + 校验 + 修复指引生成（≤200 行）
│   │   ├── NotificationService.swift     # 系统通知授权与投递（≤120 行）
│   │   └── LogStore.swift                # 每任务环形日志缓冲（≤100 行）
│   ├── UI/                               # 文件命名与视觉规范以 docs/design.md §9.2 / 附录 B 为准
│   │   ├── MainWindow.swift              # NavigationSplitView 三窗格 + toolbar（≤120 行）
│   │   ├── SidebarView.swift             # 状态过滤 + 计数 .badge（≤100 行）
│   │   ├── AppCommands.swift             # 菜单栏 Commands（≤120 行）
│   │   ├── SFSymbols.swift               # SF Symbols 名称常量表（唯一出处，≤80 行）
│   │   ├── TaskList/
│   │   │   ├── TaskListView.swift        # 列表 + 工具栏（≤200 行）
│   │   │   ├── TaskRowView.swift         # 单行：名称/进度条/速度/ETA/控制按钮（≤180 行）
│   │   │   └── TaskDetailView.swift      # 详情：轨道表 + 参数回放 + 日志（≤220 行）
│   │   ├── Composer/
│   │   │   ├── NewTaskSheet.swift        # 新建任务 Sheet（≤220 行）
│   │   │   └── DropZoneOverlay.swift     # 拖拽悬停层与接收（≤140 行）
│   │   ├── Settings/
│   │   │   ├── SettingsView.swift        # 分组容器（≤80 行）
│   │   │   ├── GeneralSettingsView.swift       # 目录、并发、通知、外观
│   │   │   ├── DownloadSettingsView.swift      # 线程/重试/超时/限速/mt
│   │   │   ├── NetworkSettingsView.swift       # 代理、请求头、Cookie、BaseURL
│   │   │   ├── DecryptionSettingsView.swift    # Key / 引擎 / 二进制路径
│   │   │   ├── OutputSettingsView.swift        # save-name / save-pattern / 混流
│   │   │   ├── LiveSettingsView.swift          # 直播选项
│   │   │   └── AdvancedSettingsView.swift      # 杂项：custom-hls / urlprocessor / ui-language
│   │   ├── DependencyView.swift          # 依赖状态与修复指引（≤200 行）
│   │   ├── LogPanel/
│   │   │   ├── LogPanelView.swift        # 等宽日志 + 过滤 + 复制 + 清空（≤180 行）
│   │   │   └── LogRowView.swift          # 单行着色（≤80 行）
│   │   ├── Components/
│   │   │   ├── ProgressBarView.swift     # 自定义进度条（≤80 行）
│   │   │   ├── StatBadgeView.swift       # 速度/ETA/分片徽章（≤80 行）
│   │   │   ├── FormField.swift           # 表单行 + 帮助气泡（≤80 行）
│   │   │   └── StatusPillView.swift      # 状态胶囊（≤60 行）
│   │   └── Design/
│   │       └── SFDesignTokens.swift      # 设计令牌：间距/字号/语义色（≤120 行，与 design.md 同源）
│   └── Util/
│       ├── ByteFormatter.swift           # 字节/速度格式化（≤80 行）
│       ├── DurationFormatter.swift       # ETA / 已用时（≤80 行）
│       ├── ShellEscaping.swift           # 命令预览用转义（仅展示，不用于执行）（≤60 行）
│       ├── RingBuffer.swift              # 定长环形缓冲（≤80 行）
│       └── VersionComparator.swift       # 版本字符串比较（≤60 行）
├── Tests/
│   ├── Harness/
│   │   ├── MiniTest.swift                # 断言 API（≤180 行）
│   │   └── main.swift                    # 注册 + 运行 + 退出码（≤60 行）
│   ├── ParserTests.swift
│   ├── SplitterTests.swift
│   ├── ArgumentBuilderTests.swift
│   ├── PauseControllerTests.swift
│   ├── DependencyProbeTests.swift
│   ├── FormatterTests.swift
│   ├── RingBufferTests.swift
│   └── Fixtures/
│       ├── kernel_progress_glued.txt     # 真实抓取：粘连进度 + 日志（4.6 KB）
│       ├── kernel_stderr_stacktrace.txt  # 真实抓取：.NET 未捕获异常
│       ├── kernel_log_levels.txt         # 合成：四级日志 + 中英文混排
│       ├── kernel_ansi.txt               # 合成：含 CSI 转义
│       └── kernel_live.txt               # 合成：直播流程关键行
├── Scripts/
│   ├── find-sdk.sh                       # SDK 探测（带编译探针与缓存）
│   ├── sdk-probe.swift                   # 探针源码（SwiftUI + @main 最小可编译集）
│   ├── build.sh
│   ├── test.sh
│   ├── package.sh
│   ├── make-icon.swift                   # CoreGraphics 生成 AppIcon.icns
│   └── check-layout.sh                   # 门禁：单文件 ≤300 行、依赖方向、无 emoji
├── docs/
│   ├── architecture.md                   # 本文
│   ├── RELEASING.md
│   ├── contracts/
│   │   ├── kernel-output-contract.md     # 内核输出文法（解析层唯一依据）
│   │   └── cli-argument-contract.md      # 参数表与映射规则
│   └── decisions/ADR-001…ADR-006.md
└── .github/workflows/{ci.yml,release.yml}
```

---

## 4. 模块契约（关键接口签名）

> 接口即契约。下列签名不得擅自变更；需要变更时先改本文 + 同步通知。

### 4.1 Engine

```swift
// ProcessSpawner：唯一允许创建子进程的地方。禁止 /bin/sh -c（无注入面）。
struct SpawnResult { let pid: pid_t; let pgid: pid_t; let stdoutFD: Int32; let stderrFD: Int32 }
enum SpawnError: Error { case execFailed(String, errno: Int32); case pipeFailed(Int32) }
func spawnGroup(executable: String, arguments: [String], environment: [String: String]?) throws -> SpawnResult

// ProcessHandle
final class ProcessHandle {
    let pid: pid_t
    func suspend()      // killpg(pgid, SIGSTOP)
    func resume()       // killpg(pgid, SIGCONT)
    func terminate()    // resume() 后 killpg(pgid, SIGTERM)，保证停止中的进程也能收到
    func forceKill()    // killpg(pgid, SIGKILL)
    func isAlive() -> Bool
    func wait() -> ProcessExit
}
struct ProcessExit { let rawStatus: Int32
    var signal: Int32? { rawStatus & 0x7f != 0 ? rawStatus & 0x7f : nil }   // 注意：WIFEXITED/WEXITSTATUS 宏在 Swift 不可用，必须手工解码
    var code: Int? { rawStatus & 0x7f == 0 ? Int((rawStatus >> 8) & 0xff) : nil }
}

// OutputPump
final class OutputPump {
    init(stdoutFD: Int32, stderrFD: Int32, queue: DispatchQueue, onChunk: @escaping (_ isStderr: Bool, _ data: Data) -> Void)
    func start(); func cancel()
}

// ArgumentBuilder
func buildArguments(input: InputSource, options: DownloadOptions, layout: TaskLayout) -> [String]
struct TaskLayout { let tmpDir: String; let saveDir: String; let logFile: String? }
```

**参数构建硬规则**

1. 顺序固定：`[executable, input, 必传开关, 路径类, 性能类, 网络类, 选择类, 解密类, 输出类, 直播类, 杂项]`。
2. 必传：`--no-ansi-color`、`--disable-update-check`、`--tmp-dir`、`--save-dir`、`--save-name`。
3. 值为空字符串的 Option **不输出**该参数；`false` 的开关型 Option **不输出**（上游多数开关默认已是 false）。
4. 上游默认 `true` 的三项必须**显式决策**并在 UI 中暴露：`--check-segments-count`(true)、`--del-after-done`(true)、`--use-system-proxy`(true)。当 UI 关闭它们时，必须显式传 `=False` 形式（见 `cli-argument-contract.md`）。
5. 任何来自用户输入的取值禁止以 `-` 开头（会被上游解析为选项）；`ArgumentBuilder` 对 `-H` 值做前缀校验，非法则拒绝构建并给出错误。
6. 生成的 argv 同时用于**命令预览**（UI 展示，经 `ShellEscaping` 转义）与**实际执行**（不转义，直接 argv 传递）。

### 4.2 Parsing

```swift
struct ParseResult { let logs: [LogEntry]; let tracks: [TrackProgress]; let phaseHint: PhaseHint? }
final class OutputParser {
    /// 追加字节；返回本批解析出的结果。线程不安全，调用方负责串行化。
    func ingest(_ data: Data, isStderr: Bool) -> ParseResult
    func flushTail() -> ParseResult        // 进程退出时冲刷残留缓冲
    var latestTracks: [TrackProgress] { get }
}
```
详见 `docs/contracts/kernel-output-contract.md`。

### 4.3 Services

```swift
@MainActor final class TaskQueue: ObservableObject {
    @Published private(set) var tasks: [DownloadTask]
    let maxConcurrent: Int                       // 来自 AppSettings，默认 2
    func enqueue(_ input: InputSource, options: DownloadOptions)
    func start(_ id: UUID); func pause(_ id: UUID); func resume(_ id: UUID)
    func cancel(_ id: UUID, deleteTemp: Bool); func retry(_ id: UUID)
}

final class TaskCoordinator {                    // 非 MainActor，运行在自己的串行队列
    func start(); func pause(); func resume(); func cancel(deleteTemp: Bool)
    var onProgress: ((TaskProgress) -> Void)?    // 节流 ≤10 Hz，回主线程
    var onLogs: (([LogEntry]) -> Void)?
    var onPhaseChange: ((TaskPhase) -> Void)?
}

final class PauseController {
    func beginPause()                            // SIGSTOP；启动时长守卫
    func endPause()                              // SIGCONT
    var onAutoConvert: (() -> Void)?             // 超过阈值 → 转 P2（停止并保留 tmp）
}
```

### 4.4 Config

```swift
final class AppSettings: ObservableObject {
    @Published var maxConcurrentTasks: Int = 2
    @Published var defaultSaveDir: String
    @Published var deleteTempOnCancel: Bool = true
    @Published var appearance: AppearancePreference = .system
    @Published var notifyOnSuccess: Bool = true
    @Published var notifyOnFailure: Bool = true
    @Published var toolPaths: [ToolKind: String]
    @Published var defaultOptions: DownloadOptions
}
```

持久化：`UserDefaults`（suite: `com.streamforge`）存 `AppSettings`；历史记录存
`~/Library/Application Support/StreamForge/history.json`（Codable，写入原子化：先写 tmp 再 rename）。
**不做沙箱**（需要执行任意外部二进制并写用户自选目录），因此不使用 security-scoped bookmark。

---

## 5. 构建方案（`Scripts/build.sh`）

### 5.1 SDK 探测（`Scripts/find-sdk.sh`）

按序尝试，**第一个能编译通过探针的即采用**，结果缓存到 `.build/.sdk-cache`（key = SDK 路径 + swift 版本）：

1. `$MACOSX_SDK` 环境变量覆盖
2. `MacOSX15.5.sdk` → `15.4` → `15.2` → `14.5`，分别在
   - `/Library/Developer/CommandLineTools/SDKs`
   - `$(xcode-select -p)/Platforms/MacOSX.platform/Developer/SDKs`
   - `/Applications/Xcode*.app/.../MacOSX.platform/Developer/SDKs`
3. 最后兜底 `xcrun --sdk macosx --show-sdk-path`（CI 完整 Xcode 场景）

探针 `Scripts/sdk-probe.swift` 必须**包含 SwiftUI 真实用法**（`@main` + `WindowGroup` + `Settings` + `Image(systemName:)` + `ObservableObject`），因为
"SDK 26.2 + Swift 6.1.2" 的不兼容只在 SwiftUI 泛型展开时才暴露（报错 `cannot suppress '~Copyable' on generic parameter`）。
探针编译 20 秒左右，命中缓存后为 0。

### 5.2 build.sh 要点

```bash
set -euo pipefail
ARCH=${ARCH:-$(uname -m)}                 # x86_64 / arm64
MIN_MACOS=${MIN_MACOS:-13.0}
CONFIG=${CONFIG:-release}
VERSION=$(cat VERSION | tr -d '[:space:]')
SDK=$(scripts/find-sdk.sh)                # 失败则打印诊断并以 70 退出

SRCS=$(find Sources -name '*.swift' -print0 | xargs -0 -n1 | sort)   # 排序保证可复现
OPT_FLAGS=(-O)                            # debug: -Onone -g -D DEBUG
COMMON=(-parse-as-library -swift-version 5
        -target "${ARCH}-apple-macosx${MIN_MACOS}"
        -sdk "$SDK"
        -D SF_VERSION=\"$VERSION\")

swiftc "${OPT_FLAGS[@]}" "${COMMON[@]}" $SRCS -o ".build/${CONFIG}/StreamForge"
```

硬约束：

- **必须 `-parse-as-library`**（否则 `@main` 与顶层代码冲突）。
- **必须 `-swift-version 5`**：避免 Swift 6 严格并发检查在 MVP 阶段制造大量 `Sendable` / actor 隔离错误；并发安全靠串行队列 + 显式 `@MainActor` 标注保证。
- **只用显式 `-target`，不用 `-macosx-version-min`**（二者冲突）。
- 编译前跑 `Scripts/check-layout.sh` 门禁（单文件 ≤300 行、Parsing/Engine/Services 无 `import SwiftUI`、全仓库无 emoji 图标）。
- 产物落在 `.build/<config>/`，`Scripts/package.sh` 组装 bundle。

### 5.3 打包（`Scripts/package.sh`）

```
dist/StreamForge.app/Contents/
├── Info.plist           # 由 Resources/Info.plist.template 模板 + VERSION 渲染
├── MacOS/StreamForge    # 编译产物
└── Resources/AppIcon.icns
```

`Info.plist` 必备键：
`CFBundleIdentifier=com.streamforge`、`CFBundleExecutable=StreamForge`、
`CFBundleShortVersionString`/`CFBundleVersion`（取自 `VERSION`）、
`LSMinimumSystemVersion=13.0`、`NSHighResolutionCapable=true`、
`NSRequiresAquaSystemAppearance=false`（允许深色）、
`CFBundleIconFile=AppIcon`、`ITSAppUsesNonExemptEncryption=false`、
`NSPrincipalClass=NSApplication`。

- 图标：`Scripts/make-icon.swift` 用 **CoreGraphics 路径绘制**（不用 SF Symbols——SF Symbols 许可不允许用作 App Icon），输出 iconset 后 `iconutil -c icns`。
- 签名：`codesign --force --deep --sign -`（ad-hoc，保证本地可启动）；发布态未签名，README 提供绕过 Gatekeeper 指引（见 RELEASING.md）。
- dmg：`hdiutil create -volname "StreamForge" -srcfolder dist/StreamForge.app -ov -format UDZO dist/StreamForge-$VERSION.dmg`；同时产出 zip 与 `shasum -a 256` 校验文件。

### 5.4 CI

- `ci.yml`：`macos-15` runner → `check-layout.sh` → `test.sh` → `build.sh` → 冒烟（启动 `.app/Contents/MacOS/StreamForge`，3 秒后进程仍存活即通过）→ 上传 artifact。
- `release.yml`：tag `v*` 触发 → 同构建 → `package.sh` → 创建 Release 草稿（dmg + zip + 校验和）。
- 两个 workflow 都必须先跑 `find-sdk.sh` 并打印选中 SDK，便于排障。
- **注意**：`macos-latest` 会漂移，RELEASING.md 中建议固定为 `macos-15`，避免某天镜像只带 26.x SDK 导致 Swift 6.1.2 编译失败。

---

## 6. 依赖检测与引导（DependencyResolver）

探测顺序（首个命中且校验通过者生效）：

1. 用户在设置里显式指定的路径
2. `AppSettings.toolPaths` 上次成功路径（缓存）
3. 候选目录 × 文件名：`/usr/local/bin`、`/opt/homebrew/bin`、`/opt/local/bin`、`$HOME/.local/bin`、`$HOME/bin`、`/Applications`、`$HOME/Applications`、`/usr/bin`
4. `PATH` 环境变量逐段查找（对 `PATH` 做去重与存在性校验）

对每个候选执行**三步校验**：

| 步骤 | 手段 | 失败含义 |
|---|---|---|
| 可执行 | `FileManager.isExecutableFile` + `access(path, X_OK)` | 路径无效 |
| 能跑起来 | 运行 `<path> --version`（内核）/ `-version`（ffmpeg），**2 秒超时**，取 stdout 首行 | 架构不匹配 / 依赖缺失 / 无权限 |
| 隔离属性 | `xattr -p com.apple.quarantine <path>` | 被 Gatekeeper 隔离，需 `xattr -dr com.apple.quarantine` |

版本策略：`minVerified = 0.6.0`（本机实测版本）。低于该值或无法解析版本 → 状态 `.unverified`，**允许继续使用但常驻提示**，不硬阻断。

`ExternalTool.status` 枚举：`.ok` / `.notFound` / `.notExecutable` / `.quarantined` / `.unverified(version)` / `.archMismatch`。
`DependencyView` 针对每种状态渲染一段**可一键复制**的修复命令，例如：

```
# N_m3u8DL-RE 缺失
curl -L -o /tmp/NRE.tar.gz https://github.com/nilaoda/N_m3u8DL-RE/releases/download/v0.6.0-beta/N_m3u8DL-RE_v0.6.0-beta_osx-arm64_20260629.tar.gz
tar -xzf /tmp/NRE.tar.gz -C /tmp
sudo mkdir -p /usr/local/bin && sudo mv /tmp/N_m3u8DL-RE /usr/local/bin/
sudo xattr -dr com.apple.quarantine /usr/local/bin/N_m3u8DL-RE
chmod +x /usr/local/bin/N_m3u8DL-RE

# ffmpeg 缺失
brew install ffmpeg
```

启动时机：App 启动即异步探测；结果写入 `AppEnvironment`。任一必需依赖缺失时，主界面顶部显示持续横幅（SF Symbol `wrench.and.screwdriver`），新建任务按钮保持可点但提交时二次提示。
`ffmpeg` 只在需要合并/解密时才必需；未启用 `--skip-merge` 且 ffmpeg 缺失 → 任务提交前阻断并给出指引。

---

## 7. 测试方案（自写 harness，替代 XCTest）

### 7.1 为什么不用 XCTest

本机 Command Line Tools 的 SDK 中不存在 `XCTest.framework`（已实测），且 SwiftPM 崩溃会连带 `swift test` 不可用。
因此：**测试 = 普通可执行文件 + 断言库 + 退出码**。

### 7.2 编译范围

`Scripts/test.sh` 编译时**排除** `Sources/StreamForge/App` 与 `Sources/StreamForge/UI`：

```bash
SRCS=$(find Sources -name '*.swift' \
        -not -path '*/UI/*' -not -path '*/App/*' | sort)
TESTS=$(find Tests -name '*.swift' | sort)
swiftc "${COMMON[@]}" $SRCS $TESTS -o .build/test/StreamForgeTests
.build/test/StreamForgeTests "$@"   # 退出码非 0 = 失败
```

这同时是**架构门禁**：UI 层一旦混入业务逻辑，就无法被编译进测试，会被立即发现。

### 7.3 Harness API（`Tests/Harness/MiniTest.swift`）

```swift
public final class TestRunner {
    public static let shared: TestRunner
    public func register(_ suite: String, _ name: String, _ body: @escaping () throws -> Void)
    @discardableResult public func run(filter: String? = nil) -> Bool
}

public func test(_ name: String, _ body: @escaping () throws -> Void)          // 注册到当前 suite
public func suite(_ name: String, _ body: () -> Void)                          // 嵌套分组

public func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ hint: String = "", file: StaticString = #file, line: UInt = #line)
public func expectTrue(_ cond: Bool, _ hint: String = "", file: StaticString = #file, line: UInt = #line)
public func expectFalse(_ cond: Bool, _ hint: String = "", ...)
public func expectNil<T>(_ v: T?, _ hint: String = "", ...)
public func expectNotNil<T>(_ v: T?, _ hint: String = "", ...)
public func expectContains(_ text: String, _ substring: String, ...)
public func expectThrows<E: Error>(_ expected: E.Type, _ body: () throws -> Void, ...)
```

输出格式（`PASS`/`FAIL` 单行 + 汇总），支持 `--filter <关键字>` 与 `--list`：

```
PASS  Parser/glued-log-and-progress-split
FAIL  Parser/eta-unknown
      Tests/ParserTests.swift:118 期望 eta == nil，实际 Optional(0)
---------------------------------------------
42 passed, 1 failed  (0.08s)
```

`main.swift` **显式注册**各测试文件（Swift 无 XCTest 运行时发现机制）：

```swift
registerParserTests(); registerSplitterTests(); registerArgumentBuilderTests()
registerPauseControllerTests(); registerDependencyProbeTests()
registerFormatterTests(); registerRingBufferTests()
exit(TestRunner.shared.run(filter: CommandLine.arguments.dropFirst().first) ? 0 : 1)
```

**纪律**：新增 `XxxTests.swift` 必须在 `main.swift` 注册，否则永不执行——PR 复核必查项。

### 7.4 必须覆盖的用例（对应「生成式代码失效模式」）

| 失效模式 | 定向用例 |
|---|---|
| Happy-path 偏差 | 每个解析器都有"空输入 / 半行输入 / 只有进度无日志 / 只有日志无进度"用例 |
| 沉默逻辑错误 | 粘连切分：断言日志条数 == 时间戳个数；**变异加固**：把 lookahead 正则写成不带 `(?=...)` 的普通匹配，必须有测试变红 |
| 幻觉依赖/接口 | `PauseControllerTests` 用可注入的 `ProcessControlling` 协议替身，不真起进程；`ProcessHandle` 真机用例仅在 `--include-integration` 下跑 |
| 边界 | 速度 `-0.00Bps`、百分比 `-0.00%`、ETA `--:--:--`、速度后缀 `Bps/KBps/MBps`、重试计数 `(1)`、字节字段缺失 |
| UTF-8 | 跨 chunk 边界被截断的多字节字符（进度条 `━` 三字节）不得产生乱码或丢帧 |
| 并发 | `TaskQueue` 并发上限：并发 2 时第三任务必须排队 |

### 7.5 Fixtures

`Tests/Fixtures/*.txt` 均为**真实或近真实内核输出**，测试只读文件，不依赖网络、不依赖内核是否安装。

---

## 8. UI 层规范

### 8.1 状态管理（部署目标决定）

- **禁止 `@Observable` / Observation 框架**（要求 macOS 14）。用 `ObservableObject` + `@Published` + `@StateObject`/`@EnvironmentObject`/`@ObservedObject`。
- 所有 `@Published` 变更只在 **MainActor** 发生；`TaskCoordinator` 的回调先 `DispatchQueue.main.async` 再赋值。
- 进度刷新**节流 ≤10 Hz**（100 ms 合并窗口），禁止每个字节触发 SwiftUI 求值。
- 日志列表用 `LazyVStack` + `RingBuffer`（默认上限 5000 条/任务）。

### 8.2 macOS 13 可用 API 白名单约束

禁用（macOS 14+）：`.inspector`、`@Observable`、`Table` 的部分新修饰符、`ContentUnavailableView`、`\`.scrollBounceBehavior` 等。
可用：`NavigationSplitView`、`Table`、`Form`/`.formStyle(.grouped)`、`Settings` scene、`MenuBarExtra`（可选）、`.onDrop`、`.preferredColorScheme`、`Commands`。

### 8.3 SF Symbols 图标表（唯一出处：`UI/SFSymbols.swift`）

> **与 `docs/design.md` 的关系**：视觉规范（尺寸、间距、分组顺序、文案库）以 design.md 为准；
> 本节只给"功能 → 符号名"的映射草案。**硬约束：所有符号必须是 SF Symbols 4 或更早**
> （macOS 13 运行时绑定 SF Symbols 4，5+ 符号会渲染为空白框，design.md 第 521 行已列为高频坑）。
> 下表与 design.md 附录 B 冲突时，**以 design.md 为准**。

| 用途 | Symbol | 用途 | Symbol |
|---|---|---|---|
| 新建任务 | `plus` | 开始 | `play.fill` |
| 暂停 | `pause.fill` | 继续 | `play.fill` |
| 停止 | `stop.fill` | 取消 | `xmark.circle` |
| 重试 | `arrow.clockwise` | 清空 | `trash` |
| 队列 | `list.bullet` | 日志 | `terminal` |
| 设置 | `gearshape` | 目录 | `folder` |
| 链接 | `link` | 本地文件 | `doc.badge.plus` |
| 速度 | `speedometer` | 线程/CPU | `cpu` |
| 时长 | `clock` | 分片 | `square.stack.3d.up` |
| 网络/代理 | `network` | 请求头 | `list.bullet.rectangle` |
| Key/解密 | `key.fill` | 解密引擎 | `lock.open` |
| 字幕 | `captions.bubble` | 视频轨 | `film` |
| 音频轨 | `waveform` | 合并 | `arrow.triangle.merge` |
| 成功 | `checkmark.circle.fill` | 失败 | `exclamationmark.triangle.fill` |
| 警告 | `exclamationmark.triangle` | 依赖 | `wrench.and.screwdriver` |
| 拖拽 | `arrow.down.doc` | 深色模式 | `moon.fill` / `sun.max.fill` |
| 复制 | `doc.on.doc` | 在访达中显示 | `folder.badge.person.crop` |

**P0-1**：任何视图、菜单、按钮标签中不得出现 emoji；图标一律走 `SFSymbols` 常量。
**P0-2**：禁止紫→粉渐变；强调色用 `Color.accentColor`，语义色用 `green/orange/red/secondary`，深色模式由系统语义色自动适配，禁止硬编码渐变。

### 8.4 拖拽

- 列表与新建区均接受 `.onDrop(of: [.url, .fileURL, .text])`：
  - `.text` 以 `http://` / `https://` 开头 → 作为 URL；
  - `.text` 以 `/` 或 `file://` 开头且文件存在 → 作为本地文件；
  - `.fileURL` 扩展名在 `m3u8|mpd|ism|ismv|txt|json` 白名单内 → 本地文件，否则拒绝并提示。
- 拖拽中显示虚线边框高亮（`DropZoneOverlay`）。

### 8.5 通知

`UNUserNotificationCenter` 首次成功投递前请求授权；成功通知标题为任务名、副标题为保存路径，点击后打开保存目录（`NSWorkspace.open`）。失败通知附 `lastError` 首行。

### 8.6 与 `docs/design.md` 的对齐点（跨角色一致性）

| 项 | 本文 | design.md | 处理 |
|---|---|---|---|
| 状态词 | 准备中 / 排队中 / 下载中 / 已暂停 / 合并中 / 已完成 / 失败 / 已取消 / **已停止（可重试）** | 七词，无「准备中」「已停止」 | 采用 design.md §9.3 文案；「准备中」「已停止（可重试）」为 ADR-003 引入的新状态，需设计师补两条文案 |
| 依赖版本下限 | `0.6.0`（本机实测版本） | `0.2.1`（占位） | **统一为 0.6.0**，design.md §9.3 需同步 |
| 设置分组 | 通用 / 下载 / 网络 / 解密 / 输出 / 直播 / 高级 | 下载 / 网络 / 解密 / 输出 / 直播 / 高级（六组） | 以 design.md 六组为准，「通用」组内容（目录/通知/外观）并入首组 |
| 图标 | 本节映射表 | 附录 B（含引入版本标注） | 以 design.md 为准；二者均须 ≤ SF Symbols 4 |

---

## 9. 风险清单与不可行项

| # | 等级 | 风险 | 缓解 |
|---|---|---|---|
| R1 | 高 | Swift 6.1.2 与 SDK 26.2 不兼容，CI 镜像漂移后可能无 15.x SDK | `find-sdk.sh` 多级探测 + 打印诊断；CI 固定 `macos-15`；必要时 `xcode-select -s` 锁定 Xcode 16 |
| R2 | 高 | 未签名/未公证 → 用户首次打开被 Gatekeeper 拦截 | README + `DependencyView` 提供 `xattr -dr com.apple.quarantine`；不做公证（无账号） |
| R3 | 中高 | 暂停语义不完美：SIGSTOP 期间 HTTP 请求超时会在恢复瞬间集中触发 | ADR-003 的 P1/P2 双策略 + 80s 时长守卫 + UI 诚实文案 |
| R4 | 中高 | 上游是 Beta（20260628），输出格式无稳定性承诺 | 解析层"宽松匹配 + 未知忽略"，绝不影响进程生命期；终态以退出码为准 |
| R5 | 中 | 进度行**无分隔符**（已实测：4623 字节仅 8 个 `\n`，0 个 `\r`），多轨道同名会串台 | 按轨道名归并取最新；同名轨道为已知限制，UI 提示 |
| R6 | 中 | SwiftUI 视图天然冗长，与 ≤300 行门禁冲突 | 一个视图文件一个组件；`Components/` 复用；`check-layout.sh` 硬门禁 |
| R7 | 中 | 部署目标 13.0 可用性约束 | 已实测 `-target x86_64-apple-macosx13.0 -sdk MacOSX15.5.sdk` 编译通过；严守 §8.2 白名单 |
| R8 | 中 | 无 SwiftPM → 无增量编译，全量编译随文件数增长 | 当前规模约 20–40 s，可接受；CI 缓存 `.build` |
| R9 | 中 | 上游二进制需用户自备，缺失则所有任务不可用 | 启动即探测 + 持续横幅 + 可复制修复命令 |
| R10 | 低 | 直播任务日志与进度暴涨 | RingBuffer 上限 + 上游 `--log-file-path` 自行落盘 |
| R11 | 合规 | 下载受版权保护内容的责任归属；上游许可 | `LICENSE`(MIT) + `NOTICE.md` 完整保留上游版权；README 声明"仅供合法用途" |
| R12 | 低 | SF Symbols 不得用于 App Icon（许可限制） | `make-icon.swift` 用 CoreGraphics 路径绘制 |

### 9.1 不可行项（不得向用户承诺）

1. **跨进程/跨重启的断点续传**：上游未公开承诺。只提供"重试（保留临时目录）"，UI 不写"断点续传"。
2. **暂停直播录制不丢内容**：SIGSTOP 期间播放列表持续刷新，恢复后必然丢片段；直播任务的暂停按钮降级为"停止"。
3. **运行中动态改参**：线程数、限速、代理等是启动参数，运行中不可变。
4. **精确剩余时间**：上游 ETA 可能为 `--:--:--`，UI 显示 `--`。
5. **速度限制的逐任务实时调整**：`-R` 为启动参数。
6. **内嵌浏览器抓流**：不做。

---

## 10. 端到端验证（Definition of Done）

```bash
# 1 门禁
./Scripts/check-layout.sh                 # 单文件 ≤300 行 / 依赖方向 / 无 emoji

# 2 测试（纯逻辑，不依赖内核）
./Scripts/test.sh                          # 退出码 0，0 failed

# 3 构建
./Scripts/build.sh                         # 打印选中的 SDK；产物 .build/release/StreamForge

# 4 打包
./Scripts/package.sh                       # dist/StreamForge.app + dmg

# 5 冒烟：启动后 3 秒进程仍存活
open dist/StreamForge.app && sleep 3 && pgrep -f "StreamForge.app/Contents/MacOS" >/dev/null

# 6 核心成功流（需联网 + 已安装内核）
#    新建任务：粘贴一个公开 HLS 测试 URL → 保存目录 → 开始
#    断言：日志面板出现 Loading URL / Content Matched / Start downloading
#    断言：进度条推进、速度非零、ETA 从 --:--:-- 变为 HH:MM:SS
#    断言：完成后状态为"已完成"，系统通知出现，输出文件存在且非空

# 7 关键错误流
#    输入一个不可达 URL → 断言：日志出现 ERROR，状态"失败"，通知为失败，退出码非 0
#    暂停 → 等待 90s → 断言：自动转为"已停止（可重试）"，未出现大量 ERROR 雪崩
#    取消 → 断言：进程组整体退出（ps 无残留），临时目录按设置清理

# 8 依赖缺失流
#    临时把内核路径改到不存在 → 断言：横幅出现 + 修复命令可复制 + 提交任务被阻断
```

关键成功流 + 三条错误流全绿，且 `test.sh` 回归率零，才算交付完成。
