# 内核输出契约（N_m3u8DL-RE）

> 解析层（`Sources/StreamForge/Parsing/`）的唯一依据。数据来自本机实测
> （内核 `0.6.0+df70f0b3da0c630bd413bf617e758051f6b64757`，Beta 20260628；
> macOS 15.7 x86_64；stdout/stderr 重定向到文件，非 TTY）。
> 样本原件：`Tests/Fixtures/kernel_progress_glued.txt`、`kernel_stderr_stacktrace.txt`。

## 1. 实测结论（先读这 5 条）

1. **进度与日志全部走 stdout**；`.NET` 未捕获异常栈走 **stderr**。退出码：成功 `0`，失败 `1`。
2. 非 TTY 模式下内核会自行输出 `Output is redirected, ANSI colors are cleared.`，但**仍会出现 CSI 转义序列**
   （实测捕获到 ESC 字节，结尾形如 `ESC[?12l` / `ESC[?25h`）。**必须剥离 ANSI 后再解析**。
3. **进度刷新帧之间没有任何分隔符**：实测 4623 字节样本中只有 **8 个 `\n`**、**0 个 `\r`**。
   多个进度帧是**直接首尾拼接**的（`...--:--:--Vid Kbps ━━━...`）。不存在"按行解析"的可能。
4. **日志行与日志行也会粘连**：`Content Matched: HTTP Live Streaming16:15:07.223 INFO : Parsing streams...`
   —— 前一行没换行就直接接下一个时间戳。**必须用时间戳 lookahead 切分**。
5. 字段可能"缺位"或"负号"：实测出现 `0/1 0.00% -0.00Bps --:--:--`
   （**字节字段整段缺失**、百分比与速度为 **负值**、ETA 为 `--:--:--`），以及重试计数 `-0.00Bps(1)`。
6. **首个进度帧内核会把轨道名重复输出一次**：实测 `Start downloading...Vid KbpsVid Kbps ━━━…`
   —— 这不是解析错误，是上游首帧自身的行为，会造成一个"永不更新的幽灵轨道"（见 §4 剔除规则）。
7. 真实样本统计：`kernel_progress_glued.txt` 共 4623 字节、**8 个 `\n`**、**14 条日志**
   （11 INFO + 3 WARN）、按时间戳切分得 **14 个 record**、可提取 **30 个进度帧**。

## 2. 日志行文法

```
line      := TIMESTAMP SP LEVEL SP ":" SP message
TIMESTAMP := /\d{2}:\d{2}:\d{2}\.\d{3}/            # 例 16:15:07.161
LEVEL     := "INFO" | "WARN" | "DEBUG" | "ERROR"
message   := 任意字符（可含中文、路径、URL），直到下一个 TIMESTAMP 或流结束
```

切分正则（`RecordSplitter`，Swift 用 `NSRegularExpression`，**不用 Swift Regex DSL**，规避可用性风险）：

```
(?=\d{2}:\d{2}:\d{2}\.\d{3}\s+(?:INFO|WARN|DEBUG|ERROR)\s*:)
```

用 `split` 语义做 lookahead 切分（零宽断言切分，不吞掉任何字符）。
切分后每个 record 形如 `<TIMESTAMP> <LEVEL> : <message><粘连的进度块…>`：
- record 头部匹配 `^(\d{2}:\d{2}:\d{2}\.\d{3})\s+(INFO|WARN|DEBUG|ERROR)\s*:\s*(.*)$`（`dotMatchesLineSeparators = true`）
  → 产出 `LogEntry`；捕获组 3 的**剩余部分**交给 `ProgressParser`。
- 第一个 record 之前若有残留（进程刚启动的半个帧），直接丢弃。

## 3. 进度帧文法

