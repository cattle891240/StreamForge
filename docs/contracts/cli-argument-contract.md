# CLI 参数契约（StreamForge ↔ N_m3u8DL-RE）

> `Sources/StreamForge/Engine/ArgumentBuilder.swift` 与高级设置面板的唯一依据。
> 上游版本：`0.6.0+df70f0b3da0c630bd413bf617e758051f6b64757`（Beta 20260628）。
> 全部参数与默认值均取自本机 `--help` 实测输出，未做任何推测。

## 1. 输出规则（硬约束）

1. **argv 直接传递，禁止 `/bin/sh -c`**：`ProcessSpawner` 走 `posix_spawn`，天然无 shell 注入面。
   `ShellEscaping` 仅用于 UI「命令预览」展示，不得用于执行。
2. **顺序固定**：
   `[executable, input, 行为开关, 路径, 性能, 网络, 轨道选择, 解密, 输出/混流, 直播, 字幕, 杂项]`。
3. **开关型参数一律显式带布尔值**（空格分隔，实测 `--opt False` 与 `--opt=False` 均被接受）：
   `--check-segments-count False`、`--del-after-done False`、`--use-system-proxy False`。
   ⚠️ 实测：给开关型参数一个非布尔值（`--check-segments-count maybe`）会被上游判为
   `Unrecognized command or argument 'maybe'` 而整体失败——因此**值必须严格是 `True`/`False`**。
4. **空值不输出**：字符串为空、数值为 nil 的选项一律省略（让上游取默认）。
5. **用户输入值禁止以 `-` 开头**：`ArgumentBuilder` 校验 `-H`、`--save-name` 等取值，
   非法则 `throw ArgumentError.leadingDash(field:)`，UI 显示字段级错误，不启动任务。
6. **默认值集中**在 `Config/Defaults.swift`，与下表「上游默认」列保持一致；UI 显示的默认即上游默认，
   不做"我们再改一层默认"的隐式行为。

## 2. 必传参数（每次调用都带）

| 参数 | 值 | 理由 |
|---|---|---|
| `--tmp-dir` | `~/Library/Caches/StreamForge/tmp/<taskUUID>` | 隔离临时文件，便于取消后清理与重试复用 |
| `--save-dir` | 用户设置 | — |
| `--save-name` | 用户填写或由 URL 推导 | 重试时必须与首次完全一致 |
| `--no-ansi-color` | 开关 | 避免 ANSI 污染解析（尽管非 TTY 下内核会自动关闭，仍显式传） |
| `--disable-update-check` | 开关 | 避免启动时的意外联网，行为可预期；设置项可开启 |
| `--log-file-path` | `~/Library/Logs/StreamForge/<taskUUID>.log`（可选） | 仅在设置「保留日志」开启时传 |
| `--log-level` | `INFO`（默认）/ `DEBUG` / `WARN` / `ERROR` / `OFF` | 默认 INFO；DEBUG 会淹没面板 |

## 3. 完整参数表

### 3.1 路径与输入

| 参数 | 类型 | 上游默认 | UI 位置 |
|---|---|---|---|
| `--base-url` | String | — | 网络 |
| `--save-pattern` | String（变量见 §4） | — | 输出 |
| `--log-file-path` | String | — | 通用 |

### 3.2 性能

| 参数 | 类型 | 上游默认 | 备注 |
|---|---|---|---|
| `--thread-count <number>` | Int | `8` | UI 范围 1–32，默认跟随上游 |
| `--download-retry-count <number>` | Int | `3` | UI 范围 0–20 |
| `--http-request-timeout <seconds>` | Int | `100` | **与暂停策略强相关**，见 ADR-003 |
| `-R, --max-speed <SPEED>` | String | — | 形如 `15M` / `100K`；UI 提供数字 + 单位 |
| `-mt, --concurrent-download` | Bool | `False` | 并发下载音视字轨 |

### 3.3 网络

