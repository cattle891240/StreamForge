# Spec - StreamForge v1.0.0

> 生成日期：2026-09-28
> 基于：docs/architecture.md + docs/design.md + docs/contracts/（内核输出契约 / 参数契约）+ ADR-001…006
> 状态：已确认（唯一交互点已完成，用户选择「SwiftUI 原生 + 未签名 dmg + 一次性完整交付」）

本文是开发、测试、验收的**唯一范围依据**。架构细节见 `architecture.md`，视觉细节见 `design.md`，
内核文法见 `contracts/kernel-output-contract.md`，参数映射见 `contracts/cli-argument-contract.md`。
冲突时：**先改本文，再改代码**。

---

## 1. 产品定义

- **一句话描述**：N_m3u8DL-RE 的 macOS 原生图形界面，让用户在窗口里完成流媒体下载任务的创建、监控与干预。
- **目标用户**：已在命令行使用 N_m3u8DL-RE、但不愿记忆大量参数的 macOS 用户（ macOS 13+）。
- **核心问题**：内核能力强大但参数繁杂、进度以滚动文本呈现、无法并发管理多个任务、缺少失败提示。

## 2. MVP 范围（锁定）

| 优先级 | 功能 | 验收标准摘要 |
|--------|------|-------------|
| P0 | 新建任务（URL 输入 / 本地 m3u8·mpd·ism 文件选择 / 拖拽） | 三种入口均可创建任务，拖拽支持窗口主体与 Dock 图标 |
| P0 | 保存目录选择 + 文件名模板 | 目录经 NSOpenPanel 选择并持久化；模板支持 `<SaveName>` 等变量 |
| P0 | 任务队列与并发上限（默认 2） | 超出上限的任务排队，完成后自动递补 |
| P0 | 实时进度：百分比 / 速度 / ETA / 分片数 | 从内核输出实时解析，多轨道分别展示 |
| P0 | 日志面板（按级别着色、可复制、可清空） | RingBuffer 上限 5000 条，含级别过滤 |
| P0 | 暂停 / 继续 / 取消 | 暂停采用 SIGSTOP 进程组策略（ADR-003） |
| P0 | 完成后的系统通知（成功 / 失败） | 首次触发时请求授权，用户可关闭 |
| P0 | 外部依赖检测与修复指引（N_m3u8DL-RE、ffmpeg） | 缺失时展示安装命令与官方下载链接 |
| P0 | 高级设置面板（6 个分组） | 线程数 / 重试 / 限速 / 代理 / 请求头 / Cookie / 解密 Key / 输出模板 / 直播选项 |
| P0 | 深色模式（跟随系统 + 手动覆盖） | 全部颜色走语义色，零 hex 字面值（design.md §2.1） |
| P1 | 任务失败重试、历史记录「再次下载」 | 终态判定只信退出码（ADR-004） |
| P1 | 命令行预览（展示将执行的完整 argv） | 经 ShellEscaping 转义，仅供展示 |

## 3. 明确不做（Out-of-Scope）

| 不做 | 原因 |
|------|------|
| 内嵌浏览器 / 网页自动嗅探 m3u8 | 本质是浏览器插件，非 MVP |
| 账号体系 / 云同步 / 遥测 | 无服务端，违反隐私最小化 |
| 自行实现 HLS/DASH 解析 | 上游 MIT 已可用，禁止重复造轮子 |
| 跨平台（Windows / Linux） | 用户明确要 macOS 原生 |
| 跨进程重启的「断点续传」保证 | 上游未公开承诺，UI 不得暗示该能力（ADR-003） |
| 运行中动态改参（线程数 / 限速） | 上游为启动参数，运行中不可变 |
| 多语言 UI | MVP 只做简体中文；`--ui-language` 仅透传内核输出语言 |

## 4. 技术栈（锁定到版本）

