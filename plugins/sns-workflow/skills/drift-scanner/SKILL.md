---
name: sns-workflow:drift-scanner
description: 背景漂移扫描器 — 多维度质量扫描（架构/文档/结构/CI），加权评分 + 基线对比，自动检测退化。PreToolUse hook 在 git commit 前自动触发轻量扫描。
user-invocable: true
allowed-tools: Bash
---

# 背景漂移扫描器

多维度质量扫描：架构 + 文档 + 结构 + CI/质量。加权评分 + 基线对比，自动检测退化趋势。

**前置条件**: `scripts/arch-lint.sh`、`scripts/doc-arch-template.sh` 已就位。

**黄金原则**: 自动加载 `.snsplay/principles.json`（如存在），按 category 路由到对应扫描步骤，自定义 penalty 覆盖默认扣分。

---

## 步骤 0: 加载黄金原则注册表

```bash
PRINCIPLES_FILE="$ROOT/.snsplay/principles.json"
PRINCIPLES_ARCH=()
PRINCIPLES_DOC=()
PRINCIPLES_STRUCT=()
PRINCIPLES_CI=()

if [[ -f "$PRINCIPLES_FILE" ]]; then
  echo "=== 加载黄金原则 ==="

  # 按 category 分类原则
  PRINCIPLE_IDS=$(python3 -c "
import json, sys
with open('$PRINCIPLES_FILE') as f:
    d = json.load(f)
for p in d.get('principles', []):
    print(f\"{p['id']}|{p['category']}|{p.get('severity','warning')}|{p.get('penalty',0)}|{p.get('check','')}\")
" 2>/dev/null || echo "")

  while IFS='|' read -r pid pcat psev ppenalty pcheck; do
    [[ -z "$pid" ]] && continue
    case "$pcat" in
      architecture) PRINCIPLES_ARCH+=("$pid:$ppenalty:$psev") ;;
      documentation) PRINCIPLES_DOC+=("$pid:$ppenalty:$psev") ;;
      structure) PRINCIPLES_STRUCT+=("$pid:$ppenalty:$psev") ;;
      ci_quality|ci) PRINCIPLES_CI+=("$pid:$ppenalty:$psev") ;;
    esac
  done <<< "$PRINCIPLE_IDS"

  total_principles=$(echo "$PRINCIPLE_IDS" | grep -c . 2>/dev/null || echo "0")
  echo "  已加载 $total_principles 条原则 (架构=${#PRINCIPLES_ARCH[@]} 文档=${#PRINCIPLES_DOC[@]} 结构=${#PRINCIPLES_STRUCT[@]} CI=${#PRINCIPLES_CI[@]})"
else
  echo "=== 黄金原则 ==="
  echo "  未找到 .snsplay/principles.json，使用默认扣分规则"
fi
```

---

## 步骤 1: 架构扫描

```bash
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")
SHELL_DIR="$ROOT/plugins/sns-workflow/scripts"
TASK_DIR="$ROOT/.snsplay/task"
mkdir -p "$TASK_DIR"

source "$SHELL_DIR/arch-lint.sh"
sns_arch_check

echo "=== 架构扫描 ==="
echo "  类型层违规: $ARCH_TYPE_ERRORS"
echo "  脚本层违规: $ARCH_SCRIPT_ERRORS"
echo "  循环依赖:   $ARCH_CIRCULAR_ERRORS"
echo "  技能层违规: $ARCH_SKILL_ERRORS"
echo "  技能层警告: $ARCH_SKILL_WARNINGS"

arch_score=$(sns_arch_score)
echo "  架构评分: $arch_score / 100"
```

---

## 步骤 2: 文档扫描

