#!/bin/bash
#
# 提示词自动优化 Hook - Bash 版本 (Mac/Linux)
# sns-workflow 集成版
#
# 工作流程：
# 1. 用户输入提示词
# 2. 过滤（内置命令、技能命令、简单回复等）
# 3. 优化
# 4. 返回优化后的提示词给 Claude
#

set -eo pipefail

# 跨平台临时目录
LOG_FILE="${TMPDIR:-${TMP:-/tmp}}/hook-prompt-optimizer.log"

# 日志函数（仅用于通过过滤的输入）
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null || true
}

# 安全读取用户输入
USER_INPUT=""
if [ $# -gt 0 ]; then
    USER_INPUT="$*"
else
    USER_INPUT=$(cat)
fi

# 去除首尾空白
USER_INPUT=$(echo "$USER_INPUT" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# ============================================
# 过滤规则：以下输入跳过优化，返回 {}
# ============================================

# 过滤 1: Claude Code 内置命令（以 / 开头，但 sns-workflow: 技能命令除外——需要特殊处理）
# 非 sns-workflow 的斜杠命令全部跳过
if [[ "$USER_INPUT" =~ ^/[^s] ]] || \
   [[ "$USER_INPUT" =~ ^/sn[^s] ]] || \
   [[ "$USER_INPUT" =~ ^/sns[^-] ]] || \
   [[ "$USER_INPUT" =~ ^/sns-[^w] ]] || \
   [[ "$USER_INPUT" =~ ^/sns-w[^o] ]] || \
   [[ "$USER_INPUT" =~ ^/sns-wo[^r] ]] || \
   [[ "$USER_INPUT" =~ ^/sns-wor[^k] ]] || \
   [[ "$USER_INPUT" =~ ^/sns-work[^f] ]] || \
   [[ "$USER_INPUT" =~ ^/sns-workf[^l] ]] || \
   [[ "$USER_INPUT" =~ ^/sns-workfl[^o] ]] || \
   [[ "$USER_INPUT" =~ ^/sns-workflo[^w] ]] || \
   [[ "$USER_INPUT" =~ ^/sns-workflow$ ]] || \
   [[ "$USER_INPUT" =~ ^/[^/] ]]; then
    # 纯 / 开头的命令（非 sns-workflow 技能）跳过
    if [[ "$USER_INPUT" =~ ^/ && ! "$USER_INPUT" =~ ^/sns-workflow: ]]; then
        echo "{}"
        exit 0
    fi
fi

# 过滤 2: 单斜杠命令（/clear, /help, /commit 等 Claude Code 内置命令）
if [[ "$USER_INPUT" =~ ^/[a-z] ]]; then
    echo "{}"
    exit 0
fi

# 过滤 3: sns-workflow 技能命令 — 保持原样，不优化
# 匹配: /sns-workflow:arch-lint, /sns-workflow:commit-push-pr 等
if [[ "$USER_INPUT" =~ ^/sns-workflow:[a-zA-Z] ]]; then
    echo "{}"
    exit 0
fi

# 过滤 4: Claude Code 内部系统消息
if [[ "$USER_INPUT" =~ ^\<(task-notification|system-reminder|tool-result|tool-use|agent-response|claude-internal) ]]; then
    echo "{}"
    exit 0
fi

# 过滤 5: 简单交互式回复
case "$USER_INPUT" in
    好的|是的|继续|谢谢|ok|OK|yes|YES|no|NO|确认|取消|好|行|可以|不|嗯|y|n|Y|N|\
    好的。|是的。|继续。|谢谢。|好的，|是的，|继续，|谢谢，)
        echo "{}"
        exit 0
        ;;
esac

# 过滤 6: 太短（< 10 字符）
INPUT_LENGTH=${#USER_INPUT}
if [ "$INPUT_LENGTH" -lt 10 ]; then
    echo "{}"
    exit 0
fi

# ============================================
# 通过过滤，开始优化
# ============================================
log "========================================"
log "Hook执行开始"
log "用户输入: ${USER_INPUT:0:100}..."
log "输入长度: ${INPUT_LENGTH}"
log "通过过滤，开始优化..."

# 查找模板文件
OPTIMIZER_PROMPT_FILE=""

# 1. 相对于脚本目录查找
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || true
    if [ -n "$SCRIPT_DIR" ]; then
        OPTIMIZER_PROMPT_FILE="$SCRIPT_DIR/../prompt-optimizer-meta.md"
    fi
fi

# 2. 备选：CLAUDE_PLUGIN_ROOT
if [ ! -f "$OPTIMIZER_PROMPT_FILE" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    OPTIMIZER_PROMPT_FILE="${CLAUDE_PLUGIN_ROOT}/skills/prompt-optimize/prompt-optimizer-meta.md"
fi

# 3. 备选：用户主目录
if [ ! -f "$OPTIMIZER_PROMPT_FILE" ]; then
    OPTIMIZER_PROMPT_FILE="$HOME/.claude/prompt-optimizer-meta.md"
fi

# 检查模板是否存在
if [ ! -f "$OPTIMIZER_PROMPT_FILE" ]; then
    log "错误：模板文件未找到"
    echo "{}"
    exit 0
fi

# 读取模板
OPTIMIZER_PROMPT=$(cat "$OPTIMIZER_PROMPT_FILE") || {
    log "错误：读取模板文件失败"
    echo "{}"
    exit 0
}

log "模板已加载，构建优化请求..."

# 构建优化上下文
ADDITIONAL_CONTEXT="${OPTIMIZER_PROMPT}

---

## 用户原始输入

${USER_INPUT}

---

请严格按照格式输出优化结果，最后必须包含完整的优化后提示词。

**重要**：输出优化结果后，立即执行\"优化后的完整提示词\"中描述的任务，不要等待用户确认。"

# 输出 JSON（手动构建，转义特殊字符）
# 1. 反斜杠 → \\
# 2. 双引号 → \"
# 3. 换行 → \n
ESCAPED_CONTEXT=$(printf '%s' "$ADDITIONAL_CONTEXT" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//')

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}' "$ESCAPED_CONTEXT"

log "优化请求已发送（JSON格式）"
