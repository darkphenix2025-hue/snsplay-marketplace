#!/usr/bin/env bash
# check-doc-sync.sh — PostToolUse hook for doc-garden skill
# 检测代码变更后文档同步状态，发现不一致时输出具体修复指令
# 返回 {"permissionDecision":"ask","message":"..."} 或 {} 放行
set -euo pipefail

# === 1. 读取 stdin，提取 file_path ===
INPUT=$(cat)

FILE_PATH=$(printf '%s' "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' || true)

if [ -z "$FILE_PATH" ]; then
  FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("tool_input",{}).get("file_path",""))' 2>/dev/null || true)
fi

if [ -z "$FILE_PATH" ]; then
  echo '{}'
  exit 0
fi

# === 2. 判断是否需要检查 ===
BASENAME=$(basename "$FILE_PATH")

# 需要触发同步检查的文件类型
NEEDS_CHECK=false
CHECK_TYPE=""

# marketplace.json 是技能注册的 source of truth
case "$FILE_PATH" in
  */marketplace.json)
    NEEDS_CHECK=true
    CHECK_TYPE="marketplace"
    ;;
  */hooks.json)
    NEEDS_CHECK=true
    CHECK_TYPE="hooks"
    ;;
esac

# SKILL.md 变更 — 新建或修改技能定义
case "$BASENAME" in
  SKILL.md)
    NEEDS_CHECK=true
    CHECK_TYPE="${CHECK_TYPE:+$CHECK_TYPE,}skill"
    ;;
esac

# 共享脚本变更
case "$FILE_PATH" in
  */scripts/version.sh|*/scripts/context.sh|*/scripts/doc-arch-template.sh)
    NEEDS_CHECK=true
    CHECK_TYPE="${CHECK_TYPE:+$CHECK_TYPE,}scripts"
    ;;
esac

if ! $NEEDS_CHECK; then
  echo '{}'
  exit 0
fi

# === 3. 定位项目根目录 ===
PROJECT_ROOT=""
dir="${PWD}"
while [[ "$dir" != "/" ]]; do
  if [[ -f "$dir/CLAUDE.md" ]] && [[ -f "$dir/.claude-plugin/marketplace.json" ]]; then
    PROJECT_ROOT="$dir"
    break
  fi
  dir="$(dirname "$dir")"
done

if [[ -z "$PROJECT_ROOT" ]]; then
  echo '{}'
  exit 0
fi

# === 4. 执行一致性检查 ===
DRIFT_ITEMS=()

# --- 4a. 技能注册一致性 ---
MARKETPLACE="$PROJECT_ROOT/.claude-plugin/marketplace.json"
SKILLS_DIR="$PROJECT_ROOT/plugins/sns-workflow/skills"

