---
name: sns-workflow:arch-lint
description: 架构强制检查 —— 检测 sns-workflow 插件的跨层违规、循环依赖、非法导入。强制执行六层架构模型（types → scripts → stages → system-prompts → skills）。
user-invocable: true
allowed-tools: Bash
---

# 架构强制检查

通过静态分析强制六层架构的依赖规则。每次提交前检查代码分层是否被破坏。

**六层架构**:

| 层级 | 目录 | 允许导入 |
|------|------|---------|
| 1. Types | `types/` | 无（纯类型定义，零业务依赖） |
| 2. Scripts | `scripts/` | types/ + 标准库 + 同级脚本 |
| 3. Tests | `scripts/__tests__/` | 同级脚本 + types/ |
| 4. Stages | `stages/` | 只读，无导入 |
| 5. Prompts | `system-prompts/built-in/` | 只读，无导入 |
| 6. Skills | `skills/` | 运行时通过 `${CLAUDE_PLUGIN_ROOT}` 引用 scripts/ |

---

## 步骤 1: 验证环境

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/skill-logger.sh"
sns_skill_start "arch-lint" "$*"

ROOT="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}"

if [[ ! -d "$ROOT/types" ]] || [[ ! -d "$ROOT/scripts" ]]; then
  echo "错误: $ROOT 不是 sns-workflow 插件根目录"
  exit 1
fi

echo "=== arch-lint: $ROOT ==="
echo ""
```

---

## 步骤 2: 运行类型层检查

```bash
ROOT="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}"
ERRORS=0

echo "--- 类型层检查 (types/) ---"

