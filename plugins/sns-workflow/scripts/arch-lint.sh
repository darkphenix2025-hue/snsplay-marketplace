#!/usr/bin/env bash
# arch-lint.sh — 六层架构检查函数库
# 可 source 供 arch-lint skill 和 drift-scanner 共用
set -euo pipefail

# 全局输出变量
ARCH_TYPE_ERRORS=0
ARCH_SCRIPT_ERRORS=0
ARCH_CIRCULAR_ERRORS=0
ARCH_SKILL_ERRORS=0
ARCH_SKILL_WARNINGS=0
ARCH_VIOLATIONS=()

_sns_arch_root() {
  echo "${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}"
}

# 类型层检查: types/ 不应有内部导入
sns_arch_check_types() {
  local ROOT=$(_sns_arch_root)
  ARCH_TYPE_ERRORS=0

  for f in "$ROOT/types/"*.ts; do
    [[ -f "$f" ]] || continue
    local base
    base=$(basename "$f")
    [[ "$base" == *.test.ts ]] && continue

    while IFS= read -r line; do
      local import_path
      import_path=$(echo "$line" | sed -n "s/.*from ['\"]\\.\\///p" | sed "s/['\"].*$//")
      if [[ -n "$import_path" ]]; then
        if [[ "$import_path" == ../types/* ]] || [[ "$import_path" == ./* ]]; then
          local target
          target=$(basename "$import_path")
          if [[ "$base" == "workflow.ts" ]] && [[ "$import_path" == "stage-definitions.ts" ]]; then
            continue
          fi
          ARCH_VIOLATIONS+=("types/$base 不应从 $import_path 导入")
          ARCH_TYPE_ERRORS=$((ARCH_TYPE_ERRORS + 1))
        fi
      fi
    done < <(grep "^import" "$f" 2>/dev/null)
  done

  return 0
}

# 脚本层检查: scripts/ 不应从 skills/ 导入
sns_arch_check_scripts() {
  local ROOT=$(_sns_arch_root)
  ARCH_SCRIPT_ERRORS=0

  for f in "$ROOT/scripts/"*.ts; do
    [[ -f "$f" ]] || continue
    local base
    base=$(basename "$f")
    [[ "$base" == *.test.ts ]] && continue

    while IFS= read -r line; do
      local import_path
      import_path=$(echo "$line" | sed -n "s/.*from ['\"]\\.\\///p" | sed "s/['\"].*$//")
      if [[ -n "$import_path" ]]; then
        if [[ "$import_path" == skills/* ]]; then
          ARCH_VIOLATIONS+=("scripts/$base 不应从 skills/ 导入")
          ARCH_SCRIPT_ERRORS=$((ARCH_SCRIPT_ERRORS + 1))
        fi
      fi
    done < <(grep "^import" "$f" 2>/dev/null)
  done

  return 0
}

# 循环依赖检测: scripts/ 内部 A ↔ B
sns_arch_check_circular() {
  local ROOT=$(_sns_arch_root)
  ARCH_CIRCULAR_ERRORS=0
  local checked=""

  for f in "$ROOT/scripts/"*.ts; do
    [[ -f "$f" ]] || continue
    local base
    base=$(basename "$f")
    [[ "$base" == *.test.ts ]] && continue

    while IFS= read -r line; do
      local import_path
      import_path=$(echo "$line" | sed -n "s/.*from '\\.\\/\\([^']*\\)\\.ts'.*/\\1/p")
      [[ -z "$import_path" ]] && continue

      local target_base
      target_base=$(basename "$import_path")
      [[ "$target_base" == "$base" ]] && continue

      local pair_key="${base}+${target_base}"
      local reverse_key="${target_base}+${base}"
      [[ "$checked" == *"$pair_key"* ]] && continue
      [[ "$checked" == *"$reverse_key"* ]] && continue
      checked="$checked $pair_key"

      local target="$ROOT/scripts/${target_base}.ts"
      [[ -f "$target" ]] || continue

      if grep -q "from.*${base}" "$target" 2>/dev/null; then
        ARCH_VIOLATIONS+=("循环依赖: $base ↔ $target_base")
        ARCH_CIRCULAR_ERRORS=$((ARCH_CIRCULAR_ERRORS + 1))
      fi
    done < <(grep "^import" "$f" 2>/dev/null)
  done

  return 0
}

# 技能层检查: skills/ 不应硬编码路径，不应直接引用 types/
sns_arch_check_skills() {
  local ROOT=$(_sns_arch_root)
  ARCH_SKILL_ERRORS=0
  ARCH_SKILL_WARNINGS=0

  for skill_dir in "$ROOT/skills/"*/; do
    local skill_name
    skill_name=$(basename "$skill_dir")
    local skill_file="$skill_dir/SKILL.md"
    [[ -f "$skill_file" ]] || continue

    local hardcoded
    hardcoded=$(grep -n 'plugins/sns-workflow/scripts\|plugins/sns-workflow/types' "$skill_file" 2>/dev/null | grep -v 'CLAUDE_PLUGIN_ROOT' | grep -v '^#' | grep -v '\${')
    if [[ -n "$hardcoded" ]]; then
      ARCH_VIOLATIONS+=("$skill_name 硬编码路径（应使用 \${CLAUDE_PLUGIN_ROOT}）")
      ARCH_SKILL_ERRORS=$((ARCH_SKILL_ERRORS + 1))
    fi

    local types_access
    types_access=$(grep -c "CLAUDE_PLUGIN_ROOT.*types/" "$skill_file" 2>/dev/null || true)
    types_access=${types_access:-0}
    if [[ "$types_access" -gt 0 ]] && [[ "$skill_name" != "arch-lint" ]]; then
      ARCH_SKILL_WARNINGS=$((ARCH_SKILL_WARNINGS + 1))
    fi
  done

  return 0
}

# 全量检查入口
sns_arch_check() {
  ARCH_VIOLATIONS=()
  sns_arch_check_types
  sns_arch_check_scripts
  sns_arch_check_circular
  sns_arch_check_skills
}

# 获取总错误数
sns_arch_total_errors() {
  echo $((ARCH_TYPE_ERRORS + ARCH_SCRIPT_ERRORS + ARCH_CIRCULAR_ERRORS + ARCH_SKILL_ERRORS))
}

# 计算架构维度评分 (0-100)
sns_arch_score() {
  local total
  total=$(sns_arch_total_errors)
  if [[ "$total" -eq 0 ]]; then
    echo 100
    return
  fi
  local score=100
  # 普通违规 -15/项
  local normal=$((total - ARCH_CIRCULAR_ERRORS))
  score=$((score - normal * 15))
  # 循环依赖额外 -15/项（已包含在 normal 中，追加额外扣分）
  score=$((score - ARCH_CIRCULAR_ERRORS * 15))
  [[ $score -lt 0 ]] && score=0
  echo "$score"
}
