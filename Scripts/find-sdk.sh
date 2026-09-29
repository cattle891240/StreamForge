#!/usr/bin/env bash
#
# Scripts/find-sdk.sh — 探测本机可用的 macOS SDK
#
# 背景（ADR-001）：
#   Swift 6.1.2 与 MacOSX26.2.sdk 不兼容，编译 SwiftUI 时报
#     cannot suppress '~Copyable' on generic parameter ...
#   而 xcrun 报告的"默认 SDK"恰恰就是 26.2。因此不能信任 xcrun 的默认选择，
#   也不能只检查目录是否存在——必须对每个候选跑一次真实编译探针。
#
# 探测顺序（首个编译通过者即采用）：
#   1. $MACOSX_SDK（显式覆盖）
#   2. MacOSX15.5 / 15.4 / 15.2 / 14.5，依次在以下目录查找
#        - /Library/Developer/CommandLineTools/SDKs
#        - $(xcode-select -p)/Platforms/MacOSX.platform/Developer/SDKs
#        - /Applications/Xcode*.app/.../MacOSX.platform/Developer/SDKs
#   3. xcrun --sdk macosx --show-sdk-path（兜底：CI 完整 Xcode 场景）
#
# 结果缓存到 .build/.sdk-cache（key = 编译器版本 + target + 探针哈希），
# 缓存命中时不重复编译。
#
# 用法：
#   SDK=$(Scripts/find-sdk.sh)         # stdout 只有一行：SDK 绝对路径
#   Scripts/find-sdk.sh --force        # 忽略缓存，重新探测
#   Scripts/find-sdk.sh --verbose      # 打印逐个候选的诊断
#
# 退出码：0 成功；70 全部候选均失败（并打印诊断）

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE="$REPO_ROOT/Scripts/sdk-probe.swift"
CACHE_FILE="$REPO_ROOT/.build/.sdk-cache"

MIN_MACOS="${MIN_MACOS:-13.0}"
ARCH="${ARCH:-$(uname -m)}"
TARGET="${ARCH}-apple-macosx${MIN_MACOS}"
# 探针模式：typecheck（默认，快）| full（含链接，慢但更严格）
PROBE_MODE="${SF_SDK_PROBE_MODE:-typecheck}"

FORCE=0
VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    --force|-f)  FORCE=1 ;;
    --verbose|-v) VERBOSE=1 ;;
    --quiet|-q)  VERBOSE=-1 ;;
    *) echo "find-sdk: 未知参数 $arg" >&2; exit 64 ;;
  esac
done

log()  { if [ "$VERBOSE" -ge 0 ]; then echo "[find-sdk] $*" >&2; fi; }
warn() { echo "[find-sdk] $*" >&2; }
die()  { echo "[find-sdk] 错误：$*" >&2; exit 70; }

[ -f "$PROBE" ] || die "探针源码不存在：$PROBE"
command -v swiftc >/dev/null 2>&1 || die "未找到 swiftc，请先安装 Xcode Command Line Tools"

# ---------------------------------------------------------------- 缓存 key
hash_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  else
    cksum "$1" 2>/dev/null | awk '{print $1}'
  fi
}

SWIFTC_VERSION="$(swiftc --version 2>&1 | tr '\n' ' ')"
SWIFTC_PATH="$(command -v swiftc)"
CACHE_KEY="$(printf '%s|%s|%s|%s|%s' \
  "$SWIFTC_VERSION" "$SWIFTC_PATH" "$TARGET" "${PROBE_MODE}" "$(hash_file "$PROBE")")"

if [ "$FORCE" -eq 0 ] && [ -f "$CACHE_FILE" ]; then
  CACHED_KEY="$(sed -n '1p' "$CACHE_FILE" 2>/dev/null)"
  CACHED_SDK="$(sed -n '2p' "$CACHE_FILE" 2>/dev/null)"
  if [ "$CACHED_KEY" = "$CACHE_KEY" ] && [ -n "${CACHED_SDK}" ] && [ -d "${CACHED_SDK}" ]; then
    log "缓存命中：${CACHED_SDK}"
    echo "${CACHED_SDK}"
    exit 0
  fi
  log "缓存失效（编译器/target/探针已变化），重新探测"