for f in "$ROOT/types/"*.ts; do
  [[ -f "$f" ]] || continue
  base=$(basename "$f")

  # 排除测试文件
  [[ "$base" == *.test.ts ]] && continue

  # types/ 文件只能导入标准库类型和 stage-definitions.ts（workflow.ts 的特例）
  # 禁止从其他 types/ 模块导入（presets.ts 和 chatroom.ts 必须零导入）
  while IFS= read -r line; do
    # 提取 import from 路径
    import_path=$(echo "$line" | sed -n "s/.*from ['\"]\\.\\///p" | sed "s/['\"].*$//")
    if [[ -n "$import_path" ]]; then
      # 检查是否是类型导入且目标在 types/ 中
      if [[ "$import_path" == ../types/* ]] || [[ "$import_path" == ./* ]]; then
        target=$(basename "$import_path")
        # workflow.ts 唯一允许导入 stage-definitions.ts
        if [[ "$base" == "workflow.ts" ]] && [[ "$import_path" == "stage-definitions.ts" ]]; then
          continue
        fi
        echo "  违规: $base 不应从 $import_path 导入"
        ERRORS=$((ERRORS + 1))
      fi
    fi
  done < <(grep "^import" "$f" 2>/dev/null)
done

if [[ "$ERRORS" -eq 0 ]]; then
  echo "  ✓ 类型层合规"
else
  echo "  ✗ $ERRORS 项违规"
fi

echo ""
```

---

## 步骤 3: 运行脚本层检查

```bash
ROOT="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}"
SCRIPT_ERRORS=0

echo "--- 脚本层检查 (scripts/) ---"

for f in "$ROOT/scripts/"*.ts; do
  [[ -f "$f" ]] || continue
  base=$(basename "$f")

  # 排除测试文件
  [[ "$base" == *.test.ts ]] && continue

  # scripts/ 允许导入: 标准库, ../types/, 同级脚本
  # 禁止: 反向导入 scripts/（业务逻辑侵入 types/）
  # 检查所有 import 路径
  while IFS= read -r line; do
    import_path=$(echo "$line" | sed -n "s/.*from ['\"]\\.\\///p" | sed "s/['\"].*$//")
    if [[ -n "$import_path" ]]; then
      # 禁止 scripts/ 文件被 types/ 反向引用（类型层不依赖业务逻辑）
      # 禁止 skills/ 直接引用 types/（应通过 scripts/ 访问）
      if [[ "$import_path" == skills/* ]]; then
        echo "  违规: $base 不应从 skills/ 导入"
        SCRIPT_ERRORS=$((SCRIPT_ERRORS + 1))
      fi
    fi
  done < <(grep "^import" "$f" 2>/dev/null)
done

if [[ "$SCRIPT_ERRORS" -eq 0 ]]; then
  echo "  ✓ 脚本层合规"
else
  echo "  ✗ $SCRIPT_ERRORS 项违规"
fi

echo ""
```

---

## 步骤 4: 循环依赖检测

```bash
ROOT="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}"
CIRCULAR_ERRORS=0

echo "--- 循环依赖检测 ---"

# 构建导入图，检测 A → B → A 形式的循环
# 对每个 scripts/ 文件，追踪其导入链
check_circular() {
  local from_file="$1"
  local to_file="$2"
  local from_base to_base

  from_base=$(basename "$from_file")
  to_base=$(basename "$to_file")

  # to_file 是否反向导入了 from_file？
  if grep -q "from.*['\"].*/${from_base}" "$to_file" 2>/dev/null; then
    echo "  循环依赖: $from_base ↔ $to_base"
    return 1
  fi
  return 0
}

# 检查脚本间的循环依赖
scripts_files=("$ROOT/scripts/"*.ts)
checked=""

for f in "${scripts_files[@]}"; do
  base=$(basename "$f")
  [[ "$base" == *.test.ts ]] && continue

  # 找出 f 导入的所有同级脚本
  while IFS= read -r import_path; do
    [[ -z "$import_path" ]] && continue
    target_base=$(basename "$import_path" | sed 's/\.ts$//')
    target="$ROOT/scripts/${target_base}.ts"

    [[ -f "$target" ]] || continue

    pair_key="${base}+${target_base}"
    reverse_key="${target_base}+${base}"

    # 避免重复检查 A-B 和 B-A
    [[ "$checked" == *"$pair_key"* ]] && continue
    [[ "$checked" == *"$reverse_key"* ]] && continue
    checked="$checked $pair_key"

    if ! check_circular "$f" "$target"; then
      CIRCULAR_ERRORS=$((CIRCULAR_ERRORS + 1))
    fi
  done < <(grep "^import" "$f" 2>/dev/null | sed -n "s/.*from ['\"]\\.\\/.\\+\\.\\(['-]*\\)/\\.\\1/p" | sed "s/['\"].*$//" | sed 's/^\\.\\///')
  # 更精确的方式：重新解析
done

# 使用更直接的方法重新检查
for f in "${scripts_files[@]}"; do
  [[ -f "$f" ]] || continue
  base=$(basename "$f")
  [[ "$base" == *.test.ts ]] && continue

  while IFS= read -r line; do
    import_path=$(echo "$line" | sed -n "s/.*from '\\.\\/\\([^']*\\)\\.ts'.*/\\1/p")
    [[ -z "$import_path" ]] && continue

    target_base=$(basename "$import_path")
    [[ "$target_base" == "$base" ]] && continue

    target="$ROOT/scripts/${target_base}.ts"
    [[ -f "$target" ]] || continue

    if grep -q "from.*${base}" "$target" 2>/dev/null; then
      echo "  循环依赖: $base ↔ $target_base"
      CIRCULAR_ERRORS=$((CIRCULAR_ERRORS + 1))
    fi
  done < <(grep "^import" "$f" 2>/dev/null)
done

if [[ "$CIRCULAR_ERRORS" -eq 0 ]]; then
  echo "  ✓ 无循环依赖"
else
  echo "  ✗ 发现 $CIRCULAR_ERRORS 个循环"
fi

echo ""
```

---

## 步骤 5: 技能层引用检查

```bash
ROOT="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}"
SKILL_ERRORS=0

echo "--- 技能层引用检查 (skills/) ---"

# skills/ 通过 SKILL.md 中的 bun 命令引用 scripts/
# 检查是否通过 CLAUDE_PLUGIN_ROOT 变量引用（不硬编码路径）
# 检查是否直接引用 types/（应通过 scripts/ 访问类型）

SKILL_WARNINGS=0

for skill_dir in "$ROOT/skills/"*/; do
  skill_name=$(basename "$skill_dir")
  skill_file="$skill_dir/SKILL.md"
  [[ -f "$skill_file" ]] || continue

  # 检查是否硬编码了 plugins/sns-workflow 路径（应使用变量）
  hardcoded=$(grep -n 'plugins/sns-workflow/scripts\|plugins/sns-workflow/types' "$skill_file" 2>/dev/null | grep -v 'CLAUDE_PLUGIN_ROOT' | grep -v '^#' | grep -v '\${')
  if [[ -n "$hardcoded" ]]; then
    echo "  违规: $skill_name 硬编码路径（应使用 \${CLAUDE_PLUGIN_ROOT}）"
    echo "    行: $hardcoded"
    SKILL_ERRORS=$((SKILL_ERRORS + 1))
  fi

  # 检查是否直接引用 types/（越层访问 — 降级为警告）
  # 排除 arch-lint 自身（其检测代码包含 types/ 字符串）
  types_access=$(grep -c "CLAUDE_PLUGIN_ROOT.*types/" "$skill_file" 2>/dev/null || echo "0")
  if [[ "$types_access" -gt 0 ]] && [[ "$skill_name" != "arch-lint" ]]; then
    echo "  警告: $skill_name 直接引用 types/（建议通过 scripts/ 导出类型）"
    SKILL_WARNINGS=$((SKILL_WARNINGS + 1))
  fi
done

if [[ "$SKILL_ERRORS" -eq 0 ]]; then
  echo "  ✓ 技能层引用合规"
else
  echo "  ✗ $SKILL_ERRORS 项违规"
fi
if [[ "$SKILL_WARNINGS" -gt 0 ]]; then
  echo "  ⚠ $SKILL_WARNINGS 项警告（直接引用 types/）"
fi

echo ""
```

---

## 步骤 6: 输出汇总报告

```bash
echo ""
echo "=== arch-lint 汇总 ==="

TOTAL=$((ERRORS + SCRIPT_ERRORS + CIRCULAR_ERRORS + SKILL_ERRORS))
if [[ "$TOTAL" -eq 0 ]]; then
  echo "状态: ✓ 架构合规"
  echo "  类型层:    ✓"
  echo "  脚本层:    ✓"
  echo "  循环依赖:  ✓"
  echo "  技能层:    ✓"
  if [[ "$SKILL_WARNINGS" -gt 0 ]]; then
    echo ""
    echo "警告: $SKILL_WARNINGS 项类型层降级引用（建议修复）"
  fi
else
  echo "状态: ✗ 发现 $TOTAL 项违规"
  [[ "$ERRORS" -gt 0 ]] && echo "  类型层违规: $ERRORS"
  [[ "$SCRIPT_ERRORS" -gt 0 ]] && echo "  脚本层违规: $SCRIPT_ERRORS"
  [[ "$CIRCULAR_ERRORS" -gt 0 ]] && echo "  循环依赖: $CIRCULAR_ERRORS"
  [[ "$SKILL_ERRORS" -gt 0 ]] && echo "  技能层违规: $SKILL_ERRORS"
  [[ "$SKILL_WARNINGS" -gt 0 ]] && echo "  技能层警告: $SKILL_WARNINGS"
  sns_skill_error "arch violations: $TOTAL"
  sns_skill_end "failed" "$TOTAL violations"
  exit 1
fi
sns_skill_end "success" "0 violations"
```