```bash
source "$SHELL_DIR/doc-arch-template.sh"

echo ""
echo "=== 文档扫描 ==="

doc_issues=()
doc_score=100

# CLAUDE.md 行数检查
CLAUDE_MD="$ROOT/CLAUDE.md"
if [[ -f "$CLAUDE_MD" ]]; then
  cl_lines=$(wc -l < "$CLAUDE_MD")
  if [[ "$cl_lines" -gt 150 ]]; then
    doc_issues+=("CLAUDE.md 超限: ${cl_lines}/150 行")
    doc_score=$((doc_score - 20))
  fi
  if ! grep -q "文档地图\|docs/" "$CLAUDE_MD" 2>/dev/null; then
    doc_issues+=("CLAUDE.md 缺少文档地图索引")
    doc_score=$((doc_score - 10))
  fi
fi

# docs/ 完整性
DOC_CHECK_OUTPUT=$(sns_doc_check --report 2>&1) || true
if echo "$DOC_CHECK_OUTPUT" | grep -q "缺失"; then
  missing_count=$(echo "$DOC_CHECK_OUTPUT" | grep -c "缺失" 2>/dev/null || echo "0")
  doc_issues+=("docs/ 缺失文件: $missing_count 个")
  doc_score=$((doc_score - missing_count * 10))
fi

# 注册一致性（复用 remind hook 逻辑）
MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
SKILLS_DIR="$ROOT/plugins/sns-workflow/skills"
if [[ -f "$MARKETPLACE" ]] && [[ -d "$SKILLS_DIR" ]]; then
  REGISTERED=$(python3 -c "
import json, sys
with open('$MARKETPLACE') as f:
    d = json.load(f)
skills = d.get('plugins',[{}])[0].get('skills',[])
names = [s.split('/')[-1] for s in skills]
print('\n'.join(sorted(names)))
" 2>/dev/null || echo "")

  ON_DISK=$(ls -1d "$SKILLS_DIR"/*/ 2>/dev/null | while read d; do
    skill_name=$(basename "$d")
    [[ -f "$SKILLS_DIR/$skill_name/SKILL.md" ]] && echo "$skill_name"
  done | sort)

  unregistered=0
  ghost=0
  while IFS= read -r skill; do
    [[ -z "$skill" ]] && continue
    echo "$REGISTERED" | grep -qx "$skill" || unregistered=$((unregistered + 1))
  done <<< "$ON_DISK"

  while IFS= read -r skill; do
    [[ -z "$skill" ]] && continue
    echo "$ON_DISK" | grep -qx "$skill" || ghost=$((ghost + 1))
  done <<< "$REGISTERED"

  if [[ "$unregistered" -gt 0 ]]; then
    doc_issues+=("未注册技能: $unregistered 个")
    doc_score=$((doc_score - unregistered * 20))
  fi
  if [[ "$ghost" -gt 0 ]]; then
    doc_issues+=("幽灵注册: $ghost 个")
    doc_score=$((doc_score - ghost * 20))
  fi
fi

[[ $doc_score -lt 0 ]] && doc_score=0
echo "  文档评分: $doc_score / 100"
for item in "${doc_issues[@]+"${doc_issues[@]}"}"; do
  echo "  ⚠ $item"
done
```

---

## 步骤 3: 结构扫描

```bash
echo ""
echo "=== 结构扫描 ==="

struct_issues=()
struct_score=100

# marketplace.json skills 数组 vs 磁盘 skills/*/SKILL.md 双向对比
if [[ -f "$MARKETPLACE" ]] && [[ -d "$SKILLS_DIR" ]]; then
  reg_count=$(echo "$REGISTERED" | grep -c . 2>/dev/null || echo "0")
  disk_count=$(echo "$ON_DISK" | grep -c . 2>/dev/null || echo "0")

  echo "  已注册: $reg_count | 磁盘: $disk_count"

  if [[ "$reg_count" -ne "$disk_count" ]]; then
    struct_issues+=("数量不一致: 注册=$reg_count 磁盘=$disk_count")
    struct_score=$((struct_score - 20))
  fi

  # 检查 ARCHITECTURE.md 计数
  ARCH_MD="$ROOT/docs/ARCHITECTURE.md"
  if [[ -f "$ARCH_MD" ]]; then
    arch_count=$(grep -oE '技能分组（[0-9]+ 个）' "$ARCH_MD" 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "")
    if [[ -n "$arch_count" ]] && [[ "$arch_count" != "$reg_count" ]]; then
      struct_issues+=("ARCHITECTURE.md 计数过时: $arch_count ≠ $reg_count")
      struct_score=$((struct_score - 15))
    fi
  fi

  # 检查 CLAUDE.md 计数
  if [[ -f "$CLAUDE_MD" ]]; then
    claude_count=$(grep -oE '技能总览（[0-9]+ 个）' "$CLAUDE_MD" 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "")
    if [[ -n "$claude_count" ]] && [[ "$claude_count" != "$reg_count" ]]; then
      struct_issues+=("CLAUDE.md 计数过时: $claude_count ≠ $reg_count")
      struct_score=$((struct_score - 15))
    fi
  fi
fi

[[ $struct_score -lt 0 ]] && struct_score=0
echo "  结构评分: $struct_score / 100"
for item in "${struct_issues[@]+"${struct_issues[@]}"}"; do
  echo "  ⚠ $item"
done
```