| 层 | 技术 | 版本 | 锁定原因 |
|----|------|------|----------|
| 语言 | Swift（`-swift-version 5` 语言模式） | 6.1.2 | 本机实测唯一可用编译器 |
| UI | SwiftUI + AppKit 互操作 | 系统提供 | macOS 原生要求 |
| 图标 | **SF Symbols**（唯一图标方案） | 系统提供 | 满足 P0-1，禁止 emoji 作功能图标 |
| 构建 | `swiftc` + shell 脚本 | — | SwiftPM 本机崩溃（ADR-001） |
| 测试 | 自写 harness `Tests/Harness/MiniTest.swift` | — | XCTest 在 CLT SDK 缺失（ADR-006） |
| SDK | `MacOSX15.5.sdk`（探测回退 15.4 / 15.2 / 14.5） | 15.5 | 26.2 与 Swift 6.1.2 不兼容（ADR-001） |
| 部署目标 | macOS 13.0 | — | 覆盖 Intel 与 Apple Silicon |
| 第三方依赖 | **零** | — | 仅系统框架 |

## 5. 模块清单（替代 API 端点清单）

本项目为本地桌面应用，无 HTTP API。以下模块即「接口面」，签名见 `architecture.md §4`。

| 模块 | 关键类型 | 职责 |
|------|----------|------|
| Engine | `ProcessSpawner` / `ProcessHandle` / `OutputPump` / `DownloadRunner` / `ArgumentBuilder` | 进程生命周期与参数构建 |
| Parsing | `OutputNormalizer` / `RecordSplitter` / `LogLineParser` / `ProgressParser` / `OutputParser` | 内核输出 → 结构化事件（纯函数，无 I/O） |
| Services | `TaskQueue` / `TaskCoordinator` / `PauseController` / `DependencyResolver` / `NotificationService` / `LogStore` | 状态机、并发调度、编排 |
| Models | `DownloadTask` / `TaskProgress` / `TrackProgress` / `DownloadOptions` / `LogEntry` / `ExternalTool` | 值类型数据 |
| Config | `Defaults` / `AppSettings` / `SettingsStore` / `Paths` / `HistoryStore` | 持久化（UserDefaults + JSON） |
| UI | `MainWindow` / `TaskList/*` / `Composer/*` / `Settings/*` / `LogPanel/*` / `DependencyView` | 渲染与事件转发 |
| Util | `ByteFormatter` / `DurationFormatter` / `ShellEscaping` / `RingBuffer` / `VersionComparator` | 纯函数 |

## 6. 持久化数据（替代数据库表）

| 载体 | 内容 | 位置 |
|------|------|------|
| UserDefaults | `AppSettings`（并发数、目录、通知、外观、默认高级参数） | `~/Library/Preferences` |
| JSON 文件 | 任务历史元数据（不含日志正文） | `~/Library/Application Support/StreamForge/history.json` |
| 内存 RingBuffer | 每任务日志（上限 5000 条），不落盘 | 进程内 |
| 临时目录 | 内核分片与日志文件 | `~/Library/Caches/StreamForge/tmp/<taskID>/` |

## 7. 页面清单

| 页面 | 形态 | 核心组件 | 依据 |
|------|------|----------|------|
| 主窗口 | `NavigationSplitView` 三栏 | `SidebarView` + `TaskListView` + `TaskDetailView` | design.md §9.2 |
| 新建任务 | Sheet | `NewTaskSheet` | design.md §9.2 |
| 拖拽接收 | 覆盖层 | `DropZoneOverlay` | design.md §9.2 |
| 设置 | Settings 窗口 / Tab | `General/Download/Network/Decryption/Output/Live/Advanced` | architecture.md §3 |
| 依赖状态 | 主窗口内嵌 + 设置页入口 | `DependencyView` | design.md §9.2 |
| 日志面板 | 详情区下半 | `LogPanelView` + `LogRowView` | design.md §9.2 |

## 8. 设计 Token（锁定）

