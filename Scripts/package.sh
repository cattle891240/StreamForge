#!/usr/bin/env bash
#
# package.sh —— 由 dist/StreamForge.app 生成分发产物：dmg + zip + SHA256 校验和。
#
# 默认先调用 build.sh 保证 .app 与 VERSION 同步；设置 SKIP_BUILD=1 可跳过。
#
# 用法：
#   ./Scripts/package.sh                 # 构建 + 打包
#   SKIP_BUILD=1 ./Scripts/package.sh    # 只打包（复用已有 dist/StreamForge.app）
#   SIGN_IDENTITY="Developer ID Application: ..." ./Scripts/package.sh
#
# 产物（均在 dist/）：
#   StreamForge-<version>.dmg      UDZO 压缩镜像
#   StreamForge-<version>.zip      zip 归档（便于不经镜像直接分发）
#   SHA256SUMS-<version>.txt       校验和
#
# 退出码：0 成功；70 环境错误

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

log()  { printf '[package] %s\n' "$*"; }
warn() { printf '[package] 警告 %s\n' "$*" >&2; }
die()  { printf '[package] 错误 %s\n' "$*" >&2; exit "${2:-1}"; }

[ -f VERSION ] || die "根目录缺少 VERSION 文件"
VERSION="$(tr -d '[:space:]' < VERSION)"
[ -n "$VERSION" ] || die "VERSION 文件内容为空"
PKG_ARCH="${PKG_ARCH:-}"            # 非空时给产物名加后缀（如 intel / apple-silicon），用于分架构发布
log "版本 v$VERSION${PKG_ARCH:+-$PKG_ARCH}"

APP="dist/StreamForge.app"

# ---------------------------------------------------------------- 确保 .app 存在
if [ "${SKIP_BUILD:-0}" = "1" ]; then
    [ -d "$APP" ] || die "SKIP_BUILD=1 但 $APP 不存在" 70
    log "跳过构建，复用已有 $APP"
else
    log "调用 build.sh 构建 .app…"
    "$SCRIPT_DIR/build.sh"
fi

[ -d "$APP" ] || die "构建后仍未找到 $APP" 70
[ -f "$APP/Contents/MacOS/StreamForge" ] || die "$APP 结构不完整：缺少 MacOS/StreamForge" 70
[ -f "$APP/Contents/Resources/AppIcon.icns" ] || warn "缺少 AppIcon.icns（不影响打包）"

mkdir -p dist

# ---------------------------------------------------------------- dmg
DMG="dist/StreamForge-${VERSION}${PKG_ARCH:+-$PKG_ARCH}.dmg"
log "生成 dmg…"
rm -f "$DMG"
# 注意：macOS 无 GNU timeout，脚本中禁用该命令
hdiutil create \
    -volname "StreamForge" \
    -srcfolder "$APP" \
    -ov \
    -format UDZO \
    "$DMG" >/dev/null
log "产物：$DMG"

# 若指定了签名身份（来自 build.sh 透传的 SIGN_IDENTITY），对 dmg 做
# Developer ID 签名（加固运行时 + 时间戳），满足 Apple 公证要求。
if [ -n "${SIGN_IDENTITY:-}" ]; then
    log "签名 dmg（hardened runtime）…"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

# ---------------------------------------------------------------- zip
ZIP="dist/StreamForge-${VERSION}${PKG_ARCH:+-$PKG_ARCH}.zip"
log "生成 zip…"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
log "产物：$ZIP"

# ---------------------------------------------------------------- 校验和
SUMS="dist/SHA256SUMS-$VERSION.txt"
log "计算校验和…"
(
    cd dist
    shasum -a 256 "StreamForge-$VERSION.dmg" "StreamForge-$VERSION.zip" > "SHA256SUMS-$VERSION.txt"
)
log "产物：$SUMS"
cat "$SUMS"

log "完成。发布流程见 docs/RELEASING.md"
