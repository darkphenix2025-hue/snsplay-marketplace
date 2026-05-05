#!/usr/bin/env bash
# remind-doc-update.sh — PostToolUse hook for doc-garden skill
# 每次 Edit/Write 代码文件后，提醒同步更新文档
# 返回 {"permissionDecision":"ask","message":"..."} 提醒，或 {} 放行
set -euo pipefail

# Read stdin (JSON with tool_input and tool_name)
INPUT=$(cat)

# Extract the "file_path" field value from tool_input
FILE_PATH=$(printf '%s' "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' || true)

if [ -z "$FILE_PATH" ]; then
  FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("tool_input",{}).get("file_path",""))' 2>/dev/null || true)
fi

if [ -z "$FILE_PATH" ]; then
  echo '{}'
  exit 0
fi

# 排除条件：文档文件不需要再提醒
# docs/ 目录下的文件
case "$FILE_PATH" in
  */docs/*|*/CLAUDE.md|*/AGENTS.md|*/README.md|*/.claude/*|*.md)
    echo '{}'
    exit 0
    ;;
esac

# 只对代码文件触发（排除配置、图片、锁文件等）
case "$FILE_PATH" in
  *.ts|*.tsx|*.js|*.jsx|*.sh|*.py|*.go|*.rs|*.json|*.yaml|*.yml|*.toml)
    ;;
  *)
    echo '{}'
    exit 0
    ;;
esac

# 提取文件名用于提醒
BASENAME=$(basename "$FILE_PATH")

MSG="[doc-garden] 代码已修改: $BASENAME。请同步更新相关文档（docs/ 下对应文件），确保代码与文档一致"
MSG_ESCAPED=$(printf '%s' "$MSG" | sed 's/"/\\"/g')

printf '{"permissionDecision":"ask","message":"%s"}\n' "$MSG_ESCAPED"