---

## 步骤 4: CI/质量扫描

```bash
echo ""
echo "=== CI/质量扫描 ==="

ci_issues=()
ci_score=100

# 从 impl-result.json 读取测试通过率
if [[ -f "$TASK_DIR/impl-result.json" ]]; then
  test_pass=$(grep -o '"tests_passed"[[:space:]]*:[[:space:]]*[0-9]*' "$TASK_DIR/impl-result.json" | head -1 | sed 's/.*://' || echo "")
  test_fail=$(grep -o '"tests_failed"[[:space:]]*:[[:space:]]*[0-9]*' "$TASK_DIR/impl-result.json" | head -1 | sed 's/.*://' || echo "")

  if [[ -n "$test_pass" ]] && [[ -n "$test_fail" ]]; then
    total=$((test_pass + test_fail))
    if [[ "$total" -gt 0 ]]; then
      fail_rate=$((test_fail * 100 / total))
      echo "  测试: $test_pass 通过 / $test_fail 失败 (${fail_rate}% 失败率)"
      if [[ "$fail_rate" -gt 10 ]]; then
        ci_issues+=("测试失败率过高: ${fail_rate}%")
        ci_score=$((ci_score - 30))
      fi
    fi
  fi

  impl_status=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$TASK_DIR/impl-result.json" | head -1 | sed 's/.*:"//;s/"$//')
  if [[ "$impl_status" == "failed" ]]; then
    ci_issues+=("实现结果: failed")
    ci_score=$((ci_score - 20))
  fi
fi

# gh pr checks（可选，无 gh 时跳过）
if command -v gh &>/dev/null; then
  latest_pr=$(gh pr list --base main --state open --json number --limit 1 2>/dev/null | jq -r '.[0].number // empty' 2>/dev/null || echo "")
  if [[ -n "$latest_pr" ]]; then
    pr_fail=$(gh pr checks "$latest_pr" --json state 2>/dev/null | jq '[.[] | select(.state == "FAILURE" or .state == "ERROR")] | length' 2>/dev/null || echo "0")
    if [[ "$pr_fail" -gt 0 ]] 2>/dev/null; then
      ci_issues+=("PR #$latest_pr CI 失败: $pr_fail 项")
      ci_score=$((ci_score - pr_fail * 20))
    else
      echo "  PR #$latest_pr: CI 通过"
    fi
  fi
fi

[[ $ci_score -lt 0 ]] && ci_score=0
echo "  CI/质量评分: $ci_score / 100"
for item in "${ci_issues[@]+"${ci_issues[@]}"}"; do
  echo "  ⚠ $item"
done
```

---

## 步骤 5: 评分 + 基线对比

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# 加权总分: 架构30% + 文档20% + 结构20% + CI/质量30%
total_score=$(( (arch_score * 30 + doc_score * 20 + struct_score * 20 + ci_score * 30) / 100 ))

# 等级判定
if [[ "$total_score" -ge 90 ]]; then
  grade="A"
elif [[ "$total_score" -ge 75 ]]; then
  grade="B"
elif [[ "$total_score" -ge 60 ]]; then
  grade="C"
else
  grade="D"
fi

# 基线对比
BASELINE="$TASK_DIR/drift-baseline.json"
trend="new"
prev_score=""
prev_grade=""
if [[ -f "$BASELINE" ]]; then
  prev_score=$(grep -o '"total_score"[[:space:]]*:[[:space:]]*[0-9]*' "$BASELINE" | head -1 | sed 's/.*://' || echo "")
  prev_grade=$(grep -o '"grade"[[:space:]]*:[[:space:]]*"[^"]*"' "$BASELINE" | head -1 | sed 's/.*:"//;s/"$//' || echo "")

  if [[ -n "$prev_score" ]]; then
    delta=$((total_score - prev_score))
    if [[ "$delta" -gt 3 ]]; then
      trend="improving"
    elif [[ "$delta" -lt -3 ]]; then
      trend="degrading"
    else
      trend="stable"
    fi
  fi
fi

