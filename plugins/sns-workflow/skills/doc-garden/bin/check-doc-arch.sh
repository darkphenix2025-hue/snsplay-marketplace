#!/usr/bin/env bash
# check-doc-arch.sh — PreToolUse hook for doc-garden skill
# 在 git push 前检查文档架构合规性（只读，不修复）
# 返回 {"permissionDecision":"ask","message":"..."} 提醒，或 {} 放行
set -euo pipefail

# Read stdin (JSON with tool_input)
INPUT=$(cat)

# Extract the "command" field value from tool_input
CMD=$(printf '%s' "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' || true)

if [ -z "$CMD" ]; then
  CMD=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("tool_input",{}).get("command",""))' 2>/dev/null || true)
fi

if [ -z "$CMD" ]; then
  echo '{}'
  exit 0
fi

# 只对 git push 触发
if ! printf '%s' "$CMD" | grep -qE 'git\s+push' 2>/dev/null; then
  echo '{}'
  exit 0
fi

# 查找共用架构规则脚本
SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
if [[ ! -f "$SCRIPT_DIR/doc-arch-template.sh" ]]; then
  # 尝试从 CLAUDE_SKILL_DIR 推导
  if [[ -n "${CLAUDE_SKILL_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$CLAUDE_SKILL_DIR/../.." && pwd)/scripts"
  fi
fi

if [[ ! -f "$SCRIPT_DIR/doc-arch-template.sh" ]]; then
  echo '{}'
  exit 0
fi

# Source 架构规则
# shellcheck source=/dev/null
source "$SCRIPT_DIR/doc-arch-template.sh"

# 检查是否是已初始化的文档项目
local root
root=$(_sns_doc_root)
if [[ -z "$root" ]]; then
  echo '{}'
  exit 0
fi

# 运行合规性检查
CHECK_OUTPUT=$(sns_doc_check --quiet 2>/dev/null)
CHECK_EXIT=$?

if [[ "$CHECK_EXIT" -eq 0 ]]; then
  echo '{}'
  exit 0
fi

# 获取详细报告
REPORT=$(sns_doc_check 2>/dev/null || true)
REPORT_ESCAPED=$(printf '%s' "$REPORT" | sed 's/"/\\"/g' | tr '\n' ' ')

printf '{"permissionDecision":"ask","message":"[doc-garden] 文档架构不符合要求: %s。请运行 /sns-workflow:doc-garden --fix 或在 commit-push-pr 中更新文档"}\n' "$REPORT_ESCAPED"
