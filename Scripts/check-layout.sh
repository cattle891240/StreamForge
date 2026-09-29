#!/usr/bin/env bash
#
# check-layout.sh —— 架构门禁。build.sh 编译前自动调用，CI 也单独跑一遍。
#
# 检查项（architecture.md §2.1 依赖铁律 / §3 目录结构 / ADR-001）：
#   1. 单个 Swift 文件有效代码行 ≤ 300（不含空行与整行注释）
#   2. Engine / Parsing / Services / Models / Config 禁止 import SwiftUI
#      （这些层必须能在命令行测试可执行文件里编译，见 architecture.md §7）
#   3. 源码与测试中不出现 emoji 作图标（P0-1）
#   4. 不存在 Package.swift（ADR-001：禁止 SwiftPM）
#
# 用法：./Scripts/check-layout.sh
# 退出码：0 通过或跳过；1 存在违规；70 脚本自身环境错误
#
# 说明：源码目录尚未就绪时优雅跳过，不视为失败（并行开发场景下不阻塞）。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

MAX_LINES="${MAX_LINES:-300}"

VIOLATIONS=0
SKIPPED=0

fail() { printf '[check-layout] 违规  %s\n' "$*" >&2; VIOLATIONS=$((VIOLATIONS + 1)); }
skip() { printf '[check-layout] 跳过  %s\n' "$*"; SKIPPED=$((SKIPPED + 1)); }
info() { printf '[check-layout] %s\n' "$*"; }

# 统计有效代码行：去掉空行与整行注释（//  ///  /*  * 开头）
count_code_lines() {
    awk '
        {
            line = $0
            gsub(/^[ \t]+/, "", line)
            gsub(/[ \t]+$/, "", line)
            if (line == "") next
            if (line ~ /^\/\//) next
            if (line ~ /^\/\*/) next
            if (line ~ /^\*/) next
            n++
        }
        END { print n + 0 }
    ' "$1"
}

# emoji 检测：只覆盖真正的 emoji 区段，不误伤「→」「★」等排版符号
emoji_scan() {
    perl -ne 'print "$ARGV:$.: $_" if /[\x{1F000}-\x{1FAFF}\x{1F1E6}-\x{1F1FF}\x{2600}-\x{26FF}\x{2700}-\x{27BF}\x{2B00}-\x{2BFF}\x{FE0F}\x{20E3}]/' "$@" 2>/dev/null
}

# ---------------------------------------------------------------- 1. Package.swift
if [ -f Package.swift ]; then
    fail "存在 Package.swift —— ADR-001 明确禁止 SwiftPM，请改用 Scripts/build.sh"
fi

# ---------------------------------------------------------------- 2. 源码就绪判定
if [ ! -d Sources ]; then
    skip "Sources/ 不存在（Swift 源码尚未就绪），行数与依赖方向检查暂不执行"
fi
if [ ! -d Tests ]; then
    skip "Tests/ 不存在（测试源码尚未就绪），相关检查暂不执行"
fi

SWIFT_FILES=""
if [ -d Sources ] || [ -d Tests ]; then
    SWIFT_FILES="$(find Sources Tests -name '*.swift' -type f 2>/dev/null | sort || true)"
fi

if [ -z "$SWIFT_FILES" ]; then
    skip "未找到任何 .swift 文件，全部内容检查暂不执行"
else
    # ------------------------------------------------------------ 3. 单文件行数
    info "检查单文件行数（上限 $MAX_LINES 有效行）…"
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        n="$(count_code_lines "$f")"
        if [ "$n" -gt "$MAX_LINES" ]; then
            fail "$f 有 $n 有效行，超过上限 $MAX_LINES —— 请拆分文件"
        fi
    done <<EOF
$SWIFT_FILES
EOF

    # ------------------------------------------------------------ 4. 依赖方向
    info "检查依赖方向（Engine/Parsing/Services/Models/Config 禁止 import SwiftUI）…"
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in
            */Engine/*|*/Parsing/*|*/Services/*|*/Models/*|*/Config/*) ;;
            *) continue ;;
        esac
        if grep -nE '^[[:space:]]*import[[:space:]]+SwiftUI' "$f" >/dev/null 2>&1; then
            line="$(grep -nE '^[[:space:]]*import[[:space:]]+SwiftUI' "$f" | head -1)"
            fail "$f 引入了 SwiftUI（${line}）—— 该层必须能在命令行测试可执行文件中编译"
        fi
    done <<EOF
$SWIFT_FILES
EOF

    # ------------------------------------------------------------ 5. emoji
    info "检查 emoji（P0-1：图标一律走 SF Symbols）…"
    # shellcheck disable=SC2086
    HITS="$(emoji_scan $SWIFT_FILES || true)"
    if [ -n "$HITS" ]; then
        while IFS= read -r hit; do
            [ -n "$hit" ] && fail "发现 emoji：$hit"
        done <<EOF
$HITS
EOF
    fi
fi

# ---------------------------------------------------------------- 汇总
if [ "$VIOLATIONS" -gt 0 ]; then
    printf '[check-layout] 未通过：%d 项违规\n' "$VIOLATIONS" >&2
    exit 1
fi

if [ "$SKIPPED" -gt 0 ]; then
    info "通过（优雅跳过 $SKIPPED 项：源码尚未就绪）"
else
    info "通过：行数 / 依赖方向 / emoji / 无 Package.swift 全部合规"
fi
exit 0
