#!/usr/bin/env bash
#
# build.sh —— 编译 StreamForge 并组装 .app bundle。
#
# 硬约束（ADR-001，本机实测）：
#   - 禁止 SwiftPM（swift build 崩溃：llbuild 符号缺失），一律 swiftc 直接编译
#   - SDK 不写死，由 Scripts/find-sdk.sh 探测（26.2 与 Swift 6.1.2 不兼容）
#   - 必须 -parse-as-library（否则 @main 与顶层代码冲突）
#   - 必须 -swift-version 5（避免 Swift 6 严格并发检查噪声）
#   - 只用 -target，不用 -macosx-version-min（二者冲突）
#   - macOS 无 GNU timeout，脚本中禁用该命令
#
# 用法：
#   ./Scripts/build.sh                       # release 构建 + 组装 dist/StreamForge.app
#   CONFIG=debug ./Scripts/build.sh          # 调试构建（-Onone -g -D DEBUG）
#   ARCH=x86_64 ./Scripts/build.sh           # 仅 Intel（默认：本机架构 uname -m）
#   ARCH=arm64 ./Scripts/build.sh            # 仅 Apple Silicon（M 系列）
#   ARCH=universal ./Scripts/build.sh        # 通用二进制（x86_64 + arm64，本地自用）
#   ARCH=x86_64,arm64 ./Scripts/build.sh     # 等价 universal
#   SKIP_GATE=1 ./Scripts/build.sh           # 跳过 check-layout.sh 门禁
#   SIGN_IDENTITY="Developer ID Application: ..." ./Scripts/build.sh
#   SKIP_SIGN=1 ./Scripts/build.sh           # 完全不签名
#
# 退出码：0 成功；70 SDK 探测失败或源码未就绪；其他为 swiftc 原样退出码

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

ARCH="${ARCH:-$(uname -m)}"            # 默认本机架构；发布时分别用 x86_64 / arm64 打两个包
MIN_MACOS="${MIN_MACOS:-13.0}"
CONFIG="${CONFIG:-release}"

# 解析目标架构列表（universal 为默认；也可用 ARCH=x86_64,arm64 显式指定）
if [ "$ARCH" = "universal" ]; then
    BUILD_ARCHS=(x86_64 arm64)
elif [ "$ARCH" = "native" ]; then
    BUILD_ARCHS=("$(uname -m)")
else
    IFS=',' read -ra BUILD_ARCHS <<< "$ARCH"
fi

log()  { printf '[build] %s\n' "$*"; }
warn() { printf '[build] 警告 %s\n' "$*" >&2; }
die()  { printf '[build] 错误 %s\n' "$*" >&2; exit "${2:-1}"; }

# ---------------------------------------------------------------- 版本号
[ -f VERSION ] || die "根目录缺少 VERSION 文件（版本号唯一真源）"
VERSION="$(tr -d '[:space:]' < VERSION)"
[ -n "$VERSION" ] || die "VERSION 文件内容为空"
log "版本 v$VERSION  架构 ${BUILD_ARCHS[*]}  部署目标 macOS $MIN_MACOS  配置 $CONFIG"

# ---------------------------------------------------------------- 门禁
if [ "${SKIP_GATE:-0}" = "1" ]; then
    warn "已设置 SKIP_GATE=1，跳过架构门禁 check-layout.sh"
else
    [ -x "$SCRIPT_DIR/check-layout.sh" ] || chmod +x "$SCRIPT_DIR/check-layout.sh"
    log "运行架构门禁…"
    "$SCRIPT_DIR/check-layout.sh"
fi

# ---------------------------------------------------------------- SDK
log "探测 SDK…"
# find-sdk 需要单一有效架构做编译探针；架构列表首位即可（SDK 路径与架构无关）
PROBE_ARCH="${BUILD_ARCHS[0]}"
if ! SDK="$(ARCH="$PROBE_ARCH" "$SCRIPT_DIR/find-sdk.sh")"; then
    die "SDK 探测失败：没有任何候选 SDK 能通过 SwiftUI 编译探针。
  排查：ls /Library/Developer/CommandLineTools/SDKs
  强制指定：MACOSX_SDK=/path/to/MacOSX15.5.sdk $0" 70
fi
[ -n "$SDK" ] || die "find-sdk.sh 返回空路径" 70
log "选用 SDK：$SDK"

