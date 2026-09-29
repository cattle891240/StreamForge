# StreamForge 设计系统与界面规范（DESIGN.md）

> 生成日期：2026-09-28 | 设计师：颜好看 | 基于：StreamForge PRD v0.1 + macOS 13 原生约束 + Folx / Downie 4 调研
> 三轴刻度：DESIGN_VARIANCE = 3 / MOTION_INTENSITY = 3 / VISUAL_DENSITY = 6
> 设计寄存器：**Product**（设计服务产品，标杆是赢得熟悉感）
> 平台轴：**macOS 原生**（遵循 Apple HIG 精要：系统控件优先、语义系统色、SF Symbols、尊重 Reduce Motion）
> 技术栈：Swift 6.1.2 + SwiftUI 原生，deployment target macOS 13.0，零第三方依赖

---

## 0. 为什么是这个方向（设计判断的三句话）

1. StreamForge 是一个**工具型外壳**：用户坐下来是为了看懂下载发生了什么、并能立刻干预。主 Surface 必须是任务列表与真实数据，不是欢迎词。
2. 本机只能命令行编译、**无法可视化调试**。因此本设计的第一原则是「系统控件优先」：每一个颜色、控件、动效都先问 SwiftUI / AppKit 是否已有标准实现。任何需要人眼反复微调的自定义绘制都被判为高风险，直接排除。
3. 参考调研结论（Folx 5、Downie 4）：两者都采用「三窗格 + 工具栏 + 列表内嵌进度条 + 右键情境菜单」的结构，Downie 把拖拽作为一等入口，Folx 把左侧过滤（全部/下载中/已完成）作为一等导航。StreamForge 取两者所长：**左侧过滤 sidebar + 中间任务列表 + 右侧详情**，拖拽同时覆盖窗口主体与 Dock 图标。