- **配色**：零自定义 hex。全部走 macOS 语义色（`sf.background` / `sf.label` / `sf.success` / `sf.warning` / `sf.danger` / `sf.info` / `sf.neutral`），详见 design.md §2。
- **字体**：SF Pro（界面）/ SF Mono（日志与数字），见 design.md §3。
- **图标**：SF Symbols，尺寸 16 / 20 / 24px，名称集中在 `UI/SFSymbols.swift`。
- **主题**：浅色 / 深色 / 跟随系统。
- **状态即颜色**：任务行内颜色只允许出现在**状态图标**与**进度条已完成部分**；文件名、大小、速度、ETA 一律 `label` / `labelSecondary`。

### 任务状态集合（锁定，共 8 态）

| 状态 | 语义 | 视觉 |
|------|------|------|
| 准备中 | 已入队、等待调度 | neutral |
| 下载中 | 进程运行、分片在推进 | accent（进度条）+ info（图标） |
| 暂停 | P1：已发 SIGSTOP，可恢复 | warning |
| 已停止（可重试） | P2：暂停超时 80s 自动降级，tmp 保留 | warning |
| 合并中 | 内核进入 ffmpeg merging | info |
| 完成 | 退出码 0 | success |
| 失败 | 退出码非 0 或被信号终止 | danger |
| 已取消 | 用户主动取消 | neutral |

> 「准备中」「已停止（可重试）」两态为架构评审补充项，UI 必须实现。

## 9. 验收标准（EARS 格式）

| 编号 | 功能 | 验收标准 | 优先级 |
|------|------|----------|--------|
| AC-01 | 输出解析 | While 内核输出粘连（多日志 + 多进度帧无分隔符），解析器**必须**切分出全部日志与进度帧，不得丢帧 | P0 |
| AC-02 | 输出解析 | If 进度行含 `-0.00Bps` / `-0.00%` / `--:--:--`，系统**必须**显示为占位符而非崩溃或显示负数 | P0 |
| AC-03 | 输出解析 | If 内核输出含 ANSI CSI 转义，系统**必须**剥离后再展示 | P0 |
| AC-04 | 暂停 | While 任务处于下载中，用户点击暂停，系统**必须**在 1s 内挂起内核进程组并显示「暂停」 | P0 |
| AC-05 | 暂停 | If 暂停持续超过 80s，系统**必须**自动降级为「已停止（可重试）」并保留 tmp 目录 | P0 |
| AC-06 | 暂停 | While 任务为直播类型，系统**必须**禁用暂停按钮并给出说明 | P0 |
| AC-07 | 取消 | When 用户取消任务，系统**必须**先 SIGCONT 再 SIGTERM，保证停止中的进程也能收到信号 | P0 |
| AC-08 | 终态判定 | If 进程退出码为 0 且输出文件存在，系统**必须**判定为完成；否则判定为失败 | P0 |
| AC-09 | 并发 | While 运行任务数达到并发上限，新任务**必须**排队，不得启动 | P0 |
| AC-10 | 参数构建 | If 用户取值以 `-` 开头（`-H` 的值），参数构建**必须**拒绝并报错，不得传给内核 | P0 |
| AC-11 | 参数构建 | When UI 关闭上游默认 true 的开关，系统**必须**显式输出 `=False` 形式 | P0 |
| AC-12 | 依赖 | If N_m3u8DL-RE 或 ffmpeg 缺失，系统**必须**展示安装指引并阻止任务启动 | P0 |
| AC-13 | 依赖 | If 依赖二进制存在 quarantine 属性，系统**必须**提示并提供清除命令 | P1 |
| AC-14 | 通知 | When 任务进入完成或失败终态，系统**必须**投递系统通知（用户未关闭时） | P0 |
| AC-15 | 架构门禁 | Engine / Parsing / Services / Models 源码中**禁止**出现 `import SwiftUI` | P0 |
| AC-16 | 代码组织 | 单文件**必须** ≤ 300 行；入口文件只装配 | P0 |
| AC-17 | P0 规则 | 全部源码与文档中**禁止** emoji 作功能图标；图标一律 SF Symbols | P0 |
| AC-18 | P0 规则 | 源码中**禁止**出现 `#RRGGBB` / `Color(red:green:blue:)` 字面颜色 | P0 |
| AC-19 | 幽灵轨道 | If 首帧轨道名重复输出，系统**必须**以 staleWindow=10s 剔除陈旧轨道，不得串台 | P0 |
| AC-20 | 构建 | When 执行 `Scripts/build.sh`，系统**必须**自动探测可用 SDK 并产出可启动的 `.app` | P0 |