```
frame := name BAR? SP done "/" total SP pct "%" [ SP sizeDone UNIT "/" sizeTotal UNIT ] SP speed [ "(" retry ")" ] SP eta
name  := /[A-Za-z][A-Za-z0-9 _\|\(\)\[\]x\-]{0,63}?/  # 必须以字母开头；**不含 . 与 :**
                                                      # 实测值：Vid Kbps / Vid 1920x1080 / Aud zh-CN / Sub
BAR   := /[━╺─\s]*/                                 # U+2501 ━ / U+257A ╺ / U+2500 ─
done  := /\d+/          total := /\d+/
pct   := /-?[\d.]+/                                 # 实测出现 -0.00 → 必须允许负号，解析后 clamp 到 [0,100]
UNIT  := "B" | "KB" | "MB" | "GB"
speed := /-?[\d.]+/ ("Bps" | "KBps" | "MBps")       # 实测出现 -0.00Bps → 负值按 unknown 处理
retry := /\d+/                                      # 可选，形如 (1) (2)，实测递增
eta   := /\d{2}:\d{2}:\d{2}/ | "--:--:--"           # --:--:-- 解析为 nil
```

NSRegularExpression 模式（`ParserPatterns.progressFrame`，`.dotMatchesLineSeparators = true`）：

```
([A-Za-z][A-Za-z0-9 _\|\(\)\[\]x\-]{0,63}?)\s*([━╺─]*)\s*(\d+)/(\d+)\s+(-?[\d.]+)%(?:\s+([\d.]+)(B|KB|MB|GB)/([\d.]+)(B|KB|MB|GB))?\s+(-?[\d.]+)(Bps|KBps|MBps)(?:\((\d+)\))?\s+(\d{2}:\d{2}:\d{2}|--:--:--)
```

组号：1 name / 2 bar / 3 done / 4 total / 5 pct / 6 sizeDone / 7 unitA / 8 sizeTotal / 9 unitB / 10 speed / 11 unitC / 12 retry / 13 eta

> **为什么 name 必须以字母开头且排除 `.` 与 `:`**（踩过的坑，勿改回）：
> 若允许任意字符起头，粘连文本会被吞进轨道名——实测会把 `Start downloading...Vid Kbps`、
> `--:--:--Vid Kbps` 整段当成 name（Python 等价验证复现过）。以字母起头 + 排除 `.`/`:`
> 之后，同名问题消失（`Vid 1280x720`、`Vid Kbps`、`Aud zh-CN` 均可正确捕获）。
> 副作用：轨道名中若真的含 `.`（未在上游观察到）会被截断到 `.` 之后——可接受。

## 4. 多轨道归并规则

- 一次刷新会按顺序写出所有轨道帧（`-mt` 并发下载时同批多个轨道）。
- 对同一批 bytes，**按出现顺序遍历所有匹配**，以 `name` 为 key 写入字典，**后者覆盖前者**：
  `tracks[frame.name] = frame`。因此每个轨道自然得到本批的最后一个（最新）帧。
### 4.1 幽灵轨道剔除（stale key eviction）

上游首帧会把轨道名重复输出一次（`Vid KbpsVid Kbps`），该 key 之后再也不更新，
会永久停在 0%，表现为一个"幽灵轨道"。处理规则：

- `OutputParser` 为每个 key 记录 `lastSeenTick`（每处理一个 record 递增 1）。
- `latestTracks` 只返回 `currentTick - lastSeenTick <= staleWindow` 的轨道，**默认 `staleWindow = 10`**
  （上游约 10 Hz 刷新，即约 1 秒）。
- 任务终态（进程退出）时调用 `freeze()`：**冻结当前可见集合**，不再剔除，
  保证最后一帧的轨道状态（含已完成轨道）不丢失。
- 单元测试需覆盖：注入一个只出现一次的 key，断言 10 个 tick 后它从 `latestTracks` 消失。

### 4.2 展示

- 轨道显示名：name 原样展示；图标按前缀判定（`Vid`→`film`、`Aud`→`waveform`、`Sub`→`captions.bubble`，其余 `square.stack.3d.up`）。
- **已知限制**：若两条轨道的 `name` 完全相同（罕见），进度会串台。UI 不做区分，属可接受限制（R5）。
- **直播场景**：播放列表持续刷新，`total` 会随时间增长（`16/16` → `32/32`），百分比会"到顶再重置"。
  因此直播任务的进度展示以**已下载分片数**为主（`square.stack.3d.up`），百分比与 ETA 作为次要信息，
  且 ETA 恒为 `--:--:--`（UI 显示 `--`）。

