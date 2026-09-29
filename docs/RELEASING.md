# 发布流程

StreamForge 采用语义化版本（[SemVer 2.0.0](https://semver.org/lang/zh-CN/)），版本号格式为 `MAJOR.MINOR.PATCH`。

- **MAJOR**：不兼容的架构变更或破坏性配置格式变更
- **MINOR**：向后兼容的新功能（如新增高级设置项、新增直播录制选项）
- **PATCH**：向后兼容的问题修复（解析修正、构建脚本修复、文档修正）

## 自动化发布（推荐）

发布由推送 `v*` 格式的 Git 标签触发，GitHub Actions 完成构建、打包与发布草稿创建。

```bash
# 1. 确认工作区干净且主分支为最新
git checkout main
git pull --rebase
git status

# 2. 更新版本号（两处需同步）
#    - 仓库根目录 VERSION 文件（唯一真源：build.sh 读取它注入 Info.plist 与 -D SF_VERSION）
#    - CHANGELOG.md 中的新版本条目
$EDITOR VERSION CHANGELOG.md

# 3. 提交版本变更
git add VERSION CHANGELOG.md
git commit -m "chore(release): bump version to v1.0.0"

# 4. 打标签并推送
git tag -a v1.0.0 -m "StreamForge v1.0.0"
git push origin main
git push origin v1.0.0
```

推送标签后，`.github/workflows/release.yml` 会自动执行：

1. 在 `macos-latest` runner 上探测可用的 macOS SDK
2. 使用 `swiftc` 编译全部源码
3. 运行 `Scripts/test.sh` 全量测试（任一失败则终止发布）
4. 组装 `StreamForge.app`
5. 打包为 `StreamForge-<version>.dmg`
6. 创建 GitHub Release 草稿并上传 dmg 与校验和

发布草稿创建后，需人工核对 release notes 并点击 Publish。

## 预发布版本

版本号带后缀的标签（如 `v1.1.0-beta.1`）会被识别为预发布（prerelease），Release 中会自动标记 `Pre-release` 徽章，不会覆盖稳定版的安装说明。

## 本地构建验证

发布前建议先在本地完整跑一遍构建与测试：

```bash
./Scripts/test.sh     # 运行测试
./Scripts/build.sh    # 构建 .app 与 .dmg
open dist/StreamForge.app
```

## 签名说明

当前发布产物**未经 Developer ID 签名与公证**。用户在首次启动时需要在「系统设置 → 隐私与安全性」中确认，或右键点击应用选择「打开」以绕过 Gatekeeper。README 中已提供相应说明。

若维护者拥有 Apple Developer 账号，可在仓库 Settings 中配置以下 secrets 后启用签名（工作流已预留开关）：

- `MACOS_CERTIFICATE`（Base64 编码的 .p12 证书）
- `MACOS_CERTIFICATE_PASSWORD`
- `MACOS_KEYCHAIN_PASSWORD`
- `MACOS_SIGNING_IDENTITY`
- `NOTARIZATION_APPLE_ID` / `NOTARIZATION_TEAM_ID` / `NOTARIZATION_PASSWORD`

未配置上述 secrets 时，工作流自动降级为未签名产物，构建不会失败。
