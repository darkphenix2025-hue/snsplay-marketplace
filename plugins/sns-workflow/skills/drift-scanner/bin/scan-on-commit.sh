#!/usr/bin/env bash
# scan-on-commit.sh — PreToolUse hook for drift-scanner skill
# git commit 前自动执行轻量漂移扫描（架构 + 文档 + 结构，跳过 CI）
# 总分 < 60 (D 级) 时阻止提交
set -euo pipefail

# === 1. 读取 stdin，检查是否为 git commit ===
INPUT=$(cat)

COMMAND=$(printf '%s' "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' || true)

if [ -z "$COMMAND" ]; then
  COMMAND=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("tool_input",{}).get("command",""))' 2>/dev/null || true)
fi

# 仅在 git commit 时触发
if [[ -z "$COMMAND" ]] || ! echo "$COMMAND" | grep -q 'git commit'; then
  echo '{}'
  exit 0
fi

# === 2. 定位项目根目录 ===
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

SHELL_DIR="$PROJECT_ROOT/plugins/sns-workflow/scripts"

# === 3. 架构扫描 ===
arch_score=100
arch_violations=0

if [[ -f "$SHELL_DIR/arch-lint.sh" ]]; then
  source "$SHELL_DIR/arch-lint.sh"
  sns_arch_check 2>/dev/null || true
  arch_violations=$(sns_arch_total_errors)
  arch_score=$(sns_arch_score)
fi

# === 4. 文档扫描 ===
doc_score=100
doc_issues=0

# CLAUDE.md 行数
CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"
if [[ -f "$CLAUDE_MD" ]]; then
  cl_lines=$(wc -l < "$CLAUDE_MD")
  if [[ "$cl_lines" -gt 150 ]]; then
    doc_score=$((doc_score - 20))
    doc_issues=$((doc_issues + 1))
  fi
fi

# docs/ 完整性
if [[ -f "$SHELL_DIR/doc-arch-template.sh" ]]; then
  source "$SHELL_DIR/doc-arch-template.sh"
  if ! sns_doc_check --quiet 2>/dev/null; then
    doc_score=$((doc_score - 30))
    doc_issues=$((doc_issues + 1))
  fi
fi

# === 5. 结构扫描 ===
struct_score=100
struct_issues=0

MARKETPLACE="$PROJECT_ROOT/.claude-plugin/marketplace.json"
SKILLS_DIR="$PROJECT_ROOT/plugins/sns-workflow/skills"

if [[ -f "$MARKETPLACE" ]] && [[ -d "$SKILLS_DIR" ]]; then
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

  ON_DISK=$(
    ls -1d "$SKILLS_DIR"/*/ 2>/dev/null | while read d; do
      skill_name=$(basename "$d")
      [[ -f "$SKILLS_DIR/$skill_name/SKILL.md" ]] && echo "$skill_name"
    done | sort
  )

  while IFS= read -r skill; do
    [[ -z "$skill" ]] && continue
    if ! echo "$REGISTERED" | grep -qx "$skill"; then
      struct_score=$((struct_score - 20))
      struct_issues=$((struct_issues + 1))
    fi
  done <<< "$ON_DISK"

  while IFS= read -r skill; do
    [[ -z "$skill" ]] && continue
    if ! echo "$ON_DISK" | grep -qx "$skill"; then
      struct_score=$((struct_score - 20))
      struct_issues=$((struct_issues + 1))
    fi
  done <<< "$REGISTERED"
fi

# === 6. 计算总分（跳过 CI 维度，CI 权重 30% 分配给其他三项）===
# 调整权重: 架构 40% + 文档 30% + 结构 30%
total_score=$(( (arch_score * 40 + doc_score * 30 + struct_score * 30) / 100 ))

[[ $total_score -lt 0 ]] && total_score=0
[[ $arch_score -lt 0 ]] && arch_score=0
[[ $doc_score -lt 0 ]] && doc_score=0
[[ $struct_score -lt 0 ]] && struct_score=0

# === 7. 判定 ===
if [[ "$total_score" -ge 60 ]]; then
  echo '{}'
  exit 0
fi

# D 级: 阻止提交
grade="D"
[[ "$total_score" -ge 60 ]] && grade="C"
[[ "$total_score" -ge 75 ]] && grade="B"
[[ "$total_score" -ge 90 ]] && grade="A"

MSG="[drift-scanner] 代码质量评分 ${grade} (${total_score}/100)，建议修复后再提交："
MSG="$MSG\\n  架构: ${arch_score}/100 (违规 ${arch_violations} 项)"
MSG="$MSG\\n  文档: ${doc_score}/100 (问题 ${doc_issues} 项)"
MSG="$MSG\\n  结构: ${struct_score}/100 (不一致 ${struct_issues} 项)"
MSG="$MSG\\n\\n修复建议:"
MSG="$MSG\\n  运行 /sns-workflow:drift-scanner 查看详细报告"
MSG="$MSG\\n  运行 /sns-workflow:arch-lint 检查架构违规"
MSG="$MSG\\n  运行 /sns-workflow:doc-garden --fix 修复文档问题"

MSG_ESCAPED=$(printf '%s' "$MSG" | sed 's/"/\\"/g')

printf '{"permissionDecision":"ask","message":"%s"}\n' "$MSG_ESCAPED"