## 5. 阶段状态机（OutputParser）

关键词仅用于**展示**；**终态一律以退出码判定**，避免关键词缺失导致状态卡死（R4）。

| 触发 | 阶段 |
|---|---|
| 任务入队 | `.queued` |
| 收到首条日志 / `Loading URL:` | `.preparing` |
| `Start downloading...` | `.downloading` |
| 日志含 `ffmpeg merging` / `Merging` / `Decrypting` | `.merging` |
| 退出码 0 | `.finished(.succeeded)` |
| 退出码非 0 且非用户取消 | `.finished(.failed)` |
| 用户取消 | `.finished(.cancelled)` |
| 主动 SIGSTOP | `.paused` |
| P2 停止（保留 tmp） | `.stopped(reusable: true)` |

- 关键词表集中在 `LogHints.swift`，**不得散落到视图**。
- `ERROR` 级别日志累加 `errorCount` 并取首条作为 `lastError`。
- 常见错误 → 提示映射（`LogHints`）：`403|401` → 检查请求头与 Cookie；`404` → 链接或 BaseURL 有误；
  `timed out|Timeout` → 提高 `--http-request-timeout` 或降低线程数；`decrypt|KEY` → 检查解密 Key 与引擎；
  `ffmpeg` → 检查 ffmpeg 路径。

## 6. 字节流处理要求（OutputNormalizer）

1. **UTF-8 增量解码**：进度条 `━` 是 3 字节，可能跨 chunk 截断。保留不足 4 字节的尾部残留到下一批再解码，
   严禁产生替换字符 `�` 或丢帧（`OutputParser.flushTail()` 处理进程退出时的残留）。
2. **ANSI 剥离**：`/\u{1B}\[[0-9;?]*[a-zA-Z]/` 全局替换为空，在切分之前执行。
3. **背压**：必须持续读取管道。暂停读取会让内核写阻塞、进而**拖慢甚至卡死下载**——这也是"停止读取管道"
   不能作为暂停手段的原因（ADR-003）。
4. **节流**：`TaskCoordinator` 以 100 ms 合并窗口向主线程发布进度，禁止逐字节刷新 UI。
5. **解析不抛异常**：任何解析失败记录一条 `WARN` 日志并跳过，绝不影响进程生命期。

## 7. 解析层验收用例（必须存在）

| 用例 | 输入 | 断言 |
|---|---|---|
| 粘连日志切分 | `kernel_progress_glued.txt` | `LogEntry` 条数 == 时间戳出现次数 **14**；无一条 message 含下一时间戳；第一个时间戳之前的残留被丢弃 |
| 进度帧提取 | 同上 | 共解析出 **30** 个帧；`tracks` 中存在 key `Vid Kbps`，`total == 1`、`done == 0` |
| 最新帧生效 | 同上 | `tracks` 只保留最新帧（done 单调不回退） |
| 幽灵轨道剔除 | 合成：注入只出现一次的 key | 10 个 tick 后该 key 从 `latestTracks` 消失；`freeze()` 后不再剔除 |
| 负值与未知 | 同上 | `pct` clamp 到 0；`speed` 负值 → `speedUnknown = true`；`eta == nil` |
| 字节字段缺失 | 同上 | `sizeDone == nil` 不崩溃 |
| 重试计数 | 同上 | 含 `(1)` 的帧可正常解析，`retryCount == 1` |
| ANSI 剥离 | `kernel_ansi.txt` | 输出中不含 `\u{1B}` |
| 半行 UTF-8 | 手工把 `━` 的 3 字节拆到两个 chunk | 两个 chunk 解析结果与整块解析一致 |
| 变异加固 | 把 lookahead 正则改为普通匹配 | 「粘连日志切分」用例必须变红 |
| stderr 栈 | `kernel_stderr_stacktrace.txt` | 记为一条 `ERROR`；任务终态 failed，退出码 1 |
