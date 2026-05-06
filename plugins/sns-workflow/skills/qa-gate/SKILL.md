---
name: sns-workflow:qa-gate
description: 质量门禁 —— 综合审查结果、UI 验证、架构评分、AC 覆盖度，输出统一 pass/fail 结论。--auto 模式驱动自主修复循环。
user-invocable: true
allowed-tools: Bash, Read, Write, Grep, Glob, AskUserQuestion
---

# 质量门禁（Quality Gate）

将 plan 的 acceptance criteria、review 的审查结果、ui-verify 的验证结果、drift-scanner 的架构评分综合为一个 pass/fail 结论。`--auto` 模式下驱动"检测 → 修复 → 再验证"自主循环。

**用法**:
- `qa-gate` — 评估当前任务质量，输出 pass/fail
- `qa-gate --auto` — 自动修复 blocker 直到通过或达到最大轮次
- `qa-gate --max-rounds 5` — 自定义最大修复轮次（默认 3）
- `qa-gate --threshold 90` — 自定义通过阈值（默认 85）

**数据源**: `.snsplay/task/` 下所有产物文件

**产物**: `.snsplay/task/qa-gate-${TIMESTAMP}.json`

---

## 步骤 1: 收集任务上下文

从 `.snsplay/task/` 收集所有相关产物，构建验证输入。

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/context.sh"

current_branch=$(git branch --show-current)
branch_type=$(sns_branch_type)
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")
TASK_DIR="$ROOT/.snsplay/task"

# 解析参数
AUTO_MODE=false
MAX_ROUNDS=3
THRESHOLD=85

for arg in "$@"; do
  case "$arg" in
    --auto) AUTO_MODE=true ;;
    --max-rounds) NEXT_IS_ROUNDS=true ;;
    --threshold) NEXT_IS_THRESHOLD=true ;;
    *)
      [[ "$NEXT_IS_ROUNDS" == "true" ]] && MAX_ROUNDS="$arg" && NEXT_IS_ROUNDS=false
      [[ "$NEXT_IS_THRESHOLD" == "true" ]] && THRESHOLD="$arg" && NEXT_IS_THRESHOLD=false
      ;;
  esac
done

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
GATE_ID="qa-gate-${TIMESTAMP}"
```

### 收集 Plan 产物

```bash
PLAN_FILE=""
PLAN_ID=""
ACCEPTANCE_CRITERIA="[]"