| 参数 | 类型 | 上游默认 | 备注 |
|---|---|---|---|
| `-H, --header <header>` | 可重复 | — | UI 用键值对列表，逐条输出一个 `-H "K: V"` |
| `--use-system-proxy` | Bool | **`True`** | 与 `--custom-proxy` 互斥，UI 二选一 |
| `--custom-proxy <URL>` | String | — | 形如 `http://127.0.0.1:8888` |
| `--append-url-params` | Bool | `False` | — |
| `--urlprocessor-args` | String | — | 高阶，UI 放「高级」折叠区 |

### 3.4 轨道选择

| 参数 | 类型 | 上游默认 |
|---|---|---|
| `--auto-select` | Bool | `False` |
| `-sv/--select-video <OPTIONS>` | 复合 | — |
| `-sa/--select-audio <OPTIONS>` | 复合 | — |
| `-ss/--select-subtitle <OPTIONS>` | 复合 | — |
| `-dv/--drop-video`、`-da/--drop-audio`、`-ds/--drop-subtitle` | 复合 | — |
| `--ad-keyword <REG>` | 正则 | — |

复合 OPTIONS 为 `:` 分隔的 `key=value` 列表（实测 `--morehelp select-video`）：

```
id=REGEX | lang=REGEX | name=REGEX | codecs=REGEX | res=REGEX | frame=REGEX | channel=REGEX
range=REGEX | url=REGEX | period=REGEX | segsMin=N | segsMax=N
plistDurMin=hms | plistDurMax=hms | bwMin=int | bwMax=int | role=string
for=best|worst|all|best[N]|worst[N]
```

UI 策略：提供 `for`（best/worst/all）、`res`、`codecs`、`lang`、`segsMin/Max` 五个常用字段，
其余走「原始表达式」文本框。裸关键字 `-sv best` 也合法（实测 example）。

### 3.5 解密

| 参数 | 类型 | 上游默认 | 备注 |
|---|---|---|---|
| `--key <KID:KEY>` | 可重复 | — | 或 `--key KEY`（全轨共用） |
| `--key-text-file <path>` | String | — | — |
| `--decryption-engine` | Enum `FFMPEG\|MP4DECRYPT\|SHAKA_PACKAGER` | `MP4DECRYPT` | — |
| `--decryption-binary-path <PATH>` | String | — | 对应引擎的二进制 |
| `--mp4-real-time-decryption` | Bool | `False` | — |
| `--custom-hls-method` | Enum `AES_128\|AES_128_ECB\|CENC\|CHACHA20\|NONE\|SAMPLE_AES\|SAMPLE_AES_CTR\|UNKNOWN` | — | — |
| `--custom-hls-key <FILE\|HEX\|BASE64>` | String | — | — |
| `--custom-hls-iv <FILE\|HEX\|BASE64>` | String | — | — |

### 3.6 输出与合并

| 参数 | 类型 | 上游默认 |
|---|---|---|
| `--skip-merge` | Bool | `False` |
| `--skip-download` | Bool | `False` |
| `--check-segments-count` | Bool | **`True`** |
| `--binary-merge` | Bool | `False` |
| `--use-ffmpeg-concat-demuxer` | Bool | `False` |
| `--del-after-done` | Bool | **`True`** |
| `--no-date-info` | Bool | `False` |
| `--no-log` | Bool | `False` |
| `--write-meta-json` | Bool | **`True`** |
| `--ffmpeg-binary-path <PATH>` | String | — |
| `-M, --mux-after-done <OPTIONS>` | 复合 | — |
| `--mux-import <OPTIONS>` | 复合（可重复） | — |