echo ""
echo "=== 扫描评分 ==="
echo "  架构:   $arch_score / 100 (权重 30%)"
echo "  文档:   $doc_score / 100 (权重 20%)"
echo "  结构:   $struct_score / 100 (权重 20%)"
echo "  CI/质量: $ci_score / 100 (权重 30%)"
echo ""
echo "  总分: $total_score / 100"
echo "  等级: $grade"
echo "  趋势: $trend"
if [[ -n "$prev_score" ]]; then
  echo "  上次: $prev_score / 100 ($prev_grade)"
  echo "  变化: $((delta > 0 ? delta : 0 > -delta ? delta : -delta >= 0 ? "↑$delta" : "↓$((-delta))"))"
fi
```

---

## 步骤 6: 输出报告 + 写入产物

```bash
echo ""
echo "=== 漂移项 ==="

# 收集所有漂移项
ALL_DRIFT_ITEMS=""

# 架构漂移
if [[ "${#ARCH_VIOLATIONS[@]}" -gt 0 ]]; then
  for v in "${ARCH_VIOLATIONS[@]}"; do
    echo "  ⚠ 架构: $v"
    ALL_DRIFT_ITEMS="$ALL_DRIFT_ITEMS{\"dimension\":\"architecture\",\"severity\":\"critical\",\"description\":\"$v\"},"
  done
fi

# 文档漂移
for item in "${doc_issues[@]+"${doc_issues[@]}"}"; do
  echo "  ⚠ 文档: $item"
  ALL_DRIFT_ITEMS="$ALL_DRIFT_ITEMS{\"dimension\":\"documentation\",\"severity\":\"warning\",\"description\":\"$item\"},"
done

# 结构漂移
for item in "${struct_issues[@]+"${struct_issues[@]}"}"; do
  echo "  ⚠ 结构: $item"
  ALL_DRIFT_ITEMS="$ALL_DRIFT_ITEMS{\"dimension\":\"structure\",\"severity\":\"critical\",\"description\":\"$item\"},"
done

# CI 漂移
for item in "${ci_issues[@]+"${ci_issues[@]}"}"; do
  echo "  ⚠ CI: $item"
  ALL_DRIFT_ITEMS="$ALL_DRIFT_ITEMS{\"dimension\":\"ci_quality\",\"severity\":\"critical\",\"description\":\"$item\"},"
done

# 去掉末尾逗号
ALL_DRIFT_ITEMS="${ALL_DRIFT_ITEMS%,}"

# 写入 artifact
TIMESTAMP_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$TASK_DIR/drift-scan-${TIMESTAMP}.json" <<ENDJSON
{
  "id": "drift-scan-${TIMESTAMP}",
  "timestamp": "$TIMESTAMP_ISO",
  "scores": {
    "architecture": {"score": $arch_score, "violations": $(sns_arch_total_errors), "weight": 0.30},
    "documentation": {"score": $doc_score, "issues": ${#doc_issues[@]+"${#doc_issues[@]}"}, "weight": 0.20},
    "structure": {"score": $struct_score, "mismatches": ${#struct_issues[@]+"${#struct_issues[@]}"}, "weight": 0.20},
    "ci_quality": {"score": $ci_score, "failures": ${#ci_issues[@]+"${#ci_issues[@]}"}, "weight": 0.30}
  },
  "total_score": $total_score,
  "grade": "$grade",
  "trend": "$trend",
  "drift_items": [$ALL_DRIFT_ITEMS],
  "baseline": {
    "total_score": ${prev_score:-0},
    "grade": "${prev_grade:-none}",
    "timestamp": "$(grep -o '"timestamp"[[:space:]]*:[[:space:]]*"[^"]*"' "$BASELINE" 2>/dev/null | head -1 | sed 's/.*:"//;s/"$//' || echo "")"
  }
}
ENDJSON

# 更新基线
cat > "$TASK_DIR/drift-baseline.json" <<ENDJSON
{
  "id": "drift-scan-${TIMESTAMP}",
  "timestamp": "$TIMESTAMP_ISO",
  "total_score": $total_score,
  "grade": "$grade"
}
ENDJSON

ARTIFACT="$TASK_DIR/drift-scan-${TIMESTAMP}.json"
echo ""
echo "=== drift-scanner 完成 ==="
echo "Artifact: $ARTIFACT"
echo "基线: $BASELINE"
```