# 查找最新的 plan 文件
latest_plan=$(ls -t "$TASK_DIR"/plan-*.json 2>/dev/null | head -1)
if [[ -n "$latest_plan" ]]; then
  PLAN_FILE="$latest_plan"
  PLAN_ID=$(python3 -c "
import json
with open('$latest_plan') as f: d = json.load(f)
print(d.get('id', ''))
" 2>/dev/null)
  ACCEPTANCE_CRITERIA=$(python3 -c "
import json
with open('$latest_plan') as f: d = json.load(f)
print(json.dumps(d.get('acceptance_criteria', [])))
" 2>/dev/null)
  echo "Plan: $PLAN_ID"
  echo "Acceptance Criteria: $ACCEPTANCE_CRITERIA"
else
  echo "警告: 未找到 plan 产物，AC 验证维度将标记为 N/A"
fi
```

### 收集 Review 产物

```bash
REVIEW_FILE=""
REVIEW_STATUS=""
REVIEW_MUST_FIX=0
REVIEW_ADVISORY=0

latest_review=$(ls -t "$TASK_DIR"/review-*.json 2>/dev/null | grep -v "round" | head -1)
if [[ -n "$latest_review" ]]; then
  REVIEW_FILE="$latest_review"
  REVIEW_STATUS=$(python3 -c "
import json
with open('$latest_review') as f: d = json.load(f)
synthesis = d.get('synthesis', {})
print(synthesis.get('overall_status', 'unknown'))
" 2>/dev/null)
  REVIEW_MUST_FIX=$(python3 -c "
import json
with open('$latest_review') as f: d = json.load(f)
synthesis = d.get('synthesis', {})
print(len(synthesis.get('must_fix', [])))
" 2>/dev/null)
  REVIEW_ADVISORY=$(python3 -c "
import json
with open('$latest_review') as f: d = json.load(f)
synthesis = d.get('synthesis', {})
print(len(synthesis.get('advisory', [])))
" 2>/dev/null)
  echo "Review: $REVIEW_STATUS (must_fix=$REVIEW_MUST_FIX, advisory=$REVIEW_ADVISORY)"
else
  echo "警告: 未找到 review 产物，审查维度将标记为 N/A"
fi
```

### 收集 UI Verify 产物

```bash
UI_VERIFY_FILE=""
UI_SEVERITY=""
UI_CHANGES=0

latest_ui=$(ls -t "$TASK_DIR"/ui-verify-*.json 2>/dev/null | grep -v baseline | head -1)
if [[ -n "$latest_ui" ]]; then
  UI_VERIFY_FILE="$latest_ui"
  UI_SEVERITY=$(python3 -c "
import json
with open('$latest_ui') as f: d = json.load(f)
print(d.get('diff_analysis', {}).get('severity', 'none'))
" 2>/dev/null)
  UI_CHANGES=$(python3 -c "
import json
with open('$latest_ui') as f: d = json.load(f)
diff = d.get('diff_analysis', {})
total = diff.get('nodes_added', 0) + diff.get('nodes_deleted', 0) + diff.get('text_changes', 0) + diff.get('attribute_changes', 0)
print(total)
" 2>/dev/null)
  echo "UI Verify: severity=$UI_SEVERITY, changes=$UI_CHANGES"
else
  echo "提示: 未找到 ui-verify 产物，UI 维度将标记为 N/A（非阻断）"
fi
```

### 收集 Drift Baseline

```bash
DRIFT_GRADE=""
DRIFT_SCORE=0
DRIFT_TREND=""

baseline_file="$TASK_DIR/drift-baseline.json"
if [[ -f "$baseline_file" ]]; then
  DRIFT_GRADE=$(python3 -c "
import json
with open('$baseline_file') as f: d = json.load(f)
print(d.get('grade', ''))
" 2>/dev/null)
  DRIFT_SCORE=$(python3 -c "
import json
with open('$baseline_file') as f: d = json.load(f)
print(d.get('total_score', 0))
" 2>/dev/null)
  DRIFT_TREND=$(python3 -c "
import json
with open('$baseline_file') as f: d = json.load(f)
print(d.get('trend', 'new'))
" 2>/dev/null)
  echo "Drift: grade=$DRIFT_GRADE, score=$DRIFT_SCORE, trend=$DRIFT_TREND"
else
  echo "提示: 未找到 drift baseline，架构维度将标记为 N/A（非阻断）"
fi
```

### 收集 Git 变更

```bash
DIFF_STAT=$(git diff --stat 2>/dev/null)
DIFF_CACHED_STAT=$(git diff --cached --stat 2>/dev/null)
CHANGED_FILES=$(git diff --name-only HEAD 2>/dev/null; git diff --cached --name-only 2>/dev/null | sort -u)

echo "变更文件:"
echo "$CHANGED_FILES" | head -20
```

---

## 步骤 2: 多维度验证

Agent 基于收集的上下文，对四个维度逐一评估。

### 2a: AC 完整性验证

Agent 分析每个 acceptance criteria 是否被当前变更覆盖：

```
对每个 AC 条目:
  1. 解析 AC 描述（如 "用户可以登录" → 涉及 auth 相关文件）
  2. 检查 CHANGED_FILES 是否包含相关文件
  3. 如果有相关变更 → 标记为 covered
  4. 如果无法确认 → 标记为 uncertain（保守策略，计为 WARN）
  5. 如果无相关变更 → 标记为 missed
```

```bash
AC_SCORE=100
AC_CRITERIA_COUNT=0
AC_COVERED=0
AC_MISSED="[]"

if [[ -n "$PLAN_FILE" ]]; then
  # Agent 分析 AC 覆盖度
  # 结果写入变量: AC_SCORE, AC_COVERED, AC_MISSED
  AC_CRITERIA_COUNT=$(python3 -c "
import json
criteria = json.loads('$ACCEPTANCE_CRITERIA')
print(len(criteria))
" 2>/dev/null)

  echo ""
  echo "=== AC 验证 ==="
  echo "总条件数: $AC_CRITERIA_COUNT"
  echo "Agent 需逐条检查 AC 与变更的对应关系"
else
  AC_SCORE=0
  echo "AC 维度: N/A（无 plan 产物）"
fi
```

**Agent 行为**: Agent 读取每个 AC 条目和变更文件列表，判断覆盖关系。对不确定的情况标记为 WARN。

### 2b: 审查质量验证

```bash
REVIEW_SCORE=100

if [[ -n "$REVIEW_FILE" ]]; then
  echo ""
  echo "=== 审查验证 ==="

  if [[ "$REVIEW_MUST_FIX" -gt 0 ]]; then
    echo "阻断: review 存在 $REVIEW_MUST_FIX 个 must_fix 项"
    REVIEW_SCORE=40
  fi

  if [[ "$REVIEW_STATUS" != "approved" ]]; then
    echo "阻断: review 状态为 $REVIEW_STATUS（期望 approved）"
    if [[ "$REVIEW_SCORE" -gt 40 ]]; then
      REVIEW_SCORE=60
    fi
  fi

  if [[ "$REVIEW_ADVISORY" -gt 5 ]]; then
    echo "警告: advisory 项较多 ($REVIEW_ADVISORY)"
    REVIEW_SCORE=$((REVIEW_SCORE - 5))
  fi

  echo "审查评分: $REVIEW_SCORE"
else
  REVIEW_SCORE=0
  echo "审查维度: N/A（无 review 产物）"
fi
```

### 2c: UI 安全性验证

```bash
UI_SCORE=100

if [[ -n "$UI_VERIFY_FILE" ]]; then
  echo ""
  echo "=== UI 验证 ==="

  case "$UI_SEVERITY" in
    none) UI_SCORE=100 ;;
    minor) UI_SCORE=90 ;;
    moderate)
      echo "警告: UI 变更 severity 为 moderate"
      UI_SCORE=70
      ;;
    significant)
      echo "阻断: UI 变更 severity 为 significant"
      UI_SCORE=30
      ;;
    *) UI_SCORE=80 ;;
  esac

  echo "UI 评分: $UI_SCORE (severity: ${UI_SEVERITY:-none}, changes: $UI_CHANGES)"
else
  # UI 验证非必须（后端变更无需 UI 验证），N/A 时不扣分
  UI_SCORE=100
  echo "UI 维度: 跳过（无 ui-verify 产物，非阻断）"
fi
```

### 2d: 架构一致性验证

```bash
ARCH_SCORE=100

if [[ -n "$DRIFT_GRADE" ]]; then
  echo ""
  echo "=== 架构验证 ==="

  case "$DRIFT_GRADE" in
    A) ARCH_SCORE=100 ;;
    B) ARCH_SCORE=85 ;;
    C) ARCH_SCORE=65 ;;
    D)
      echo "阻断: drift grade 为 D"
      ARCH_SCORE=40
      ;;
    *) ARCH_SCORE=80 ;;
  esac

  if [[ "$DRIFT_TREND" == "degrading" ]]; then
    echo "警告: 架构评分趋势下降"
    ARCH_SCORE=$((ARCH_SCORE - 10))
  fi

  echo "架构评分: $ARCH_SCORE (grade: $DRIFT_GRADE, trend: $DRIFT_TREND)"
else
  # 无 baseline 时不扣分（首次运行）
  ARCH_SCORE=100
  echo "架构维度: 跳过（无 drift baseline）"
fi
```

---

## 步骤 3: 综合评分

根据可用维度动态计算权重。

```bash
# 计算可用维度和动态权重
WEIGHTS='{"ac": 0.20, "review": 0.30, "ui": 0.25, "arch": 0.25}'
AVAILABLE_WEIGHT=0
AVAILABLE_DIMS=0

# 维度可用性检查
AC_AVAILABLE=true
REVIEW_AVAILABLE=true
UI_AVAILABLE=true
ARCH_AVAILABLE=true

[[ -z "$PLAN_FILE" ]] && AC_AVAILABLE=false
[[ -z "$REVIEW_FILE" ]] && REVIEW_AVAILABLE=false
# UI 和 ARCH 的 N/A 不影响评分，使用默认满分

if ! $AC_AVAILABLE; then
  AVAILABLE_WEIGHT=$(python3 -c "print(0.20)")
  AVAILABLE_DIMS=$((AVAILABLE_DIMS + 1))
fi
if ! $REVIEW_AVAILABLE; then
  AVAILABLE_WEIGHT=$(python3 -c "print($AVAILABLE_WEIGHT + 0.30)")
  AVAILABLE_DIMS=$((AVAILABLE_DIMS + 1))
fi

# 重分配不可用维度的权重
TOTAL_SCORE=$(python3 -c "
ac_w = 0.20 if ${AC_AVAILABLE:-false} else 0
rev_w = 0.30 if ${REVIEW_AVAILABLE:-false} else 0
ui_w = 0.25
arch_w = 0.25

# 收集不可用权重
unused = 0
if not ${AC_AVAILABLE:-false}:
    unused += 0.20
if not ${REVIEW_AVAILABLE:-false}:
    unused += 0.30

# 重分配给可用维度
active = []
if ${AC_AVAILABLE:-false}:
    active.append(('ac', 0.20, $AC_SCORE))
if ${REVIEW_AVAILABLE:-false}:
    active.append(('review', 0.30, $REVIEW_SCORE))
active.append(('ui', 0.25, $UI_SCORE))
active.append(('arch', 0.25, $ARCH_SCORE))

if len(active) > 0 and unused > 0:
    # 按比例分配
    total_w = sum(w for _, w, _ in active)
    active = [(n, w + unused * (w / total_w), s) for n, w, s in active]

total = sum(w * s / 100 for _, w, s in active)
print(round(total * 100, 1))
" 2>/dev/null)

echo ""
echo "=== 综合评分 ==="
echo "AC: $AC_SCORE (${AC_AVAILABLE})"
echo "Review: $REVIEW_SCORE (${REVIEW_AVAILABLE})"
echo "UI: $UI_SCORE (${UI_AVAILABLE})"
echo "Arch: $ARCH_SCORE (${ARCH_AVAILABLE})"
echo "总分: $TOTAL_SCORE / 100"
echo "阈值: $THRESHOLD"
```

---

## 步骤 4: 结论输出

```bash
# 识别阻断项
CRITICAL_BLOCKERS="[]"
BLOCKER_COUNT=0

# 收集阻断项
python3 -c "
import json

blockers = []

# Review 阻断
if $REVIEW_MUST_FIX > 0:
    blockers.append({
        'severity': 'critical',
        'dimension': 'review',
        'description': f'review 存在 {$REVIEW_MUST_FIX} 个 must_fix 项，需要修复后才能通过'
    })

if '$REVIEW_STATUS' != 'approved' and '$REVIEW_STATUS' != '':
    blockers.append({
        'severity': 'high',
        'dimension': 'review',
        'description': f'review 状态为 {$REVIEW_STATUS}，需要 approved'
    })

# UI 阻断
if '$UI_SEVERITY' == 'significant':
    blockers.append({
        'severity': 'critical',
        'dimension': 'ui',
        'description': 'UI 变更 severity 为 significant，存在重大 UI 回归'
    })

# Arch 阻断
if '$DRIFT_GRADE' == 'D':
    blockers.append({
        'severity': 'high',
        'dimension': 'arch',
        'description': f'架构评分降至 D 级（分数: {$DRIFT_SCORE}）'
    })

print(json.dumps(blockers))
" 2>/dev/null

# 生成修复建议
REMEDIATION=$(python3 -c "
import json
steps = []

if $REVIEW_MUST_FIX > 0:
    steps.append({
        'step': len(steps) + 1,
        'action': '修复 review must_fix 项',
        'target': 'review-*.json synthesis.must_fix[]',
        'skill': '/sns-workflow:review --diff'
    })

if '$UI_SEVERITY' == 'significant':
    steps.append({
        'step': len(steps) + 1,
        'action': '检查 UI 变更，确认是否为预期变更',
        'target': 'ui-verify-*.json diff_analysis',
        'skill': '/sns-workflow:ui-verify --verify'
    })

if '$DRIFT_GRADE' == 'D':
    steps.append({
        'step': len(steps) + 1,
        'action': '运行 drift-scanner 修复架构问题',
        'target': '.snsplay/principles.json',
        'skill': '/sns-workflow:drift-scanner'
    })

print(json.dumps(steps))
" 2>/dev/null)
```

### 判定逻辑

```bash
# 读取阻断项数量
BLOCKER_COUNT=$(python3 -c "
import json
blockers = json.loads('$CRITICAL_BLOCKERS') if '$CRITICAL_BLOCKERS' != '[]' else []
print(len([b for b in blockers if b.get('severity') in ('critical', 'high')]))
" 2>/dev/null)

VERDICT=""
if [[ "$BLOCKER_COUNT" -gt 0 ]]; then
  VERDICT="FAIL"
elif [[ $(python3 -c "print(int(float('$TOTAL_SCORE') >= $THRESHOLD))" 2>/dev/null) -eq 1 ]]; then
  VERDICT="PASS"
elif [[ $(python3 -c "print(int(float('$TOTAL_SCORE') >= 70))" 2>/dev/null) -eq 1 ]]; then
  VERDICT="WARN"
else
  VERDICT="FAIL"
fi

echo ""
echo "╔══════════════════════════════════════╗"
echo "║         QA GATE: $VERDICT"
echo "║  Score: $TOTAL_SCORE / 100"
echo "║  Blockers: $BLOCKER_COUNT"
echo "╚══════════════════════════════════════╝"
```

### 写入 Artifact

```bash
python3 -c "
import json, datetime

artifact = {
    'id': '$GATE_ID',
    'timestamp': datetime.datetime.utcnow().isoformat() + 'Z',
    'branch': '$current_branch',
    'plan_id': '$PLAN_ID',
    'score': float('$TOTAL_SCORE') if '$TOTAL_SCORE' else 0,
    'verdict': '$VERDICT',
    'threshold': $THRESHOLD,
    'dimensions': {
        'ac': {
            'score': $AC_SCORE,
            'available': $(python3 -c "print('true' if '$PLAN_FILE' else 'false')"),
            'criteria_count': $(python3 -c "print('$AC_CRITERIA_COUNT' if '$AC_CRITERIA_COUNT' else '0')"),
            'covered': $(python3 -c "print('$AC_COVERED' if '$AC_COVERED' else '0')"),
        },
        'review': {
            'score': $REVIEW_SCORE,
            'available': $(python3 -c "print('true' if '$REVIEW_FILE' else 'false')"),
            'must_fix': $REVIEW_MUST_FIX,
            'advisory': $REVIEW_ADVISORY,
            'status': '$REVIEW_STATUS'
        },
        'ui': {
            'score': $UI_SCORE,
            'available': $(python3 -c "print('true' if '$UI_VERIFY_FILE' else 'false')"),
            'severity': '$UI_SEVERITY' if '$UI_SEVERITY' else 'none',
            'changes': $UI_CHANGES
        },
        'arch': {
            'score': $ARCH_SCORE,
            'available': $(python3 -c "print('true' if '$DRIFT_GRADE' else 'false')"),
            'grade': '$DRIFT_GRADE' if '$DRIFT_GRADE' else 'N/A',
            'trend': '$DRIFT_TREND' if '$DRIFT_TREND' else 'new'
        }
    },
    'blockers': json.loads('$CRITICAL_BLOCKERS') if '$CRITICAL_BLOCKERS' else [],
    'remediation': json.loads('$REMEDIATION') if '$REMEDIATION' else [],
    'escalated': False,
    'round': 1
}

with open('$TASK_DIR/${GATE_ID}.json', 'w') as f:
    json.dump(artifact, f, indent=2, ensure_ascii=False)

print(f'Artifact: $TASK_DIR/${GATE_ID}.json')
" 2>/dev/null
```

### 结果报告

```bash
echo ""
echo "=== QA Gate 完成 ==="
echo "Verdict: $VERDICT"
echo "Score: $TOTAL_SCORE / 100 (阈值: $THRESHOLD)"
echo "Artifact: $TASK_DIR/${GATE_ID}.json"
echo ""

if [[ "$VERDICT" == "PASS" ]]; then
  echo "所有维度通过，可以安全提交"
  echo ""
  echo "后续操作:"
  echo "  /sns-workflow:commit-push-pr  → 提交变更"
elif [[ "$VERDICT" == "WARN" ]]; then
  echo "存在警告项，建议修复后再提交"
  echo ""
  echo "修复建议:"
  python3 -c "
import json
remediation = json.loads('$REMEDIATION') if '$REMEDIATION' else []
for r in remediation:
    print(f\"  {r['step']}. {r['action']} → {r['skill']}\")
" 2>/dev/null
else
  echo "存在关键阻断项，必须修复后才能提交"
  echo ""
  echo "阻断项:"
  python3 -c "
import json
blockers = json.loads('$CRITICAL_BLOCKERS') if '$CRITICAL_BLOCKERS' else []
for i, b in enumerate(blockers, 1):
    print(f\"  {i}. [{b['severity']}] {b['description']}\")
" 2>/dev/null
  echo ""
  echo "修复建议:"
  python3 -c "
import json
remediation = json.loads('$REMEDIATION') if '$REMEDIATION' else []
for r in remediation:
    print(f\"  {r['step']}. {r['action']} → {r['skill']}\")
" 2>/dev/null
  echo ""
  if $AUTO_MODE; then
    echo "自动修复模式: 将自动修复阻断项（步骤 5）"
  else
    echo "提示: 使用 --auto 参数可启用自动修复"
    echo "  /sns-workflow:qa-gate --auto"
  fi
fi
```

---

## 步骤 5: 自动修复循环（--auto 模式）

仅在 `--auto` 且 VERDICT != PASS 时执行。

```bash
if $AUTO_MODE && [[ "$VERDICT" != "PASS" ]]; then
  echo ""
  echo "=== 自动修复模式（MAX_ROUNDS=$MAX_ROUNDS）==="

  ROUND=1
  CURRENT_VERDICT="$VERDICT"

  while [[ "$ROUND" -le "$MAX_ROUNDS" ]] && [[ "$CURRENT_VERDICT" != "PASS" ]]; do
    echo ""
    echo "--- 第 $ROUND/$MAX_ROUNDS 轮 ---"

    # 读取当前 blocker
    BLOCKERS_JSON=$(python3 -c "
import json
with open('$TASK_DIR/${GATE_ID}.json') as f: d = json.load(f)
print(json.dumps(d.get('blockers', [])))
" 2>/dev/null)

    BLOCKER_DIMS=$(python3 -c "
import json
blockers = json.loads('$BLOCKERS_JSON')
dims = set(b['dimension'] for b in blockers)
print(' '.join(dims))
" 2>/dev/null)

    echo "阻断维度: $BLOCKER_DIMS"

    # 按维度触发修复
    for dim in $BLOCKER_DIMS; do
      case "$dim" in
        review)
          echo "→ 触发 review 修复"
          echo "Agent 行为: 读取 review must_fix 项，逐一修复代码，然后重新运行 review"
          # Agent 执行:
          # 1. Read review artifact → must_fix items
          # 2. For each must_fix: locate file, apply fix
          # 3. Re-run /sns-workflow:review --diff
          ;;
        ui)
          echo "→ 触发 ui-verify 重新验证"
          echo "Agent 行为: 检查 UI 变更是否为预期变更，如非预期则修复"
          # Agent 执行:
          # 1. Read ui-verify diff analysis
          # 2. Check if changes are intentional
          # 3. If not: fix UI code
          # 4. Re-run /sns-workflow:ui-verify --verify
          ;;
        arch)
          echo "→ 触发 drift-scanner 重新扫描"
          echo "Agent 行为: 运行 drift-scanner，根据扣分项修复架构问题"
          # Agent 执行:
          # 1. Run /sns-workflow:drift-scanner
          # 2. Read deductions
          # 3. Fix architecture violations
          ;;
        ac)
          echo "→ 检查缺失 AC 对应的变更"
          echo "Agent 行为: 读取 missed AC，补充实现缺失的功能"
          # Agent 执行:
          # 1. Read plan acceptance_criteria
          # 2. For each missed AC: implement or verify
          # 3. Check git diff for new changes
          ;;
      esac
    done

    # 修复完成后重新评估
    echo ""
    echo "重新评估..."

    # 重新收集产物（修复可能产生了新产物）
    latest_review=$(ls -t "$TASK_DIR"/review-*.json 2>/dev/null | grep -v "round" | head -1)
    latest_ui=$(ls -t "$TASK_DIR"/ui-verify-*.json 2>/dev/null | grep -v baseline | head -1)

    # 简化重评：检查关键指标是否改善
    NEW_REVIEW_MUST_FIX=$(python3 -c "
import json
if '$latest_review':
    with open('$latest_review') as f: d = json.load(f)
    print(len(d.get('synthesis', {}).get('must_fix', [])))
else:
    print($REVIEW_MUST_FIX)
" 2>/dev/null)

    echo "Review must_fix: $REVIEW_MUST_FIX → $NEW_REVIEW_MUST_FIX"

    # 判定本轮结果
    if [[ "$NEW_REVIEW_MUST_FIX" -eq 0 ]] && [[ -z "$BLOCKER_DIMS" || "$BLOCKER_DIMS" != *"review"* ]]; then
      CURRENT_VERDICT="PASS"
      echo "本轮修复成功"
    fi

    ROUND=$((ROUND + 1))
  done

  # 更新 artifact
  python3 -c "
import json
with open('$TASK_DIR/${GATE_ID}.json') as f: d = json.load(f)
d['round'] = $ROUND - 1
d['verdict'] = '$CURRENT_VERDICT'
d['escalated'] = $(python3 -c "print('true' if $ROUND - 1 > $MAX_ROUNDS else 'false')")
with open('$TASK_DIR/${GATE_ID}.json', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
" 2>/dev/null

  if [[ "$CURRENT_VERDICT" != "PASS" ]]; then
    echo ""
    echo "=== 自动修复未能通过 ($MAX_ROUNDS 轮) ==="
    echo "升级人工处理"
    echo ""
    echo "升级产物: $TASK_DIR/${GATE_ID}.json"
    echo "请检查 blocker 并手动修复，然后重新运行:"
    echo "  /sns-workflow:qa-gate"
  fi
fi
```

---

## 辅助: 快速检查（无产物模式）

当没有任何产物时，qa-gate 可以基于 git diff 进行轻量级检查：

```bash
# 如果所有产物都不存在，执行快速检查
if [[ -z "$PLAN_FILE" ]] && [[ -z "$REVIEW_FILE" ]] && [[ -z "$UI_VERIFY_FILE" ]] && [[ -z "$DRIFT_GRADE" ]]; then
  echo ""
  echo "=== 快速检查模式 ==="
  echo "未找到任何工作流产物，执行基于 git diff 的轻量检查"
  echo ""

  # 检查变更量
  CHANGED_COUNT=$(echo "$CHANGED_FILES" | grep -c . 2>/dev/null || echo "0")
  echo "变更文件数: $CHANGED_COUNT"

  if [[ "$CHANGED_COUNT" -eq 0 ]]; then
    echo "无变更，无需验证"
  else
    echo ""
    echo "建议在提交前运行以下技能:"
    echo "  /sns-workflow:review --diff     → 代码审查"
    if [[ "$CHANGED_COUNT" -gt 5 ]]; then
      echo "  /sns-workflow:drift-scanner     → 架构扫描（变更较多）"
    fi
    echo "  /sns-workflow:qa-gate           → 提交前质量门禁"
  fi
fi
```