if [[ -f "$MARKETPLACE" ]] && [[ -d "$SKILLS_DIR" ]]; then
  # 从 marketplace.json 提取已注册技能名
  REGISTERED=$(
    python3 -c "
import json, sys
with open('$MARKETPLACE') as f:
    d = json.load(f)
skills = d.get('plugins',[{}])[0].get('skills',[])
names = [s.split('/')[-1] for s in skills]
print('\n'.join(sorted(names)))
" 2>/dev/null || echo ""
  )

  # 从磁盘扫描实际技能目录
  ON_DISK=$(
    ls -1d "$SKILLS_DIR"/*/ 2>/dev/null | while read d; do
      skill_name=$(basename "$d")
      if [[ -f "$SKILLS_DIR/$skill_name/SKILL.md" ]]; then
        echo "$skill_name"
      fi
    done | sort
  )

  # 找出差异
  if [[ -n "$REGISTERED" ]] && [[ -n "$ON_DISK" ]]; then
    # 磁盘有但未注册
    while IFS= read -r skill; do
      if ! echo "$REGISTERED" | grep -qx "$skill"; then
        DRIFT_ITEMS+=("未注册技能: $skill (目录存在但 marketplace.json 中缺失)")
      fi
    done <<< "$ON_DISK"

    # 注册了但磁盘没有
    while IFS= read -r skill; do
      if ! echo "$ON_DISK" | grep -qx "$skill"; then
        DRIFT_ITEMS+=("幽灵注册: $skill (marketplace.json 中有但目录/SKILL.md 不存在)")
      fi
    done <<< "$REGISTERED"
  fi

  REGISTERED_COUNT=$(echo "$REGISTERED" | grep -c . 2>/dev/null || echo "0")
  ON_DISK_COUNT=$(echo "$ON_DISK" | grep -c . 2>/dev/null || echo "0")

  if [[ "$REGISTERED_COUNT" != "$ON_DISK_COUNT" ]] && [[ "$REGISTERED_COUNT" -gt 0 ]]; then
    DRIFT_ITEMS+=("技能数量不一致: marketplace.json=$REGISTERED_COUNT 磁盘=$ON_DISK_COUNT")
  fi

  # --- 4b. CLAUDE.md 技能数量 ---
  CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"
  if [[ -f "$CLAUDE_MD" ]]; then
    CLAUDE_COUNT=$(grep -oE '技能总览（[0-9]+ 个）' "$CLAUDE_MD" 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "")
    CLAUDE_TREE=$(grep -oE '[0-9]+ 个 skill' "$CLAUDE_MD" 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "")

    if [[ -n "$CLAUDE_COUNT" ]] && [[ "$CLAUDE_COUNT" != "$REGISTERED_COUNT" ]]; then
      DRIFT_ITEMS+=("CLAUDE.md 技能数量过时: 声明 $CLAUDE_COUNT 个，实际 $REGISTERED_COUNT 个")
    fi
    if [[ -n "$CLAUDE_TREE" ]] && [[ "$CLAUDE_TREE" != "$REGISTERED_COUNT" ]]; then
      DRIFT_ITEMS+=("CLAUDE.md 目录树技能数量过时: 声明 $CLAUDE_TREE 个，实际 $REGISTERED_COUNT 个")
    fi

    # 检查新技能是否出现在分类表中
    while IFS= read -r skill; do
      if ! grep -q "$skill" "$CLAUDE_MD" 2>/dev/null; then
        DRIFT_ITEMS+=("CLAUDE.md 缺少技能: $skill 未出现在分类表中")
      fi
    done <<< "$ON_DISK"
  fi

  # --- 4c. ARCHITECTURE.md 技能数量 ---
  ARCH_MD="$PROJECT_ROOT/docs/ARCHITECTURE.md"
  if [[ -f "$ARCH_MD" ]]; then
    ARCH_COUNT=$(grep -oE '技能分组（[0-9]+ 个）' "$ARCH_MD" 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "")

    if [[ -n "$ARCH_COUNT" ]] && [[ "$ARCH_COUNT" != "$REGISTERED_COUNT" ]]; then
      DRIFT_ITEMS+=("ARCHITECTURE.md 技能数量过时: 声明 $ARCH_COUNT 个，实际 $REGISTERED_COUNT 个")
    fi

    while IFS= read -r skill; do
      if ! grep -q "$skill" "$ARCH_MD" 2>/dev/null; then
        DRIFT_ITEMS+=("ARCHITECTURE.md 缺少技能: $skill 未出现在分组表中")
      fi
    done <<< "$ON_DISK"
  fi
fi

# === 5. 输出结果 ===
if [[ ${#DRIFT_ITEMS[@]} -eq 0 ]]; then
  echo '{}'
  exit 0
fi

# 构建修复指令
MSG="[doc-garden] 文档同步检测到 ${#DRIFT_ITEMS[@]} 项不一致："
for item in "${DRIFT_ITEMS[@]}"; do
  MSG="$MSG\n  - $item"
done
MSG="$MSG\n\n请执行以下修复："
MSG="$MSG\n  1. 编辑 marketplace.json — 确认技能注册列表完整"
MSG="$MSG\n  2. 编辑 CLAUDE.md — 更新技能数量和分类表"
MSG="$MSG\n  3. 编辑 docs/ARCHITECTURE.md — 更新技能分组和数量"

MSG_ESCAPED=$(printf '%s' "$MSG" | sed 's/"/\\"/g')

printf '{"permissionDecision":"ask","message":"%s"}\n' "$MSG_ESCAPED"