> 调研来源：Folx 中文站《管理下载列表》(https://www.folxchina.cn/faq/fx-glxzlb.html)、7labs《Folx 5》(https://cfblog.7labs.io/technology-news/mac-downloader.html)、33rd Square《Downie 4 Review》(https://33rdsquare.com/software-app/downie-4-review-the-easiest-way-to-download-online-videos-on-mac/)。
> 参考的是**信息组织方式**（三个窗格、状态过滤、列表内嵌进度、右键复现/优先级），不参考它们的视觉皮肤。macOS 13 的目标下，任何自制皮肤都不如系统语义色的适配可靠。

---

## 1. Visual Theme & Atmosphere（视觉主题与氛围）

### 关键词（4 个）
**可诊断、克制、即时、系统原生**

### 氛围描述
一个安静的批处理工作台。界面本身不抢戏，所有视觉重量交给「正在发生的事情」：速度在跳、ETA 在缩、分片状态在变、日志在滚。用户扫一眼侧栏就知道哪几个任务有问题，不需要读懂任何说明文字。

### 对标锚点
- **Activity Monitor（活动监视器）**：密集数据行 + 单列选择的确定性。
- **Xcode Organizer / Console**：日志面板的密度与等宽字体处理。
- **Shortcuts（快捷指令）**：Form 分组、Sheet 任务的收敛方式。

### 三轴刻度及行为约束

| 轴 | 值 | 在本项目中的具体行为 |
|---|---|---|
| DESIGN_VARIANCE | 3 | 可预测网格。NavigationSplitView 标准三栏 + Form 分组设置，不做非对称、不做破网格、不做自定义 Hero 区 |
| MOTION_INTENSITY | 3 | 仅有功能性动效：Sheet 升起（系统默认）、日志自动滚到底、进度条数值过渡。无页面加载编排、无装饰动画、无 bounce |
| VISUAL_DENSITY | 6 | 数据行密度略高于 macOS 默认：任务行三行式（文件名 / 进度 / 状态+指标），行高 56pt。设置面板窗口内容丰富，用 `.formStyle(.grouped)` 承载 |

---

## 2. Color Palette & Roles（色彩与角色）

### 2.1 核心决策：零自定义色板

本项目**不定义任何品牌 hex 色值**。全部颜色通过 macOS 语义色表达（`NSColor` 语义成员 + SwiftUI 语义样式），由此自动获得：

- 深色模式适配（用户切换即生效，代码零分支）
- 强调色跟随用户在「系统设置 - 外观 - 强调色」的选择
- 用户在辅助功能中开启「增强对比度」时自动加深，无需额外代码
- macOS 14+ 的新系统外观自动继承

**The Zero-Hex Rule（零色值规则）**：Swift 源码中出现任何 `#RRGGBB`、`Color(red:green:blue:)`、`NSColor(calibratedRed:...)` 即为设计违约。唯一允许的字面颜色用途是系统提供的 `Color.white` / `Color.black`，且本项目无此需求，实际使用为零。

唯一例外通道：若未来确需品牌色，必须作为**资产颜色**在 `Assets.xcassets` 中建 Color Set 并配 Any/Dark 两档，不得在代码中写字面色值。

### 2.2 A1 - Identity 层（容器与文本）

| Token | SwiftUI 表达式 | AppKit 依据 | 参考渲染值（浅/深，仅供审稿估算，**不进代码**） |
|---|---|---|---|
| `sf.background` | `Color(nsColor: .windowBackgroundColor)` | `.windowBackgroundColor` | `#FFFFFF` / `#1E1E1E` |
| `sf.surface` | `Color(nsColor: .controlBackgroundColor)` | `.controlBackgroundColor` | `#FFFFFF` / `#2C2C2E` |
| `sf.surfaceInset` | `Color(nsColor: .textBackgroundColor)` | `.textBackgroundColor` | `#FFFFFF` / `#1E1E1E` |
| `sf.label` | `Color.primary` | `.labelColor` | `#000000` / `#FFFFFF` |
| `sf.labelSecondary` | `Color.secondary` | `.secondaryLabelColor` | 约 `#6E6E73` / 约 `#98989D` |
| `sf.border` | `Color(nsColor: .separatorColor)` | `.separatorColor` | 半透明 20% 分隔线 |
| `sf.accent` | `Color.accentColor` | `.controlAccentColor` | 用户设定值（默认 `#007AFF` / `#0A84FF`） |

### 2.3 A2 - Semantic 层（状态与结果）

| Token | SwiftUI 表达式 | 用途 |
|---|---|---|
| `sf.success` | `Color(nsColor: .systemGreen)` | 下载完成、依赖就绪 |
| `sf.warning` | `Color(nsColor: .systemOrange)` | 依赖缺失、重试中、速度异常偏低 |
| `sf.danger` | `Color(nsColor: .systemRed)` | 任务失败、破坏性操作（移除并删除文件） |
| `sf.info` | `Color(nsColor: .systemBlue)` | 信息提示、链接、非阻塞说明 |
| `sf.neutral` | `Color(nsColor: .systemGray)` | 排队中、已取消、未知态 |

> **重要**：`Color.accentColor` 与 `systemBlue` 在默认配置下渲染结果接近，但语义不同。只有「选中态 + 主操作按钮」用 `accentColor`；所有**状态指示**一律用五个语义色，避免用户把「蓝色 = 系统强调」误读为「蓝色 = 下载中」。

### 2.4 B - Slot 层（插槽别名）

| Token | SwiftUI 表达式 | 用途 |
|---|---|---|
| `sf.labelTertiary` | `Color(nsColor: .tertiaryLabelColor)` | 仅用于禁用态文字与纯装饰；**承载信息的文字禁止使用**（见 §8.1） |
| `sf.fillQuaternary` | `Color(nsColor: .quaternaryLabelColor)` | 拖拽悬停区底色、低强度 hover 底色 |
| `sf.selectedText` | `Color(nsColor: .selectedTextColor)` | 选中行内的文字（不由列表自动处理时显式指定） |
| `sf.selection` | 由 `List(selection:)` 自动渲染 | 行选中底色，**不要手动画** |

### 2.5 每屏强调色预算

**The State-Is-Color Rule（状态即颜色规则）**

- `Color.accentColor` 在主窗口**可见计数 ≤ 2**：通常恰好是「新建任务」主按钮 + 当前选中任务行的自动高亮。
- 工具栏按钮一律 `.borderless` + `foregroundStyle(.secondary)`，只有「新建任务」使用 `.borderedProminent`。
- 任务列表中的颜色只允许出现在两处：**状态图标** 与 **进度条已完成部分**。文件名、大小、速度、ETA 一律 `label` / `labelSecondary`。
- 第二列的详情区允许出现一次 `accentColor`（如「重新下载」按钮），不叠加第三次。

---

## 3. Typography（排版）

### 3.1 字体栈

本项目使用系统字体，**不引入任何自定义字体文件**（零第三方依赖约束的直接推论，也是 macOS 原生的正确做法）。SF Pro 承载全部界面文本，SF Mono 承载日志与数字。

| Token | SwiftUI 表达式 | 用途 |
|---|---|---|
| `sf.fontBody` | `.font(.body)` | 任务文件名、表单标签、按钮文字 |
| `sf.fontHeadline` | `.font(.headline)` | 详情页 heading、侧栏分组标题 |
| `sf.fontSubheadline` | `.font(.subheadline)` | 详情摘要值（路径、命令行） |
| `sf.fontFootnote` | `.font(.footnote)` | 任务行元数据（速度、ETA、分片数） |
| `sf.fontCaption` | `.font(.caption)` | 辅助说明、日志时间戳（下限，**禁止更小的 caption2**） |
| `sf.fontMono` | `.font(.system(.caption, design: .monospaced))` | 日志正文、原始命令行、版本号 |
| `sf.fontMonoDigit` | `.font(.system(.footnote, design: .monospaced)).monospacedDigit()` | 速度、百分比、ETA 等跳动数字 |

### 3.2 平台校准（重要，别套 iOS 数值）

macOS 上 SwiftUI 系统文字样式的实际 pt 值**小于 iOS**（`.body` ≈ 13pt，`.footnote` ≈ 11pt，`.caption` ≈ 10pt）。

- 这是**正确的平台行为**，禁止为了「看起来大一点」把正文改成 15/16pt 手工数值，那会让界面立刻显得外来。
- 任务行的文件名用 `.body` + `.semibold`（13pt），元数据用 `.footnote`（11pt），这条组合是 Activity Monitor 与 Console 的同款处理方法。
- 使用语义样式而非硬编码 size，才能随「系统设置 - 辅助功能 - 显示 - 文字大小」自动缩放。

### 3.3 字重三级制

| 级别 | SwiftUI | 用途 |
|---|---|---|
| Read | `.regular` | 正文、日志、路径 |
| Emphasize | `.medium` / `.semibold` | 任务文件名、Form 标签、危险操作按钮 |
| Announce | `.bold` | 仅用于详情页大标题与空状态标题 |

### 3.4 字距与数字

- 数字类（速度、百分比、ETA）必须 `.monospacedDigit()`，否则数字跳动时行会产生横向颤动。
- 全大写标签（如 KEY、COOKIE 这类术语）加 letter-spacing：`Text("KEY").tracking(0.6)`（约 0.06em，macOS 上微量即可）。
- 日志区行高额外补偿：`.lineSpacing(2)`，等宽字体的行距需要比界面文本宽一格。

---

## 4. Components（组件规范）

### 4.1 按钮

| 变体 | SwiftUI 表达式 | 使用场景 |
|---|---|---|
| Prominent | `.buttonStyle(.borderedProminent)` | 每屏唯一主操作：新建任务 Sheet 的「开始下载」、依赖卡片「安装」 |
| Bordered | `.buttonStyle(.bordered)` | 次级操作：暂停、继续、重试、清除日志 |
| Borderless | `.buttonStyle(.borderless)` | 工具栏图标按钮、表格内联操作 |
| Destructive | `.buttonStyle(.bordered)` + `.buttonStyle` 之上 `role: .destructive`（macOS 13 需 `Button(role: .destructive)` + `.foregroundStyle(.red)`） | 移除任务并删除已下载文件（需二次确认 Alert） |
| Link | `.buttonStyle(.link)` | 打开文档、打开项目主页 |

**尺寸规范**

| 位置 | 最小点击区 | 图标尺寸 |
|---|---|---|
| 工具栏 | 32 × 32 pt | SF Symbol 16pt |
| 行内 / 表格内 | 28 × 28 pt | SF Symbol 14pt |
| 表单 / Sheet 底部 | 高度 24pt（系统默认 bordered），宽度随 `.frame(minWidth: 88)` | 无图标或 14pt |
| 侧栏行 | 行高 28pt | SF Symbol 14pt |

**状态矩阵（9 态）**

| 状态 | 处理 |
|---|---|
| Default | 见上表变体 |
| Hover | 系统自动（bordered 由 AppKit 提供）；borderless 追加 `.foregroundStyle(.primary)` |
| Focus / Focus-visible | 系统自动（macOS 键盘导航焦点环）；**禁止 `.focusable(false)` 之外的任何 focus 环抑制** |
| Active | 系统自动按压态 |
| Disabled | `.disabled(true)` 由系统降低不透明度；禁止手写 opacity |
| Loading | 「安装依赖」「开始下载」在执行中时：标题换为进行中文案（`正在解析...`）+ 同行 `ProgressView().controlSize(.small)`，按钮同时 disabled 防双提交 |
| Error | 按钮不承载错误态；错误由相邻 Text 或 Form 内提示承担（见 §4.3） |
| Empty | 空列表时的引导按钮（见 §5.4 空状态） |
| Success | 完成后 1.5s 内联确认（`已添加 1 个任务`），然后自动消失，不用 Alert 打断流程 |

### 4.2 输入控件

- 单行文本：`TextField` + `.textFieldStyle(.roundedBorder)` + `.controlSize(.large)`（macOS 上 large 提供标准 22pt 高度）。
- 多行文本（日志浏览 / 批量 URL）：`TextEditor` + `.font(.system(.caption, design: .monospaced))` + 外层 `.border(sf.border)` 圆角 4pt。
- 数值（线程数、重试次数、限速）：`Stepper` 优先，连续量用 `Slider` + 右侧数值标签。禁止纯 TextField 让用户猜单位，必须在标签括号中写明单位，如 `线程数（每个文件）`。
- 开关（下载完成后通知、自动重试）：`Toggle` + `.toggleStyle(.switch)`（macOS 13 默认即 switch）。
- 下拉（输出格式、日志级别、并发策略）：`Picker` + `.menu` / `.radioGroup`（组内 ≤ 3 项时用 radio 组更清晰）。
- 目录选择：`Button` 触发 `NSOpenPanel`（`canChooseDirectories = true`，`canChooseFiles = false`）。**不要用 `.fileImporter` 选目录**（不支持目录）。
- 文件选择：`Button` 触发 `NSOpenPanel`（allowedContentTypes 含 `.m3u8`, `.mpd`, 及公共类型 `.text`）。

**输入校验**：错误在字段**正下方**出现，11pt `.systemRed` 文案 + 前置 `exclamationmark.triangle.fill` 14pt。错误文案必须说清「哪里错 + 怎么修」（见 §9.3 文案库）。

### 4.3 容器与卡片

- 列表容器：`List` + `.listStyle(.inset(alternatesRowBackgrounds: true))`。
- 详情区摘要：不用卡片套壳，用 `Form` + `.formStyle(.grouped)` 承载，分组标题写在 `Section(header:)`。
- 依赖状态卡片：`.background(sf.surface)` + `.clipShape(RoundedRectangle(cornerRadius: 8))` + `.overlay(RoundedRectangle(cornerRadius: 8).stroke(sf.border))`。**禁止圆角 ≥ 12pt**（这是 AI 过度圆滑的典型），**禁止给卡片同时加边框和大模糊阴影**（幽灵卡片模式）。
- 拖拽悬停区：`RoundedRectangle(cornerRadius: 12).strokeBorder(sf.border, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))` + 底色 `sf.fillQuaternary` 的 40% 透明度，仅在 `isTargeted` 为真时出现。

### 4.4 进度呈现（本项目最关键的组件）

同一套视觉语言在两处复用：**任务行内的紧凑形态** 与 **详情区的大尺寸形态**。

| 元素 | 紧凑（任务行） | 展开（详情区） |
|---|---|---|
| 进度条 | `ProgressView(value: pct).progressViewStyle(.linear)`，高度 4pt，宽度撑满内容区 | 同上但高度 6pt |
| 未确定进度 | `.controlSize(.small)` 的不确定 ProgressView（`parse / ffprobe` 阶段），因为它原生支持 indeterminate | 同左 |
| 百分比 | 行内右侧 `.monospacedDigit()` 11pt | 进度条上方 13pt semibold |
| 已下载 / 总大小 | 行内元数据区 | 进度条下方 11pt secondary |
| 速度 | 元数据区首位（`8.3 MB/s`） | 摘要区 `速度` 值 |
| ETA | 元数据区第二位（`剩余 2:14`） | 摘要区 `预计剩余` 值 |
| 分片计数 | 元数据区末位（`分片 84/312`） | 「分片」标签页的 Table |

**填色规则**：进度条 `.tint(...)` 跟随任务状态。不要给下载中用 `sf.info`（`systemBlue`），它会与系统强调色混淆，让人分不清「蓝色是品牌色还是在跑」。最终规则：

- 下载中：`.tint(sf.accent)` —— 这是「正在推进」的唯一显式色彩信号，与缓慢/暂停形成对照。
- 合并中：`.tint(sf.warning)`（`systemOrange`），这是一个短时的过渡阶段，需要用户留意但不报警。
- 已完成：不显示进度条，改为一行完成摘要 `已完成 · 用时 4:12 · 平均 8.3 MB/s`。已完成状态不使用绿色填满的进度条（那会制造仍在推进的错觉）。
- 失败 / 已取消：进度条保留到最后已知百分比，`.tint(sf.neutral)`（灰）并整体降透明度至 60%，视觉上「冻结」。

### 4.5 徽标 / 标签（Badge）

SwiftUI macOS 13 的 `.badge()` 修饰符在 `List` 行与 `TabView` 上可用。任务**状态不用 Badge**，用「图标 + 文字」组合（见附录 C.1），因为 Badge 在 macOS 列表里语义偏「计数」。计数类徽标仅用于侧栏（`下载中 3`），用 `.badge(3)` 原生渲染。

---

## 5. Layout & Spacing（布局与间距）

### 5.1 间距网格（4pt 基准，常用 8pt 步进）

允许值：`4 / 8 / 12 / 16 / 20 / 24 / 32 / 48`。禁止 5、7、13、15、22、30 等非标值。

| Token | 值 | 用途 |
|---|---|---|
| `sf.space1` | 4pt | 图标与紧邻文字 |
| `sf.space2` | 8pt | 表单行内控件间距、控件与错误文案 |
| `sf.space3` | 12pt | 任务行内部行间距 |
| `sf.space4` | 16pt | 卡片 / Form section 内边距 |
| `sf.space5` | 20pt | 工具栏与内容区间隔 |
| `sf.space6` | 24pt | 详情区大块间距 |
| `sf.space8` | 32pt | 空状态上下留白 |
| `sf.space12` | 48pt | Sheet 顶部与底部大留白 |

### 5.2 圆角（上限 12pt）

| Token | 值 | 用途 |
|---|---|---|
| `sf.radiusSm` | 4pt | 小徽标、代码 / 命令行背景块 |
| `sf.radiusMd` | 8pt | 卡片、按钮、依赖卡 |
| `sf.radiusLg` | 12pt | 拖拽悬停虚线框（上限） |

### 5.3 窗口尺寸（主窗口 NavigationSplitView）

| 项 | 值 |
|---|---|
| 默认 frame | 1040 × 680 |
| 最小 frame | 820 × 520 |
| Sidebar | 宽 200（可拖 180–280），`.navigationSplitViewColumnWidth(min: 180, ideal: 200)` |
| Detail | `.navigationSplitViewColumnWidth(min: 420, ideal: 560)` |
| 侧栏折叠 | 用户可折叠至 0，不提供自定义折叠按钮（系统自动） |

### 5.4 空状态（Populated / Empty / Loading / Error / Edge 五态）

任务列表空状态必须包含 4 项：**现在这里会有什么 + 为什么有用 + 怎么开始 + 一个视觉锚**。

```
                [ arrow.down.doc 40pt, secondary ]

                还没有下载任务

    把 .m3u8 链接或本地文件拖到这里，或按 Command-N 新建

            [ 新建任务 ]     [ 从剪贴板导入 ]
```

从剪贴板导入的按钮仅在剪贴板中有 `http(s)://` 文本时 enabled，否则 disabled 并在旁边写 `剪贴板中没有链接`。这是一个只有真实工作流才有的细节。

依赖未完成时的空状态变体：中间区域直接替换为「依赖状态视图」（§6.3），列表区保留但 disabled 并覆盖一层说明 —— 不直接替换主窗口，避免用户以为应用还没启动。

---

## 6. Depth & Elevation（深度与层级）

**Hairline First 原则**：macOS 界面的层级靠 1pt 分隔线与底色递进表达，不靠阴影。

| 层级 | 表达 | 使用场景 |
|---|---|---|
| flat | 无边框无阴影，纯背景色 | 主背景 `windowBackgroundColor` |
| inset surface | `controlBackgroundColor` + 无边框 | Form 分组背景、Task 详情区 |
| separated | 1pt `separatorColor` 分隔线 | 任务行之间、日志区与输入区之间、侧栏与列表之间 |
| raised | 系统提供 | Sheet / Alert /<｜hy_place▁holder▁no▁813｜> 面板，**全部用系统容器，不自制阴影面板** |

**明令禁止**：
- 给卡片同时加 `1px stroke` + `blur ≥ 16px` 的 box-shadow（AI 幽灵卡片模式）。
- 任何形式的 `background(.ultraThinMaterial)` 装饰性毛玻璃。仅 macOS 原生工具栏 / sidebar 自带 vibrancy（系统自动提供），不得手动追加 `.background(.thinMaterial)`。
- `border-left` 宽度 > 1px 的彩色强调条（AI 常见 stripes）。

---

## 7. Do's & Don'ts（设计守则）

### 允许

1. 用系统标准控件（List / Form / Stepper / Toggle / Picker / ProgressView / NavigationSplitView / Toolbar / Sheet / Alert）。
2. 用 SF Symbols，并在旁边写中文文字标签，**除工具栏与 24pt 独立图标外不允许图标单独出现**。
3. 用 NSColor / SwiftUI 语义色，让系统替你处理深色模式与增强对比度。
4. 为一等召回失败信息：错误必须指明主体是谁（N_m3u8DL-RE / ffmpeg / 网络 / 磁盘 / 权限）。
5. 列表行内直接放进度条与实时数字，用户不选中也能读。
6. 右键（contextMenu）复现核心操作：暂停 / 继续 / 重试 / 复制 URL / 在访达中显示 / 移除。macOS 是右键重度的一等工具平台。
7. 键盘快捷键全覆盖（见 §9.4）。

### 禁止

1. 任何 emoji 作为功能图标（P0-1）。唯一例外：用户自己的文件名（UGC）按原样显示，应用不做替换。
2. 紫色到粉色 / Indigo 到 Pink 的任意渐变，以及「渐变 + 发光边框 + 毛玻璃」组合（P0-2）。
3. 硬编码颜色值（P0-4，见 The Zero-Hex Rule）。
4. 「欢迎使用 StreamForge」这类空洞欢迎词（P0-5）。所有文案必须是具体信息，`欢迎` 一词在本项目中零出现。
5. 千篇一律的 Hero 区（大标题 + 副标题 + 居中 CTA + 抽象 3D 图形）。主窗口的主体就是任务列表。
6. 虚构数字（`10,000+ 用户`、`99.9%`）。速度/ETA/大小无数据时显示 `—`，禁止占位为 0 或编造值。
7. 过度圆角（卡片 ≥ 12pt），以及彩色左边框强调条。
8. 每 section 都有的小型大写 tracking 标签（`快速开始`、`核心能力` 这种语气）以及编号 section 标记（`01 · 下载`）。macOS 原生界面的分组标题就是普通居中加粗文本。
9. 超出 macOS 13 可用范围的 SF Symbols（SF Symbols 5+，`macOS 14` 起步），否则在 macOS 13 上渲染为空白。

### Named Rules（给实现 Agent 执行的短句）

1. **The System-First Rule**：先查系统控件；有标准实现就不要自己写个近似品。
2. **The Zero-Hex Rule**：源码不出现任何字面色值。
3. **The Symbol-Only Rule**：图标一律 SF Symbols，禁止 emoji、禁止自绘 PNG 图标。
4. **The State-Is-Color Rule**：颜色只用于「推进中的进度」与「状态指示」，且两者配色不重叠混淆。
5. **The Real-Numbers Rule**：无数据显示 `—`，禁止占位数字。
6. **The Who-Failed Rule**：错误文案必须点名失败的主体 + 一个可点击的下一步。
7. **The One-Window-Sheet Rule**：自包含任务走 Sheet，全局偏好走 Settings 窗口，主窗口不产生二级导航栈。

---

## 8. Responsive & Accessibility（响应式与无障碍）

macOS 窗口是可自由缩放的，因此「响应式」在本文档中之含义是**宽度断点内的布局保持**。

### 8.1 对比度与文本层级：别把信息放进过淡的色阶

| 层级 | Token | 对比度参考 | 允许承载的内容 |
|---|---|---|---|
| 一级 | `sf.label` | 高（深/浅均 > 10:1） | 文件名、表单值、日志正文 |
| 二级 | `sf.labelSecondary` | 中（约 6:1 ~ 7:1 量级） | 速度、ETA、路径、时间戳 |
| 三级 | `sf.labelTertiary` | 低（约 3:1 ~ 4:1 量级） | **仅**禁用态与纯装饰；承载信息的文字禁止使用 |

> 上表为 macOS 13 Ventura 默认主题的估算区间，实际值随系统版本变化。实现完成后用 **Accessibility Inspector 的 Contrast 检查**逐项复核（针对浅色与深色两套）。**不应在编码阶段为了「通过检查」而手动加深淡色阶**，那会破坏系统语义色的自动适配。

### 8.2 深色模式

- 零 `colorScheme` 分支判断。若确需分支（推荐旁路：仅在自绘 Canvas / `NSView` bridge 层），用 `@Environment(\.colorScheme)` 读取，不要 `UserDefaults` 手抄。
- 日志区在深色下，等宽字体的视觉重量会下降一档：深色模式下额外给日志 `.fontWeight(.regular)` 并保持 `.lineSpacing(2)`，可抵消这一感知损失（暗底亮字补偿三轴中的字重轴）。
- 命令行预览块在深色模式的底色用 `controlBackgroundColor` 在两主题下区分层次，不要用 `NSColor.black` 硬规定。

### 8.3 Dynamic Type 与 Scaling

- 全部文本用 SwiftUI 语义样式（`.body` / `.footnote` / `.caption`），随系统「文字大小」设置缩放。**禁止 `.system(size:)` 硬编码**，除非是用于 `.monospacedDigit` 的 `.system(_:design:)` 构造器（保留 design 参数即可保留缩放能力）。
- 任务行使用 `.frame(minHeight: 56)` 而非固定行高，文字放大时纵向增长而不是被裁切。
- 文件名一律 `.lineLimit(1).truncationMode(.middle)`，并给父容器 `minWidth: 0`（防止 flex 容器撑破）。
- 宽度 < 640 时（用户把窗口拖窄），NavigationSplitView 自动收起 sidebar（macOS 系统行为），此时底部 Toolbar 补充一个「过滤」菜单：`Menu` + 状态 Picker 列表，替代消失的 sidebar。

### 8.4 VoiceOver / 无障碍标签表

| 元素 | accessibilityLabel | accessibilityValue | 备注 |
|---|---|---|---|
| 任务行（整体） | `{文件名}` | `{状态}，已完成 {百分比}%，速度 {速度}，剩余 {ETA}` | 整体作为一个 accessibility 元素（`.accessibilityElement(children: .combine)`） |
| 状态图标 | 不单独暴露 | — | `.accessibilityHidden(true)`，信息已合并到行级 value |
| 进度条 | — | — | `.accessibilityHidden(true)`，同上，避免重复播报 |
| 暂停 / 继续 按钮 | 动态切换 `暂停 {文件名}` / `继续 {文件名}` | — | 状态变化时 label 必须跟着变，这是 macOS power user 的常见抱怨点 |
| 移除按钮 | `移除 {文件名}` | — | 命名破坏：`移除已完成的任务` 这类具体动词优于 `删除所选` |
| 依赖状态图标 | `未安装 N_m3u8DL-RE` / `已安装 ffmpeg {版本}` | — | 图标不能单独传意，必须有文字 label |
| 安装按钮 | `安装 N_m3u8DL-RE` | — | 按钮标签必须以具体动词开头并带上作用对象，避免只有「确定」 |
| 日志行 | 不逐行暴露 | — | 日志面板整体 label 为 `下载日志`；用户用 VoiceOver rotor 进入后可逐行读取 |
| 文件名模板字段 | `输出文件名模板` | 当前模板字符串 | 必须配 `.accessibilityHint("可用占位符：%title、%id、%date")` |

### 8.5 Reduce Motion

- 日志自动滚动在 `@Environment(\.accessibilityReduceMotion)` 为真时使用瞬时赋值（`.scrollTo(id, anchor: .bottom)` 不带 animation）。
- 任务行的数值过渡（可选 `.contentTransition(.numericText())`，macOS 13 可用）同上，reduced motion 时关闭。
- 依赖检测结果由「检测中」切换为「就绪」时，只切换图标与文案，不加展开动画（≤150ms 或 0）。完成感来自文案本身，不靠时长编排。

### 8.6 五态覆盖清单（按模块）

| 模块 | Loading | Empty | Error | Populated | Edge |
|---|---|---|---|---|---|
| 任务列表 | 首次启动时 3 行 `ProgressView` 占位 | §5.4 空状态 | 依赖缺失横幅覆盖 | 三行式数据行 | 文件名过长中间截断；任务数 > 200 用 `LazyVStack`；全部完成时不清除历史 |
| 详情区 | 摘要区 `—` 占位 | `未选择任务` + 提示选中左侧任务 | 该任务失败时的具体错误卡 | 摘要 + 分片 Table + 日志 | 日志 > 5000 行时截断到最近 2000 行并顶部提示 |
| 依赖状态 | 检测中 ProgressView + `正在检测...` | 无此态 | 缺失卡（§6.3） | 就绪卡（版本 + 路径） | 版本低于要求时的「版本过低」卡（非「缺失」） |
| 新建任务 Sheet | 「开始下载」-> 解析中 | 字段为空时的 disabled 主按钮 | 字段下方具体错误 | 正常表单 | URL 含空格自动 trim；多行粘贴 > 1 条时切换为「批量任务 (N 条)」 |
| 日志面板 | 追随滚动 | `暂无日志输出` | 不单独立态 | 等宽滚动文本 | 非法 UTF-8 字节替换为 `#`，保留行尾；日志 > 5000 行时截断到最近 2000 行 |

---

## 9. Agent Implementation Guide（实现指南）

### 9.1 Token 落地方式（Swift 代码片段，直接可用）

```swift
// Sources/StreamForge/Design/SFDesignTokens.swift
// The Zero-Hex Rule: 本文件是唯一的颜色真相源，且只允许引用系统语义色。

import SwiftUI
import AppKit

public enum SFColor {
    // A1 Identity
    public static let background: Color = Color(nsColor: .windowBackgroundColor)
    public static let surface: Color = Color(nsColor: .controlBackgroundColor)
    public static let surfaceInset: Color = Color(nsColor: .textBackgroundColor)
    public static let label: Color = .primary
    public static let labelSecondary: Color = .secondary
    public static let labelTertiary: Color = Color(nsColor: .tertiaryLabelColor)
    public static let border: Color = Color(nsColor: .separatorColor)
    public static let accent: Color = .accentColor

    // A2 Semantic (状态专用)
    public static let success: Color = Color(nsColor: .systemGreen)
    public static let warning: Color = Color(nsColor: .systemOrange)
    public static let danger: Color = Color(nsColor: .systemRed)
    public static let info: Color = Color(nsColor: .systemBlue)
    public static let neutral: Color = Color(nsColor: .systemGray)

    // B-slot
    public static let fillQuaternary: Color = Color(nsColor: .quaternaryLabelColor)
}

public enum SFSpace {
    public static let s1: CGFloat = 4
    public static let s2: CGFloat = 8
    public static let s3: CGFloat = 12
    public static let s4: CGFloat = 16
    public static let s5: CGFloat = 20
    public static let s6: CGFloat = 24
    public static let s8: CGFloat = 32
    public static let s12: CGFloat = 48
}

public enum SFRadius {
    public static let sm: CGFloat = 4    // 徽标 / 代码块
    public static let md: CGFloat = 8    // 卡片 / 按钮（上限）
    public static let lg: CGFloat = 12   // 拖拽虚线框（全项目最大圆角）
}

public enum SFSize {
    public static let toolbarHit: CGFloat = 32
    public static let inlineHit: CGFloat = 28
    public static let taskRowMinHeight: CGFloat = 56
    public static let windowMinWidth: CGFloat = 820
    public static let windowMinHeight: CGFloat = 520
}

public enum SFMotion {
    public static let base: Double = 0.15   // 150ms 收敛值
    public static let sheet: Double = 0.25
}
```

> 注意：macOS 13 上 `Color(nsColor:)` 已可用，Swift 6 strict concurrency 下 `NSColor` 非 Sendable，上述 `static let` 在首次访问时创建。若编译器报不可 Sendable，改为 `public static var background: Color { Color(nsColor: .windowBackgroundColor) }`（计算属性版本），语义不变。

### 9.2 视图组件清单（建议文件与命名）

| 文件 | 职责 | 关键 API（macOS 13 可用，已核） |
|---|---|---|
| `MainWindow.swift` | `NavigationSplitView` 三窗格 + `.toolbar` | `NavigationSplitView`, `.navigationSplitViewColumnWidth` |
| `SidebarView.swift` | 状态过滤 + 总量计数 | `List(selection:)`, `.badge()` |
| `TaskListView.swift` | 任务行列表（Lazy） | `List`, `.listStyle(.inset(alternatesRowBackgrounds: true))` |
| `TaskRowView.swift` | 三行式任务行 | `VStack(alignment: .leading, spacing: SFSpace.s1)` |
| `TaskDetailView.swift` | 摘要 + 分片 + 日志（分段切换） | `Form`, `.formStyle(.grouped)`, `Table` |
| `LogPanelView.swift` | 等宽滚动日志 | `ScrollViewReader`, `.font(.system(.caption, design: .monospaced))` |
| `NewTaskSheet.swift` | 新建任务 Sheet | `.sheet`, `.formStyle(.grouped)`, `@FocusState` |
| `SettingsView.swift` | 六分组偏好 | `Settings` scene（macOS 13 原生 Settings 窗口）, `TabView` 或 sidebar-less `Form` |
| `DependencyView.swift` | 依赖状态视图 | `ProgressView`, `NSWorkspace.open` |
| `DropZoneOverlay.swift` | 拖拽悬停层 | `.onDrop(of: [.fileURL, .url, .plainText], isTargeted:)` |

### 9.3 文案库（简体中文，全部可直接落地）

**状态词（统一、不混用）**：排队中 / 下载中 / 已暂停 / 合并中 / 已完成 / 失败 / 已取消

**错误信息（The Who-Failed Rule）**

| 场景 | 文案 | 行动按钮 |
|---|---|---|
| 下载器缺失 | `未找到 N_m3u8DL-RE。StreamForge 需要它来分析 m3u8 清单。` | `安装`（打开 releases 页）/ `手动指定路径` |
| ffmpeg 缺失 | `未找到 ffmpeg。合并音视频需要它，缺失时只下载分片不合并。` | `安装`（打开 brew.sh）/ `复制安装命令` |
| 版本过低 | `检测到 N_m3u8DL-RE {版本}，需要 0.2.1 或更高。` | `更新` |
| HTTP 403 | `请求被拒绝（403）。常见于缺少 Referer 或 Cookie 过期。` | `打开高级设置` |
| Key 无效 | `解密失败：提供的 Key 无法解开这个分片的加密。请检查是否为十六进制格式。` | `修改 Key` |
| 磁盘写满 | `保存目录不可写或空间不足：{路径}。` | `更换目录` |
| 代理失败 | `无法通过代理连接：{代理地址}。检查代理是否已启动。` | `关闭代理重试` |

**空状态与提示**

- 空任务列表：`还没有下载任务` / `把 .m3u8 链接或本地文件拖到这里，或按 Command-N 新建。`
- 详情未选：`未选择任务` / `在左侧选中一个任务，查看分片进度与日志。`
- 依赖检测中：`正在检测命令行工具...`
- 剪贴板无链接：`剪贴板中没有 http 链接。`

**完成通知**（`UNUserNotificationCenter`）

- 标题：`下载完成` / 副标题：`{文件名}` / 正文：`大小 {size}，用时 {duration}。`
- 多条队列完成时合并为一条：`{N} 个任务已完成`，禁止 N 条通知刷屏。

**禁止出现的文案**：欢迎使用、轻松管理、极致体验、一站式、赋能、无缝（及 §7 禁止 8 的同族套话）。

### 9.4 键盘快捷键

| 快捷键 | 动作 |
|---|---|
| `Cmd-N` | 新建任务 |
| `Cmd-,` | 打开设置（系统默认） |
| `Space` | 暂停 / 继续选中任务 |
| `Cmd-Backspace` | 移除选中任务（文件保留） |
| `Cmd-R` | 重新下载（重置已下载分片） |
| `Cmd-Shift-G` | 在访达中显示输出文件 |
| `Cmd-F` | 进入列表搜索（`.searchable` 自动提供） |
| `Cmd-C`（列表聚焦时） | 复制选中任务的原始 URL |

### 9.5 已知坑（实现时必须绕开）

1. **旋转 spinner 在 SwiftUI macOS 13 的 `List` 行内会被裁切**：给 ProgressView 加 `.controlSize(.small)` 并确认行 frame 足够，或改用状态图标静态表达。
2. **`.fileImporter` 不支持选目录**：必须退回 `NSOpenPanel`（见 §4.2）。
3. **SF Symbols 版本错位**：macOS 13 运行时绑定 SF Symbols 4。若使用了 SF Symbols 5+ 的符号，编译可通过、运行时显示空白框。交付前须逐个符号在 macOS 13 可运行的 SF Symbols 应用中确认（或用 macOS 13 环境实机验证）。
4. **`ProgressView(value:, total:)` 的 `value/total` 为 0 时会 NaN 崩溃前后**: total 未知时（解析器还没返回总大小）传入 `-1` 或用 `.indeterminate` 形态，禁止 `value/0`。
5. **日志高频刷新导致界面卡顿**：日志追加必须批量合并（如每 200ms 刷一次 / 累积 50 行再 append），禁止逐行 `@Published` 触发。`AsyncStream` + `.throttle` 或定时器合并。
6. **`Color(nsColor:)` 在 macOS 14 起的部分构造签名变化**：若后续抬升部署目标，统一在本文件改一处。
7. **Drawer / MenuBarExtra 为 macOS 13 新增 API**：若做菜单栏，用 `MenuBarExtra` 且必须提供 fallback（关闭菜单栏图标仍可用主窗口），并在 macOS 13 上实测。
8. **任务中的终端输出可能含控制字符（ANSI 色彩码）**：渲染前必须清洗（`\u{1B}\\[[0-9;]*m`），否则日志区出现乱码方块。

---

## 附录 A：窗口与页面结构

### A.1 主窗口（NavigationSplitView）

```
┌────────────────────────────────────────────────────────────────────────┐
│ 工具栏: [+] [开始] [暂停] [停止] | [依赖状态 ▾]     [搜索]      [设置]   │
├──────────────┬─────────────────────────────────────────────────────────┤
│ SIDEBAR      │ TASK LIST                        │ DETAIL               │
│              │                                   │                      │
│ 全部      12 │ ┌─────────────────────────────┐  │  剧集.S01E03         │
│ 下载中     3 │ │ 剧集.S01E03      720p  1.2GB│  │  [已完成徽标]        │
│ 已暂停     1 │ │ ████████████░░░░░░░  62%     │  │  ───────────────    │
│ 等待中     2 │ │ ● 下载中 8.3MB/s 剩2:14 分片84/312│  │  概览 | 分片 | 日志 │
│ 合并中     0 │ └─────────────────────────────┘  │                      │
│ ───────────  │ ┌─────────────────────────────┐  │  源 / 路径 / 线程    │
│ 已完成     5 │ │ 第二集搬运版    480p  640MB │  │  输出文件名模板       │
│ 失败       1 │ │ ██████░░░░░░░░░░░  34%       │  │  已下载 / 总大小     │
│              │ │ ● 已暂停                     │  │  速度 / 预计剩余     │
│              │ └─────────────────────────────┘  │                      │
│              │ ┌─────────────────────────────┐  │  ───────────────    │
│              │ │ live:stream-9a   直播  --    │  │  [暂停] [停止]      │
│              │ │ ◌ 排队中                     │  │  [重试] [访达显示]  │
│              │ └─────────────────────────────┘  │                      │
└──────────────┴───────────────────────────────────┴──────────────────────┘
```

**侧栏**：7 项单级列表（无嵌套），`.listStyle(.sidebar)`。计数用 `.badge()` 原生。选中态系统自动。**不含**「精美」分组或「高级」二级。

**工具栏**（`.toolbar`，全部 borderless）

| 顺序 | SF Symbol | 标签 | 说明 |
|---|---|---|---|
| 1 | `plus` | 新建任务 | 唯一 prominent 按钮，位于最左 |
| 2 | `play.fill` | 全部开始 | 启用条件：存在暂停/排队任务 |
| 3 | `pause.fill` | 全部暂停 | 启用条件：存在下载中任务 |
| 4 | `stop.fill` | 停止选中 | |
| 5 | `trash` | 移除 | destructive 角色 |
| 分隔 | | | |
| 6 | `checkmark.shield` / `exclamationmark.triangle.fill` | 依赖状态 | 任一依赖缺失时变为橙色三角，点击弹出依赖状态 Sheet |
| flexible space | | | |
| 7 | 系统搜索字段 | `.searchable` | 按文件名与 URL 过滤 |
| 8 | `gearshape` | 设置 | 打开 Settings 窗口（`Cmd-,`） |

**详情区**结构（宽度不足时纵向堆叠，不隐藏信息）：

1. 头部：文件名（`.title3` semibold）+ 状态徽标 + 「概览 / 分片 / 日志」分段 Picker（`.pickerStyle(.segmented)`）
2. 概览：`Form` + `.formStyle(.grouped)`，分组「来源」（原始 URL / 解析类型 / 清晰度）、「输出」（保存目录 / 文件名模板 / 文件大小）、「传输」（线程数 / 平均速度 / 已用时 / 预计剩余）
3. 分片：`Table` 四列（序号 / 大小 / 速度 / 状态），高度 ≤ 200pt，可滚动
4. 日志：等宽 `ScrollView` + 右上工具条（`doc.on.doc` 复制全部、`trash` 清除、`chevron.down` 跳到底部）

### A.2 新建任务 Sheet（`Cmd-N`，宽 560，不可调整）

```
┌──────────────────────────────────────────────┐
│  新建下载任务                          [×]   │
├──────────────────────────────────────────────┤
│  来源                                        │
│  [ ( ○ 输入 URL       ● 选择本地文件 ) ]      │
│  ┌────────────────────────────────────────┐  │
│  │ https://example.com/index.m3u8         │  │
│  └────────────────────────────────────────┘  │
│  [ 选择本地文件… ]   [ 从剪贴板粘贴 ]         │
│                                              │
│  输出                                        │
│  另存到   [~/Movies  ▾]  [ 选择目录… ]        │
│  文件名模板 [ %title_%quality       ▾ 可用占位符 ]│
│                                              │
│  开始后立即下载      [ 开关 ON ]              │
│  ▸ 高级选项（线程数、请求头、解密 Key…）      │
│                                              │
│                        [ 取消 ] [ 开始下载 ] │
└──────────────────────────────────────────────┘
```

- 高级选项用 `DisclosureGroup` 而不是第二个 Sheet，**同任务的配置必须在一屏可达**（Product 寄存器的可预测性要求）。
- 「开始下载」为主按钮，仅在来源有效时 enabled。
- 来源为空时的错误文案：`请填写 m3u8 链接或选择一个本地文件。`
- URL 格式检查失败：`链接格式不正确。需要以 http:// 或 https:// 开头。`

### A.3 高级设置（Settings 窗口，六分组）

分组顺序固定：**下载 / 网络 / 解密 / 输出 / 直播 / 高级**。用 `TabView` + `.tabViewStyle` 的 macOS 侧栏形态（`.navigationTitle` 组标题）或单列 `Form` 配 `ScrollView`。建议前者，因为 macOS Settings 窗口窄且内容多。

| 分组 | SF Symbol | 控件清单 |
|---|---|---|
| 下载 | `square.and.arrow.down.fill` | 默认保存目录（TextField + 「选择…」按钮）、最大并发任务数（Stepper 1-10）、每文件线程数（Stepper 1-32）、失败自动重试（Toggle + 次数 Stepper）、限速（Toggle + Slider + 数值 `MB/s`） |
| 网络 | `network` | 代理类型（Picker：无 / HTTP / SOCKS5）、代理地址、端口、跳过证书校验（Toggle，配红色说明 `仅在测试环境开启`）、超时秒数（Stepper） |
| 解密 | `key.fill` | 解密 Key（`SecureField` 或明文 TextField + 「显示」按钮，必须允许 "key:id" 多段格式）、自动使用 KEY 请求（Toggle） |
| 输出 | `square.and.pencil` | 默认文件名模板（TextField + 占位符说明）、二进制合并（Toggle，依赖 ffmpeg）、完成后转换（Toggle）、写入元数据（Toggle）、临时文件目录（TextField + 「选择…」） |
| 直播 | `antenna.radiowaves.left.and.right` | 直播录制最大时长（Stepper，分钟）、断流后自动重连（Toggle + 次数 Stepper） |
| 高级 | `slider.horizontal.3` | 自定义请求头（多行键值编辑器，每行一条 `List` 行 + 增删按钮）、Cookie（TextField）、User-Agent（TextField，附「恢复默认」按钮）、原始命令行预览（等宽只读文本框）、日志输出到文件（Toggle + 路径）、完成后通知（Toggle） |

底部常驻一行：`重置为默认值`（destructive 角色 + Alert 二次确认）。

### A.4 依赖状态视图（缺失时的修复指引）

以 Sheet 呈现（宽 620），也作为首次启动的引导：若两项依赖均缺失，应用启动后自动弹出此 Sheet，处理完成才进入列表。已有一项就绪时不自动弹窗，仅在工具栏显示橙色状态图标。

```
┌──────────────────────────────────────────────────────────┐
│  依赖检测                                          [×]   │
│  上次检测：今天 15:42                  [ 重新检测 ]       │
├──────────────────────────────────────────────────────────┤
│  [!] N_m3u8DL-RE            未检测到          [ 安装 ]    │
│      下载引擎。没有它无法解析 m3u8 / MPD 清单。           │
│      推荐安装：                                           │
│      brew install nilaoda/x/n_m3u8dl-re    [ 复制 ]       │
│      或手动指定已下载的二进制位置        [ 选择文件… ]     │
│  ─────────────────────────────────────────────────────    │
│  [✓] ffmpeg                  已就绪 v6.0                │
│      /opt/homebrew/bin/ffmpeg                            │
│      缺失时无法合并音视频，将只下载分片。                  │
└──────────────────────────────────────────────────────────┘
```

- 状态图标：`checkmark.circle.fill`（绿）/ `exclamationmark.triangle.fill`（橙，缺失或版本过低）/ `exclamationmark.octagon.fill`?（红，找到但不可执行）。
- 每张卡只给**一条**推荐安装方式（brew 命令或 releases 链接），其余收进 `Menu`。认知负荷规则：一个决策点的可见选项不超过 4 个。
- 「复制」按钮复制的是可直接粘贴到终端的完整命令，点击后内联反馈 `已复制`（不用 Toast）。
- 版本号必须来自实际 `-v` 输出，禁止写死。

### A.5 拖拽交互

| 拖拽源 | 接受行为 |
|---|---|
| `.m3u8` / `.mpd` / `.txt` 文件 | 打开新建任务 Sheet，来源已填，焦点落在「开始下载」按钮 |
| 纯http URL 文本拖入（含多段文本中的 URL） | 同上；若文本含多条 URL，标题转为 `新建 N 个下载任务`，Sheet 中部显示 URL 列表预览（可勾选剔除） |
| Dock 图标拖入 | 同左（AppDelegate / SwiftUI `.onDrop` 在 application 层处理） |
| 文件含本地 m3u8 引用的相对路径 | Sheet 顶部警告 `这个清单引用了相对路径的本地分片，建议连同分片所在目录一起放在同一文件夹下。` |

视觉反馈：`DropZoneOverlay`，见 §4.3。松手后若类型不支持，Shake? 不 —— macOS 不支持 NSShake 且抖动会被判搞怪。改为：Sheet 正常打开，来源字段为空并写 `未能识别拖入的内容。支持 .m3u8 / .mpd 文件或 http 链接。`

---

## 附录 B：SF Symbols 图标清单

**通用规则**

- 图标尺寸：macOS 上 SF Symbols 与文字混排时按字号走（13pt 文字配 13-14pt 图标），工具栏统一 **16pt**，行内按钮 **14pt**，空状态装饰 **40pt**。
- 所有符号必须是 SF Symbols **4 或更早**（macOS 13 运行时上限），下表标注引入版本。
- 除工具栏与 ≥24pt 独立图标外，图标必须与中文文字标签同现。
- 禁止 `.symbolRenderingMode(.multicolor)` 的默认 guessy 用法：除 `exclamationmark.triangle.fill`（SF4 下确实是 multicolor）与状态色无关的那些符号外，统一通过 `.foregroundStyle()` 显式染色。

| 用途 | SF Symbol 名 | 引入版本 | 尺寸 | 颜色 Token |
|---|---|---|---|---|
| 新建任务 | `plus` | SF1 | 16pt（工具栏） | `sf.accent`（prominent 按钮内为白色） |
| 全部开始 | `play.fill` | SF1 | 16pt | `sf.labelSecondary` |
| 全部暂停 | `pause.fill` | SF1 | 16pt | `sf.labelSecondary` |
| 停止 | `stop.fill` | SF1 | 16pt | `sf.labelSecondary` |
| 移除 / 关闭 Sheet | `xmark` | SF1 | 16pt / 14pt | `sf.labelSecondary` |
| 删除任务（destructive） | `trash` | SF1 | 16pt | `sf.danger` |
| 重试 / 重新检测依赖 | `arrow.clockwise` | SF1 | 16pt / 14pt | `sf.labelSecondary` |
| 复制（URL / 日志 / 命令） | `doc.on.doc` | SF1 | 14pt | `sf.labelSecondary` |
| 从剪贴板粘贴 | `doc.on.clipboard` | SF1 | 14pt | `sf.labelSecondary` |
| 选择目录 / 文件 / 在访达中显示 | `folder` | SF1 | 14pt | `sf.labelSecondary` |
| 设置 | `gearshape` | SF2 | 16pt | `sf.labelSecondary` |
| 搜索 | `magnifyingglass` | SF1 | 跟随系统 | 系统提供 |
| 依赖就绪 | `checkmark.circle.fill` | SF1 | 16pt | `sf.success` |
| 依赖缺失 / 版本过低 | `exclamationmark.triangle.fill` | SF1 | 16pt | `sf.warning` |
| 依赖不可执行 | `xmark.octagon.fill` | SF1 | 16pt | `sf.danger` |
| 下载引擎二进制 | `terminal` | SF2 | 16pt | `sf.labelSecondary` |
| ffmpeg 二进制 | `film` | SF1 | 16pt | `sf.labelSecondary` |
| 状态：排队中 | `clock` | SF1 | 14pt | `sf.neutral` |
| 状态：下载中 | `arrow.down.circle.fill` | SF1 | 14pt | `sf.accent` |
| 状态：已暂停 | `pause.circle.fill` | SF1 | 14pt | `sf.neutral` |
| 状态：合并中 | `shuffle` | SF1 | 14pt | `sf.warning` |
| 状态：已完成 | `checkmark.circle.fill` | SF1 | 14pt | `sf.success` |
| 状态：失败 | `exclamationmark.triangle.fill` | SF1 | 14pt | `sf.danger` |
| 状态：已取消 | `xmark.circle.fill` | SF1 | 14pt | `sf.neutral` |
| 设置分组：下载 | `square.and.arrow.down.fill` | SF1 | 14pt | 跟随系统 tint |
| 设置分组：网络 | `network` | SF3 | 14pt | 跟随系统 tint |
| 设置分组：解密 | `key.fill` | SF2 | 14pt | 跟随系统 tint |
| 设置分组：输出 | `square.and.pencil` | SF1 | 14pt | 跟随系统 tint |
| 设置分组：直播 | `antenna.radiowaves.left.and.right` | SF3 | 14pt | 跟随系统 tint |
| 设置分组：高级 | `slider.horizontal.3` | SF2 | 14pt | 跟随系统 tint |
| 限速 / 速度 | `speedometer` | SF3 | 14pt | `sf.labelSecondary` |
| 线程数 / 重试次数 | `number.circle` | SF2 | 14pt | `sf.labelSecondary` |
| 请求头（多行键值） | `list.bullet` | SF1 | 14pt | `sf.labelSecondary` |
| Cookie | `lock.circle` | SF1 | 14pt | `sf.labelSecondary` |
| 空状态装饰 | `tray.and.arrow.down` | SF1 | 40pt | `sf.labelTertiary`（装饰用，非信息） |
| 日志跳到底部 | `chevron.down` | SF1 | 14pt | `sf.labelSecondary` |
| 帮助 / 文档 | `questionmark.circle` | SF1 | 14pt | `sf.info` |

> 候选但需实机确认的符号：`server.rack`、`shippingbox.fill`、`arrow.triangle.merge` 均为 SF Symbols 4 及以后且部分为 5+，若要在 macOS 13 使用，必须在 macOS 13 实机或 SF Symbols 4 App 中确认存在。上表已改用更低风险的等价符号替代。

---

## 附录 C：任务状态视觉规范（状态 + 进度 + 指标的信息层级）

### C.1 状态矩阵

| 状态 | SF Symbol | 颜色 Token | 中文文案 | 进度条行为 | 详情区是否可操作 |
|---|---|---|---|---|---|
| 排队中 queued | `clock` | `sf.neutral` | `排队中` | 不显示（显示 `--`） | 开始、上移优先级、移除 |
| 下载中 running | `arrow.down.circle.fill` | `sf.accent` | `下载中` | 蓝（accent），跟随真实百分比 | 暂停、停止、打开日志 |
| 已暂停 paused | `pause.circle.fill` | `sf.neutral` | `已暂停` | 保留最后百分比，灰 60% | 继续、移除、查看日志 |
| 合并中 merging | `shuffle` | `sf.warning` | `合并中` | 不确定形态（indeterminate）或 100% 橙 | 无（等待完成），可取消合并 |
| 已完成 done | `checkmark.circle.fill` | `sf.success` | `已完成` | **不显示**，显示完成摘要行 | 在访达中显示、打开、移除记录 |
| 失败 failed | `exclamationmark.triangle.fill` | `sf.danger` | `失败` | 冻结在最后百分比，灰 60% | 重试、查看日志、修改 Key/请求头后重试 |
| 已取消 canceled | `xmark.circle.fill` | `sf.neutral` | `已取消` | 冻结并重 | 重新下载（重置）、移除 |

### C.2 任务行的信息层级（三行，行高 ≥ 56pt）

```
第 1 行（最重要）：文件名                              右侧：清晰度 + 总大小
                   .body / .semibold / .label          .footnote / .labelSecondary

第 2 行（进展）：进度条 ────────────────────░░░░       右侧：百分比 .monospacedDigit

第 3 行（状态 + 指标）：{icon} 下载中                   右侧：速度 · 剩余时间 · 分片
                       .footnote / 状态色              .footnote / .labelSecondary
```

- 三行的视觉重量必须严格递减：第 1 行 semibold 13pt，第 2 行是唯一的色块（4pt 高），第 3 行 11pt 且除状态图标外全为 secondary。
- 「速度 · 剩余 · 分片」用 `·` 中点分隔，间距 6pt，不用竖线和斜杠。
- 任何一项无数据时显示 `—`（半角破折号 U+2014），不显示 `0 KB/s` 或 `剩余 --:--` 这类伪值。

### C.3 详情区摘要的层级

```
文件名（.title3 semibold）
{状态图标} {状态文案}  |  创建于 {时间}                     <- 单行 meta 行

概览 Form：
  来源        https://…                     （可复制，Selectable）
  解析类型     HLS / DASH
  清晰度       1920x1080
  输出         ~/Movies/剧集.S01E03.mp4     （可复制 + 「在访达中显示」）
  线程数       16                           （数字等宽）
  平均速度     8.3 MB/s
  已用时       4:12
  预计剩余     2:14                          （完成时消失，替换为 总用时）
```

---

## 附录 D：变更记录

| 日期 | 变更 | 原因 | 影响范围 |
|---|---|---|---|
| 2026-09-28 | 初版发布 | Phase 2 设计契约产出 | 全项目 |

---

### P0 自检（提交前由 Designer 复核，供 reviewer 直接检测）

- [ ] 全文档 emoji 正则 `[\x{1F300}-\x{1F9FF}\x{2600}-\x{26FF}\x{2700}-\x{27BF}]` 扫描通过（本章正文与所有 UI 图示内零 emoji）
- [ ] 无 `#7C3AED` / `#A855F7` / `#9333EA` / `#EC4899` 及任意 Indigo→Pink 渐变
- [ ] 无 `欢迎使用` / `Lorem ipsum` / `Welcome to` 及同类空洞占位
- [ ] 源码级色值仅存在于 `SFColor` 一处，且全部引用系统语义色
- [ ] 图标 100% 为 SF Symbols，且全部 ≤ SF Symbols 4（macOS 13 可用）
- [ ] 主窗口主体为任务列表与真实数据，无 Hero 区
- [ ] 所有交互组件覆盖 §4.1 的 9 态矩阵与 §8.6 的五态清单
- [ ] 所有间隙值为 4/8/12/16/20/24/32/48 之一
- [ ] 所有圆角 ≤ 12pt
