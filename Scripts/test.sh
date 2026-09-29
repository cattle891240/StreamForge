#!/usr/bin/env bash
#
# test.sh —— 编译并运行测试可执行文件。退出码即结果（0 通过 / 1 失败）。
#
# 为什么不用 XCTest（ADR-006，本机实测）：
#   - Command Line Tools 的 SDK 中不存在 XCTest.framework
#   - SwiftPM 崩溃（ADR-001）连带 swift test 不可用
# 因此测试 = 普通可执行文件 + 自写 harness（Tests/Harness/MiniTest.swift）+ 退出码。
#
# 编译范围：排除 Sources/StreamForge/App 与 Sources/StreamForge/UI。
# 这同时是架构门禁——UI 层一旦混入业务逻辑就无法被编译进测试，CI 第一时间暴露。
#
# 注意：Tests/Harness/main.swift 使用 @main 入口写法，
#       因此**必须**加 -parse-as-library（与顶层代码写法相反，勿删）。
#
# 用法：
#   ./Scripts/test.sh                    # 全量
#   ./Scripts/test.sh --filter Parser    # 只跑名字含 Parser 的用例
#   ./Scripts/test.sh --list             # 只列出用例
#
# 退出码：0 通过或优雅跳过；1 有用例失败；70 环境错误

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

ARCH="${ARCH:-$(uname -m)}"
MIN_MACOS="${MIN_MACOS:-13.0}"
TARGET="${TARGET:-${ARCH}-apple-macosx${MIN_MACOS}}"

log()  { printf '[test] %s\n' "$*"; }
warn() { printf '[test] 警告 %s\n' "$*" >&2; }
die()  { printf '[test] 错误 %s\n' "$*" >&2; exit "${2:-1}"; }

# ---------------------------------------------------------------- 收集文件
SRCS=()
while IFS= read -r f; do
    [ -n "$f" ] && SRCS+=("$f")
done < <(find Sources -name '*.swift' -type f \
            -not -path '*/UI/*' -not -path '*/App/*' 2>/dev/null | sort || true)

TESTS=()
while IFS= read -r f; do
    [ -n "$f" ] && TESTS+=("$f")
done < <(find Tests -name '*.swift' -type f 2>/dev/null | sort || true)

if [ "${#TESTS[@]}" -eq 0 ]; then
    warn "Tests/ 下没有 .swift 文件（测试源码尚未就绪），跳过测试执行。"
    warn "本脚本自身已就绪；请等 Tests/ 落地后重跑。"
    exit 0
fi

if [ "${#SRCS[@]}" -eq 0 ]; then
    warn "Sources/ 下没有可参与测试的 .swift 文件（排除 UI / App 后为空）。"
    warn "Swift 源码尚未就绪，跳过测试执行。"
    exit 0
fi

log "被测源码 ${#SRCS[@]} 个，测试文件 ${#TESTS[@]} 个"

# ---------------------------------------------------------------- SDK
if ! SDK="$("$SCRIPT_DIR/find-sdk.sh")"; then
    die "SDK 探测失败" 70
fi
[ -n "$SDK" ] || die "find-sdk.sh 返回空路径" 70
log "选用 SDK：$SDK"

# ---------------------------------------------------------------- 编译
OUT_DIR=".build/test"
BIN="$OUT_DIR/StreamForgeTests"
mkdir -p "$OUT_DIR"

COMMON=(
    -swift-version 5
    -target "$TARGET"
    -sdk "$SDK"
    -parse-as-library
)

# 依赖尚未落地的测试分组由编译开关保护（见 Tests/Harness/main.swift 注释）。
# 这里按源码实际就绪情况自动启用：模块写完了就自动解锁对应用例，无需改脚本。
DEFS=()
if [ -f "Sources/StreamForge/Parsing/OutputParser.swift" ] \
   && [ -f "Sources/StreamForge/Parsing/ProgressParser.swift" ] \
   && [ -f "Sources/StreamForge/Parsing/LogHints.swift" ]; then
    DEFS+=(-D SF_PARSING_FULL)
    log "Parsing 三件套已就绪 → 启用 -D SF_PARSING_FULL"
else
    warn "Parsing 尚缺 LogHints/ProgressParser/OutputParser，相关用例本次不参与编译"
fi

if [ -f "Sources/StreamForge/Engine/ArgumentBuilder.swift" ] \
   && [ -f "Sources/StreamForge/Engine/ProcessHandle.swift" ]; then
    DEFS+=(-D SF_ENGINE_READY)
    log "Engine 已就绪 → 启用 -D SF_ENGINE_READY"
else
    warn "Engine 尚未落地，ArgumentBuilder / PauseController 用例本次不参与编译"
fi

log "编译测试可执行文件…"
swiftc -Onone -g "${COMMON[@]}" "${DEFS[@]}" "${SRCS[@]}" "${TESTS[@]}" -o "$BIN"

# ---------------------------------------------------------------- 运行
log "运行测试（工作目录 = 仓库根，Fixtures 相对路径以此为准）…"
set +e
"$BIN" "$@"
STATUS=$?
set -e

if [ "$STATUS" -ne 0 ]; then
    printf '[test] 失败：测试可执行文件退出码 %d\n' "$STATUS" >&2
    exit 1
fi
log "通过"
exit 0
