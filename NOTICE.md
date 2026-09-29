# 第三方声明

StreamForge 是命令行工具 **N_m3u8DL-RE** 的图形界面前端。StreamForge 本身不含、
不嵌入、不重新分发任何第三方二进制文件。

## N_m3u8DL-RE

- 项目地址：https://github.com/nilaoda/N_m3u8DL-RE
- 版权：Copyright (c) nilaoda
- 许可：MIT License
- 用途：解析 MPD / M3U8 / ISM 流媒体并完成分片下载、解密与合并，是本应用的功能内核

StreamForge 通过命令行调用该工具，实时读取其标准输出以呈现进度与日志。
用户需自行下载并安装该工具（README 中给出了获取方式），StreamForge 在启动时
自动检测其是否存在，缺失时给出安装指引。

## ffmpeg

- 项目地址：https://ffmpeg.org
- 许可：LGPL / GPL（按构建配置而定）
- 用途：分片合并、混流（mp4 / mkv）、部分解密场景

## 可选工具

以下工具仅在用户在高级设置中选择了对应解密引擎时才需要：

- **mp4decrypt**（Bento4 的一部分）：https://github.com/axiomatic-systems/Bento4
  用于 CENC 加密内容的解密，StreamForge 默认解密引擎
- **shaka-packager**：https://github.com/shaka-project/shaka-packager
  可选解密引擎

上述工具均由用户自行安装，各自遵循其自身的许可证。
