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

1. 在 `macos-15` runner 上探测可用的 macOS SDK（与 CI 锁定同版本，ADR-001）
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

## 签名与公证（Developer ID Signing & Notarization）

未配置任何签名/公证 Secret 时，流水线向后兼容：产物为 **ad-hoc 签名**（仅保证本机可启动，
对外分发仍会被 Gatekeeper 拦截，需用户右键「打开」）。配置下方 Secret 后，即变为
**Developer ID 签名 + 公证（Notarization）**，用户可双击直接打开。

### 前提条件

- 加入 **Apple Developer Program**（$99/年）。这是创建 Developer ID 证书与提交公证的硬性要求。
  仅有免费 Apple ID 无法做对外分发的签名/公证。

### 需要的证书与凭据

| 用途 | 类型 | 说明 |
|------|------|------|
| 签名 .app / .dmg | **Developer ID Application** 证书 | 注意不是 "Developer ID Installer"，也不是 Mac App Distribution |
| 提交公证 | Apple ID + **应用专用密码** + 团队 ID | `notarytool` 不能用 Apple ID 普通密码 |

### 第 1 步：生成 Developer ID Application 证书

方式 A（推荐，Xcode）：
1. Xcode → Settings → Accounts → 选中你的 Apple ID → Manage Certificates。
2. 左下角 + → 选 **Developer ID Application** → 自动生成并装入登录钥匙串。

方式 B（Developer 网站 + 钥匙串访问）：
1. 打开 **钥匙串访问** → 证书助理 → 从证书颁发机构请求证书… → 填邮箱与名称、CA 邮箱留空、选「存储到磁盘」→ 得到 `CertificateSigningRequest.certSigningRequest`。
2. 打开 [developer.apple.com](https://developer.apple.com) → Certificates, Identifiers & Profiles → Certificates → + → 选 **Developer ID** → **Developer ID Application** → 上传上面的 `.certSigningRequest`。
3. 下载生成的 `.cer`，双击装入**登录（login）**钥匙串。

### 第 2 步：导出 p12（CI 用）

1. 钥匙串访问 → 登录 → 我的证书 → 找到 `Developer ID Application: 你的名字 (TEAMID)`。
2. 右键 → 导出 → 格式选 **.p12** → 设一个「导出密码」（即 `MACOS_CERTIFICATE_PASSWORD`）。
   p12 内含证书 + 私钥，CI 才能用它签名。

### 第 3 步：p12 转 base64

```bash
base64 -i Certificates.p12 | pbcopy   # 复制到剪贴板
```

### 第 4 步：准备公证凭据

1. [appleid.apple.com](https://appleid.apple.com) → 登录与安全 → **应用专用密码** → 生成（即 `NOTARIZATION_PASSWORD`，不是 Apple ID 密码）。
2. 团队 ID（`NOTARIZATION_TEAM_ID`，10 位字符）：developer.apple.com 右下角或 Membership 页查看。
3. `NOTARIZATION_APPLE_ID` = 你的 Apple ID 邮箱。

### 第 5 步：在仓库配置 Secrets

GitHub 仓库 → **Settings → Secrets and variables → Actions → New repository secret**，新增：

| Secret 名 | 值 |
|-----------|-----|
| `MACOS_CERTIFICATE` | 第 3 步的 base64 字符串 |
| `MACOS_CERTIFICATE_PASSWORD` | p12 导出密码 |
| `MACOS_KEYCHAIN_PASSWORD` | 任意随机串（如 `openssl rand -base64 24`，仅 CI 临时钥匙串用） |
| `MACOS_SIGNING_IDENTITY` | 证书身份全名，形如 `Developer ID Application: 你的名字 (TEAMID)` |
| `NOTARIZATION_APPLE_ID` | Apple ID 邮箱 |
| `NOTARIZATION_TEAM_ID` | 团队 ID（10 位） |
| `NOTARIZATION_PASSWORD` | 应用专用密码 |

> 获取身份全名：证书装好后终端执行 `security find-identity -v -p codesigning`，复制 `Developer ID Application:` 那一条的值。

### 第 6 步：触发签名发布

配置好 Secrets 后，推送一个新的 `v*` tag（或 Actions 页面手动 Run workflow）。流水线会：
导入证书 → `build.sh` 用 Developer ID 签名 .app（加固运行时）→ `package.sh` 签名 dmg
→ `notarytool` 公证 → `stapler staple` 钉入票据 → 生成校验和 → 创建 Release。

### 常见问题

- **签名失败 `errSecInternalComponent`**：钥匙串分区权限问题。流水线已用 `set-key-partition-list -S apple-tool:,apple:` 处理；本机若遇此错，重启钥匙串访问或重导 p12。
- **公证失败（缺时间戳 / 缺 hardened runtime）**：流水线已用 `--options runtime --timestamp` 签名；自行改脚本请保留这两个选项。
- **应用需要特殊授权**：在 `build.sh` 增加 `--entitlements` 并提供一个 `.entitlements` plist；当前 StreamForge 为纯 GUI，无需自定义 entitlements 即可公证通过。
- **`MACOS_KEYCHAIN_PASSWORD` 泄露**：它只是 CI 临时钥匙串密码，不接触你的真实钥匙串，泄露无直接危害，可随时轮换。