fi

# ------------------------------------------------------- 构造候选 SDK 列表
CANDIDATES=()

add_candidate() {
  local p="$1" c
  [ -n "$p" ] || return 0
  for c in "${CANDIDATES[@]:-}"; do
    [ "$c" = "$p" ] && return 0
  done
  if [ -d "$p" ]; then
    CANDIDATES+=("$p")
  else
    log "跳过（目录不存在）：$p"
  fi
}

SDK_DIRS=()
SDK_DIRS+=("/Library/Developer/CommandLineTools/SDKs")
XCODE_SELECT_PATH="$(xcode-select -p 2>/dev/null || true)"
if [ -n "$XCODE_SELECT_PATH" ]; then
  SDK_DIRS+=("$XCODE_SELECT_PATH/Platforms/MacOSX.platform/Developer/SDKs")
fi
# 完整 Xcode（含带版本后缀的多个 Xcode）
for app in /Applications/Xcode*.app; do
  [ -d "$app" ] && SDK_DIRS+=("$app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs")
done

# 1 显式覆盖
[ -n "${MACOSX_SDK:-}" ] && add_candidate "$MACOSX_SDK"

# 2 版本优先（15.5 → 15.4 → 15.2 → 14.5）
for ver in 15.5 15.4 15.2 14.5; do
  for dir in "${SDK_DIRS[@]}"; do
    add_candidate "$dir/MacOSX$ver.sdk"
  done
done

# 3 兜底
if command -v xcrun >/dev/null 2>&1; then
  XCRUN_SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
  add_candidate "$XCRUN_SDK"
fi

if [ "${#CANDIDATES[@]}" -eq 0 ]; then
  die "未找到任何 macOS SDK 候选。已搜索目录：${SDK_DIRS[*]}"
fi

log "候选数量 ${#CANDIDATES[@]}，target=${TARGET}，探针模式=${PROBE_MODE}"

# --------------------------------------------------------------- 编译探针
TMPDIR_PROBE="$(mktemp -d "${TMPDIR:-/tmp}/streamforge-sdk.XXXXXX")"
trap 'rm -rf "$TMPDIR_PROBE"' EXIT INT TERM

probe_sdk() {
  local sdk="$1"
  local logfile="$TMPDIR_PROBE/probe.log"
  local args=(-parse-as-library -swift-version 5 -target "$TARGET" -sdk "${sdk}")

  rm -f "$logfile"
  if [ "${PROBE_MODE}" = "full" ]; then
    swiftc "${args[@]}" -o "$TMPDIR_PROBE/probe.bin" "$PROBE" >"$logfile" 2>&1
  else
    swiftc -typecheck "${args[@]}" "$PROBE" >"$logfile" 2>&1
  fi
}

FAILURES=""
for sdk in "${CANDIDATES[@]}"; do
  log "探测：${sdk}"
  if probe_sdk "${sdk}"; then
    mkdir -p "$(dirname "$CACHE_FILE")"
    printf '%s\n%s\n' "$CACHE_KEY" "${sdk}" > "$CACHE_FILE"
    log "采用：${sdk}（已写入缓存 $(dirname "$CACHE_FILE")/.sdk-cache）"
    echo "${sdk}"
    exit 0
  fi
  first_err="$(grep -m1 -E 'error:' "$TMPDIR_PROBE/probe.log" 2>/dev/null || true)"
  [ -z "${first_err}" ] && first_err="$(sed -n '1p' "$TMPDIR_PROBE/probe.log" 2>/dev/null)"
  log "  失败：${first_err}"
  FAILURES="${FAILURES}  - $sdk
      ${first_err}
"
done

warn "全部 ${#CANDIDATES[@]} 个候选 SDK 均未通过编译探针。"
warn "失败明细："
printf '%s' "$FAILURES" >&2
warn "排障建议："
warn "  - 安装 Xcode Command Line Tools：xcode-select --install"
warn "  - 查看已安装 SDK：ls /Library/Developer/CommandLineTools/SDKs"
warn "  - 手动指定：MACOSX_SDK=/path/to/MacOSX15.5.sdk Scripts/find-sdk.sh --force"
warn "  - 完整 Xcode 场景：sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
exit 70
