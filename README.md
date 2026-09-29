# StreamForge

StreamForge 是 [N_m3u8DL-RE](https://github.com/nilaoda/N_m3u8DL-RE) 的 macOS 原生图形界面客户端。

N_m3u8DL-RE 是一个功能强大的命令行流媒体下载器，支持 MPD / M3U8 / ISM 的点播与直播下载。StreamForge 不改变它的任何下载行为，而是把它的能力装进一个符合 macOS 设计规范的窗口里：任务可以排队、进度可以看见、出错可以干预、参数不用记忆。

> **重要**：StreamForge **不捆绑、不嵌入、不重新分发** N_m3u8DL-RE 或 ffmpeg 的任何二进制文件。它以命令行方式调用你本机已安装的下载器，并实时读取其输出。第三方组件的归属与许可见 [NOTICE.md](NOTICE.md)。

---

## 功能

**任务管理**
- 新建任务：支持直接粘贴 URL，或选择本地 `.m3u8` / `.mpd` / `.ism` 文件
- 拖拽添加：把文件或 URL 文本拖到窗口（或 Dock 图标）即可创建任务
- 任务队列：可配置并发上限（默认 2），超出上限的任务自动排队
- 任务控制：暂停 / 继续 / 取消，以及失败后重试

**进度与日志**
- 实时进度：完成百分比、下载速度、剩余时间（ETA）、分片完成状态
- 多轨道分别展示：视频、音频、字幕各自独立呈现进度
- 日志面板：实时显示下载器输出，按级别着色，支持过滤、复制与清空

**高级设置**（六个分组，覆盖下载器主要参数）
- 下载：线程数、重试次数、超时、限速、并发下载
- 网络：系统代理 / 自定义代理、自定义请求头、Cookie、BaseURL
- 解密：解密 Key、Key 文件、解密引擎与二进制路径、HLS 自定义 Key / IV
- 输出：文件名、命名模板（`<SaveName>` `<Resolution>` `<Bandwidth>` 等变量）、混流容器与混流器
- 直播：录制时长限制、实时合并、管道混流、刷新间隔等直播选项
- 高级：HLS 加密方式、URL 处理器参数、界面语言等

**其他**
- 外部依赖自动检测：启动时检测下载器与 ffmpeg，缺失时给出具体的安装指引
- 下载完成后发送系统通知（成功 / 失败）
- 支持深色模式（跟随系统或手动指定）
- 命令行预览：可查看将要执行的完整命令

---

## 系统要求

- macOS 13.0 或更高版本
- 本机已安装 N_m3u8DL-RE 与 ffmpeg（见下节）

---

## 依赖说明

StreamForge 是图形外壳，实际下载工作由以下外部工具完成，需要你自行安装。

### 必需

**1. N_m3u8DL-RE**（下载内核）

从上游仓库的 [Releases 页面](https://github.com/nilaoda/N_m3u8DL-RE/releases) 下载 macOS 版本（注意选择与你的芯片匹配的版本：Intel 选 `osx-x64`，Apple Silicon 选 `osx-arm64`），解压后放到合适位置，例如：

```bash
# 示例：放到本地二进制目录并确保可执行
mv N_m3u8DL-RE /usr/local/bin/
chmod +x /usr/local/bin/N_m3u8DL-RE
```

macOS 会对下载的二进制标记隔离属性（quarantine），导致首次运行被 Gatekeeper 拦截。如遇此情况：

```bash
xattr -d com.apple.quarantine /usr/local/bin/N_m3u8DL-RE
```

**2. ffmpeg**（用于分片合并与混流）

```bash
brew install ffmpeg
```

### 可选

仅在你在「解密」设置中选择对应解密引擎时才需要：

- **mp4decrypt**（Bento4 的一部分）：`brew install bento4`，默认解密引擎
- **shaka-packager**：用于可选的解密引擎

应用启动时会自动在常见路径中检测上述工具。若全部缺失，界面会展示依赖状态卡片并给出对应的安装命令，任务在依赖就绪前不会启动。

---

## 运行与安装

### 方式一：使用预编译产物（推荐）

1. 从 [Releases](../../releases) 页面下载 `StreamForge-<版本>.dmg`
2. 打开 dmg，把 `StreamForge.app` 拖入「应用程序」文件夹
3. 首次启动：
   - 本项目的发布产物**未经 Apple Developer ID 签名**，macOS Gatekeeper 会拦截
   - 解决方式：**右键点击** `StreamForge.app` → 选择「打开」→ 在弹窗中确认
   - （或在「系统设置 → 隐私与安全性」中点击「仍要打开」）
4. 确认依赖已安装（见上一节），然后开始新建任务

### 方式二：从源码构建

```bash
git clone <你的仓库地址>
cd StreamForge

# 1) 运行测试（会自动探测可用的 macOS SDK）
./Scripts/test.sh

# 2) 构建 .app 并打包 dmg
./Scripts/build.sh
./Scripts/package.sh

# 3) 打开
open dist/StreamForge.app
```

构建脚本会自动探测可用的 macOS SDK（依次尝试 15.5 / 15.4 / 15.2 / 14.5），无需手动指定。

---

## 使用方法

1. 点击工具栏「新建任务」（或按 `Cmd-N`）
2. 填入流媒体地址，或选择本地的 `.m3u8` / `.mpd` 文件
3. 选择保存目录，可按需设置文件名或命名模板
4. 需要调整线程数、代理、解密 Key 等参数时，打开「设置」（`Cmd-,`）在对应分组中修改
5. 点击开始，任务进入队列；在主窗口右侧可查看该任务的轨道进度与实时日志
6. 下载中可随时暂停、继续或取消；完成后会收到系统通知

---

## 项目结构

```
StreamForge/
├── Sources/StreamForge/
│   ├── App/        应用入口与装配
│   ├── Models/     数据模型（任务、进度、日志、选项…）
│   ├── Config/     默认参数与持久化
│   ├── Engine/     子进程管理、输出泵、参数构建
│   ├── Parsing/    内核输出解析（ANSI 剥离 / 记录切分 / 进度解析）
│   ├── Services/   任务队列、暂停控制、依赖检测、通知
│   ├── UI/         SwiftUI 界面（主窗口 / 任务列表 / 设置 / 日志面板…）
│   └── Util/       格式化、环形缓冲等纯函数
├── Tests/          自写测试 harness 与用例（含真实抓取的内核输出样本）
├── Scripts/        构建、测试、打包、门禁脚本
├── docs/           架构、设计、契约与决策记录
└── .github/        CI 与发布工作流
```

分层遵循单向依赖：`UI → Services → Engine/Parsing → Models/Config → Util`。其中 Engine、Parsing、Services、Models 均不依赖 SwiftUI，因此可在命令行测试可执行文件中直接编译运行。

---

## 脚本说明

| 脚本 | 作用 |
|---|---|
| `Scripts/find-sdk.sh` | 探测可用的 macOS SDK（带 SwiftUI 真实编译探针与缓存） |
| `Scripts/test.sh` | 编译并运行测试，退出码即结果 |
| `Scripts/build.sh` | 编译源码并组装 `StreamForge.app` |
| `Scripts/package.sh` | 打包为 dmg（支持可选签名） |
| `Scripts/make-icon.swift` | 生成应用图标 |
| `Scripts/check-layout.sh` | 架构门禁：单文件行数、依赖方向、无 emoji 图标 |

---

## 截图

> 待补充：应用完成后在此处替换为实际截图。

主窗口（任务列表与详情双栏）：

![主窗口](docs/screenshots/main-window.png)

新建任务面板：

![新建任务](docs/screenshots/new-task.png)

高级设置：

![高级设置](docs/screenshots/settings.png)

---

## 开发

设计文档与工程约定位于 `docs/`：

- [架构设计](docs/architecture.md) —— 分层、目录结构、模块接口契约
- [界面规范](docs/design.md) —— 设计系统、配色、排版、组件与图标
- [规格说明](docs/SPEC.md) —— 范围锁定与验收标准
- [内核输出契约](docs/contracts/kernel-output-contract.md) —— 输出文法（解析层依据）
- [参数契约](docs/contracts/cli-argument-contract.md) —— 参数表与映射规则
- [决策记录](docs/decisions/) —— ADR-001 … ADR-006

提交前请运行：

```bash
./Scripts/check-layout.sh   # 架构门禁
./Scripts/test.sh           # 测试
```

---

## 发布流程

见 [docs/RELEASING.md](docs/RELEASING.md)。简述：更新 `VERSION` 与 `CHANGELOG.md` → 打 `v*` 标签并推送 → GitHub Actions 自动构建、打包并创建 Release 草稿。

---

## 许可证

本项目采用 **MIT License**，详见 [LICENSE](LICENSE)。

N_m3u8DL-RE 由 nilaoda 开发，同样基于 MIT License。StreamForge 不分发其二进制文件。第三方组件的归属与许可声明见 [NOTICE.md](NOTICE.md)。

上游项目声明：本软件仅用于学习和技术研究目的，使用者应遵守所在国家或地区的法律法规，仅下载和获取拥有合法权限的流媒体内容。