## 10. 边界与约束

- 仅支持 macOS 13.0+，不支持 iOS / iPadOS / 跨平台。
- 内核为 Beta 版本（0.6.0，20260628 构建），输出格式可能随上游变更；解析层需容错。
- 不支持运行中修改线程数、限速等启动参数。
- 暂停时长超过内核 `--http-request-timeout`（默认 100s）可能导致在途请求失败，故设 80s 守卫（ADR-003）。
- 发布产物未签名，用户需右键「打开」绕过 Gatekeeper。

## 11. 已实测的已知坑（开发时必须规避）

| 坑 | 根因 | 规避 |
|----|------|------|
| 进度帧**零分隔符** | 内核把日志与进度写在同一缓冲，实测样本 8 个 `\n`、0 个 `\r` | 按时间戳 lookahead 切分，禁止按行解析 |
| 首帧轨道名重复 → 幽灵轨道 | 内核首帧输出两次轨道名 | staleWindow=10s 剔除 |
| 轨道名正则吞掉粘连日志 | 若正则允许 `.` `:` 开头会跨帧匹配 | 轨道名必须字母开头，排除 `.` `:` |
| 布尔参数传错整体失败 | 上游要求 `True` / `False` 字面值 | 显式输出 `=True` / `=False` |
| `WIFEXITED` / `WEXITSTATUS` 在 Swift 不可用 | Darwin 宏非函数 | 手工解码 `rawStatus`（见 architecture.md §4.1） |
| `-0.00Bps` / `--:--:--` / 字节字段缺失 / `(1)` 重试计数 | 内核未就绪或重试时的正常输出 | 全部视为合法，渲染为占位符 |
| 默认 SDK（26.2）与 Swift 6.1.2 不兼容 | CLT 版本错配 | 构建脚本强制探测 15.5 / 15.4 / 15.2 / 14.5 |
| SwiftPM `swift build` 崩溃 | llbuild 框架符号缺失 | 禁用 SwiftPM |
| macOS 无 GNU `timeout` 命令 | BSD 与 GNU 差异 | 脚本不得依赖 `timeout` |
| 系统代理拦截 127.0.0.1 | 内核默认 `--use-system-proxy` | 本地测试用 `file://` 协议 |

## 12. 端到端验证步骤

```bash
# 1. 运行测试（解析器 / 参数构建 / 暂停策略 / 格式化）
./Scripts/test.sh

# 2. 架构门禁（单文件行数、依赖方向、无 emoji）
./Scripts/check-layout.sh

# 3. 构建并打包
./Scripts/build.sh          # 产出 dist/StreamForge.app 与 .dmg

# 4. 冒烟：启动应用
open dist/StreamForge.app   # 断言：进程存活、主窗口出现

# 5. 真实下载验证（需本机已装 N_m3u8DL-RE 与 ffmpeg）
#    用 ffmpeg 生成最小 m3u8，在 GUI 中新建任务：
#    - 断言：进度从 0% 推进到 100%，速度与 ETA 有值
#    - 断言：中途暂停后继续，最终产出 mp4 且状态为「完成」
#    - 断言：取消后进程退出，状态为「已取消」

# 6. 依赖缺失验证
#    临时把 N_m3u8DL-RE 改名，重启应用 → 断言展示修复指引且禁止启动任务
```

## 13. 变更记录

| 日期 | 变更内容 | 原因 | 影响范围 |
|------|----------|------|----------|
| 2026-09-28 | 初版 Spec 建立 | 基于架构与设计产出锁定范围 | 全文 |
| 2026-09-28 | 补充「准备中」「已停止（可重试）」两态 | 架构评审提出 design.md 状态词缺失 | §8 |