# ---------------------------------------------------------------- 源文件
SRCS=()
while IFS= read -r f; do
    [ -n "$f" ] && SRCS+=("$f")
done < <(find Sources -name '*.swift' -type f 2>/dev/null | sort || true)

if [ "${#SRCS[@]}" -eq 0 ]; then
    die "Sources/ 下没有 .swift 文件（Swift 源码尚未就绪）。
  本脚本自身已就绪；请等 Sources/ 落地后重跑。" 70
fi
log "源文件 ${#SRCS[@]} 个"

# ---------------------------------------------------------------- 编译
if [ "$CONFIG" = "debug" ]; then
    OPT_FLAGS=(-Onone -g -D DEBUG)
else
    OPT_FLAGS=(-O)
fi

COMMON=(
    -parse-as-library
    -swift-version 5
    -sdk "$SDK"
    -D SF_VERSION
)

# 逐架构编译，再用 lipo 合并为通用二进制
OUT_DIR=".build/$CONFIG"
BIN="$OUT_DIR/StreamForge"
mkdir -p "$OUT_DIR"
SLICE_BINS=()
log "编译中（无增量编译，首次较慢；universal 为双架构，耗时约 2 倍）…"
for a in "${BUILD_ARCHS[@]}"; do
    atarget="${a}-apple-macosx${MIN_MACOS}"
    slice_bin="$OUT_DIR/StreamForge-$a"
    log "  编译架构 $a (target: $atarget)"
    swiftc "${OPT_FLAGS[@]}" "${COMMON[@]}" -target "$atarget" "${SRCS[@]}" -o "$slice_bin"
    SLICE_BINS+=("$slice_bin")
done

if [ "${#SLICE_BINS[@]}" -gt 1 ]; then
    log "合并为通用二进制（lipo -create）…"
    lipo -create -output "$BIN" "${SLICE_BINS[@]}"
else
    cp "${SLICE_BINS[0]}" "$BIN"
fi
log "编译产物：$BIN"

# ---------------------------------------------------------------- 图标
ICON_DIR=".build/AppIcon.iconset"
ICNS="$OUT_DIR/AppIcon.icns"
if [ ! -f "$ICNS" ]; then
    log "生成 AppIcon（CoreGraphics 绘制，不使用 SF Symbols）…"
    mkdir -p .build/tools
    swiftc -O -target "$(uname -m)-apple-macosx${MIN_MACOS}" -sdk "$SDK" \
        "$SCRIPT_DIR/make-icon.swift" -o .build/tools/make-icon
    .build/tools/make-icon "$ICON_DIR"
    iconutil -c icns "$ICON_DIR" -o "$ICNS"
fi

# ---------------------------------------------------------------- 组装 .app
APP_ROOT="dist/StreamForge.app"
CONTENTS="$APP_ROOT/Contents"
log "组装 $APP_ROOT …"
rm -rf "$APP_ROOT"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN" "$CONTENTS/MacOS/StreamForge"
chmod +x "$CONTENTS/MacOS/StreamForge"
cp "$ICNS" "$CONTENTS/Resources/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>StreamForge</string>
    <key>CFBundleDisplayName</key>
    <string>StreamForge</string>
    <key>CFBundleIdentifier</key>
    <string>com.streamforge</string>
    <key>CFBundleExecutable</key>
    <string>StreamForge</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
</dict>
</plist>
PLIST

# ---------------------------------------------------------------- 签名
# 默认 ad-hoc（保证本机可启动）；设置 SIGN_IDENTITY 则走 Developer ID；
# 设置 SKIP_SIGN=1 则完全不签。
if [ "${SKIP_SIGN:-0}" = "1" ]; then
    warn "SKIP_SIGN=1，产物未签名"
elif [ -n "${SIGN_IDENTITY:-}" ]; then
    log "使用身份签名：$SIGN_IDENTITY"
    codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_ROOT"
else
    log "ad-hoc 签名（--sign -），发布态为未签名；Gatekeeper 处理见 README"
    codesign --force --deep --sign - "$APP_ROOT"
fi

# 本地开发便利：去掉隔离属性，避免首次打开被 Gatekeeper 拦
xattr -dr com.apple.quarantine "$APP_ROOT" 2>/dev/null || true

log "完成：$APP_ROOT"
log "运行：open $APP_ROOT"