`-M` 复合 OPTIONS（实测 `--morehelp mux-after-done`）：
`format=mkv|mp4|ts`、`muxer=ffmpeg|mkvmerge`、`bin_path=PATH`、`skip_sub=BOOL`、`keep=BOOL`，
`:` 分隔。示例 `-M format=mp4`、`-M format=mkv:muxer=mkvmerge:bin_path=/opt/homebrew/bin/mkvmerge`。
注意：`bin_path` 中若含 `:` 需转义（上游 example 用 `\:`），UI 生成时应提示。`--mux-import` 需在 `-M` 启用时才有意义。

### 3.7 直播

| 参数 | 类型 | 上游默认 |
|---|---|---|
| `--live-perform-as-vod` | Bool | `False` |
| `--live-real-time-merge` | Bool | `False` |
| `--live-keep-segments` | Bool | `True` |
| `--live-pipe-mux` | Bool | `False` |
| `--live-fix-vtt-by-audio` | Bool | `False` |
| `--live-record-limit <HH:mm:ss>` | String | — |
| `--live-wait-time <SEC>` | Int | — |
| `--live-take-count <NUM>` | Int | `16` |

**直播任务禁用暂停**（ADR-003）：UI 上直播任务的暂停按钮降级为「停止」。

### 3.8 字幕

| 参数 | 类型 | 上游默认 |
|---|---|---|
| `--sub-only` | Bool | `False` |
| `--sub-format` | Enum `SRT\|VTT` | `SRT` |
| `--auto-subtitle-fix` | Bool | `True` |

### 3.9 其他

| 参数 | 类型 | 上游默认 | 备注 |
|---|---|---|---|
| `--custom-range <RANGE>` | String | — | 实测语法：`0-10`、`10-`、`-99`、`05:00-20:00` |
| `--task-start-at <yyyyMMddHHmmss>` | String | — | UI 用 `Date` 选择器格式化 |
| `--ui-language` | Enum `en-US\|zh-CN\|zh-TW` | — | 只影响内核输出语言；App UI 不做 i18n |
| `--allow-hls-multi-ext-map` | Bool | `False` | 实验性，UI 标注 |
| `--force-ansi-console` | Bool | `False` | **禁止勾选**（与 `--no-ansi-color` 冲突），UI 不暴露 |

## 4. `--save-pattern` 变量

实测可用变量：`<SaveName>`、`<Id>`、`<Codecs>`、`<Language>`、`<Resolution>`、`<Bandwidth>`、
`<MediaType>`、`<Channels>`、`<FrameRate>`、`<VideoRange>`、`<GroupId>`、`<Ext>`。

UI 提供变量插入按钮组（点击在光标处插入），并做"至少包含一个唯一变量"的软提示（避免多轨同名覆盖）。

## 5. 互斥与校验规则（`ArgumentRules`）

| 规则 | 处理 |
|---|---|
| `--use-system-proxy` 与 `--custom-proxy` | 互斥；选中自定义代理时显式传 `--use-system-proxy False` |
| `--skip-download` 与 `--custom-range` | 同时勾选无意义，UI 警告但不阻断 |
| `--sub-only` 与 `-sv` 视频选择 | 同时勾选时 UI 提示"将只下载字幕" |
| `-M` 未启用但填了 `--mux-import` | 阻断并提示 |
| `--live-*` 与 `--custom-range` | 直播场景 `--custom-range` 无效，UI 置灰 |
| `--decryption-engine=FFMPEG` 但 `--decryption-binary-path` 为空 | 回退 `--ffmpeg-binary-path`；两者皆空则用依赖检测的默认 ffmpeg 路径 |
| 需要合并且 ffmpeg 缺失 | **提交前阻断**（依赖检测层） |

## 6. 命令预览

`TaskDetailView` 展示本次任务的**完整命令行**（`ShellEscaping` 转义后单行），可一键复制。
预览与实际执行的 argv **必须同源**（都来自 `ArgumentBuilder.buildArguments`），
禁止 UI 再拼一份——否则必然出现"预览与执行不一致"的沉默逻辑错误。
`ArgumentBuilderTests` 中必须有"预览字符串 == 转义后的 argv 拼接"用例。
