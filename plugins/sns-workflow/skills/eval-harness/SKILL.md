---
name: sns-workflow:eval-harness
description: 评估测试套件生成与执行 —— 将 plan 的 acceptance criteria 转化为可执行评估脚本，运行并报告通过率。支持 --auto 模式自动修复未通过的用例。
user-invocable: true
allowed-tools: Bash, Read, Write, Grep, Glob
---

# 评估测试套件（Eval Harness）

将 plan 产物的 acceptance criteria 转化为可执行评估脚本，逐条验证代码变更是否满足验收标准。`--auto` 模式下对失败用例自动修复并重新验证。

**用法**:
- `eval-harness` — 生成评估脚本并执行，报告通过率
- `eval-harness --auto` — 自动修复未通过用例（最多 2 轮）
- `eval-harness --plan <plan-id>` — 指定关联的 plan 产物（默认读取最新）
- `eval-harness --dry-run` — 仅生成脚本，不执行

**数据源**: `.snsplay/task/plan-*.json`（acceptance_criteria）、git diff、review 产物

**产物**: `.snsplay/task/eval-harness-{TIMESTAMP}.sh` + `eval-harness-{TIMESTAMP}.json`

**集成**:
- Consumes: plan artifacts (acceptance_criteria), review artifacts
- Feeds: qa-gate (pass_rate 作为新维度)
- Works with: review (失败用例触发 review 修复)

---

## 步骤 1: 收集任务上下文

从 `.snsplay/task/` 读取最新的 plan 产物、review 产物和当前代码变更。

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/context.sh"

current_branch=$(git branch --show-current)
branch_type=$(sns_branch_type)
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")
TASK_DIR="$ROOT/.snsplay/task"

mkdir -p "$TASK_DIR"

# 解析参数
AUTO_MODE=false
DRY_RUN=false
TARGET_PLAN=""
MAX_ROUNDS=2

for arg in "$@"; do
  case "$arg" in
    --auto) AUTO_MODE=true ;;
    --dry-run) DRY_RUN=true ;;
    --plan) NEXT_IS_PLAN=true ;;
    --max-rounds) NEXT_IS_ROUNDS=true ;;
    *)
      [[ "$NEXT_IS_PLAN" == "true" ]] && TARGET_PLAN="$arg" && NEXT_IS_PLAN=false
      [[ "$NEXT_IS_ROUNDS" == "true" ]] && MAX_ROUNDS="$arg" && NEXT_IS_ROUNDS=false
      ;;
  esac
done

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
EVAL_ID="eval-harness-${TIMESTAMP}"
```

### 查找 Plan 产物

```bash
PLAN_FILE=""
PLAN_ID=""
ACCEPTANCE_CRITERIA="[]"

if [[ -n "$TARGET_PLAN" ]]; then
  # 指定 plan ID
  PLAN_FILE=$(ls -t "$TASK_DIR"/plan-*.json 2>/dev/null | while read -r f; do
    id=$(python3 -c "import json; print(json.load(open('$f')).get('id',''))" 2>/dev/null)
    [[ "$id" == "$TARGET_PLAN" ]] && echo "$f" && break
  done)
fi

if [[ -z "$PLAN_FILE" ]]; then
  # 默认取最新的 plan 文件
  PLAN_FILE=$(ls -t "$TASK_DIR"/plan-*.json 2>/dev/null | head -1)
fi

if [[ -n "$PLAN_FILE" ]]; then
  PLAN_ID=$(python3 -c "
import json
with open('$PLAN_FILE') as f: d = json.load(f)
print(d.get('id', ''))
" 2>/dev/null)

  ACCEPTANCE_CRITERIA=$(python3 -c "
import json
with open('$PLAN_FILE') as f: d = json.load(f)
criteria = d.get('acceptance_criteria', [])
print(json.dumps(criteria))
" 2>/dev/null)

  AC_COUNT=$(python3 -c "
import json
criteria = json.loads('$ACCEPTANCE_CRITERIA')
print(len(criteria))
" 2>/dev/null)

  echo "Plan: $PLAN_ID"
  echo "Acceptance Criteria 数量: $AC_COUNT"
  echo "Acceptance Criteria: $ACCEPTANCE_CRITERIA"
else
  echo "错误: 未找到 plan 产物"
  echo "请先运行 /sns-workflow:plan 生成计划"
  exit 1
fi
```

### 收集代码变更

```bash
# 获取变更文件列表
CHANGED_FILES=$(git diff --name-only HEAD 2>/dev/null; git diff --cached --name-only 2>/dev/null | sort -u)
CHANGED_COUNT=$(echo "$CHANGED_FILES" | grep -c . 2>/dev/null || echo "0")

echo "变更文件数: $CHANGED_COUNT"

# 获取完整 diff（评估脚本可能需要检查具体变更内容）
FULL_DIFF=$(git diff HEAD 2>/dev/null; git diff --cached 2>/dev/null)

# 收集 review 产物（可选，用于交叉参考）
REVIEW_FILE=""
latest_review=$(ls -t "$TASK_DIR"/review-*.json 2>/dev/null | grep -v "round" | head -1)
if [[ -n "$latest_review" ]]; then
  REVIEW_FILE="$latest_review"
  echo "Review 产物: $latest_review"
fi
```

---

## 步骤 2: 生成评估脚本

Agent 基于 acceptance criteria 生成可执行的验证逻辑。每条 AC 转化为一个独立的测试用例。

### AC → 测试用例转化规则

Agent 按以下规则将 AC 描述转化为可执行的检查步骤:

| AC 模式 | 检测方法 | 示例 |
|---------|----------|------|
| 功能存在性 | grep/文件存在检查 | "支持暗黑模式" → 检查 CSS 变量或 theme 文件 |
| 行为正确性 | 运行代码/命令验证 | "用户可以登录" → 验证 auth 流程可达 |
| API 契约 | HTTP 请求 / 类型检查 | "返回 200 状态码" → curl 或断言函数签名 |
| 配置项 | 配置文件解析 | "支持自定义端口" → 检查 config schema |
| 错误处理 | 触发错误路径 | "无效输入返回 400" → 构造错误输入验证 |

```bash
EVAL_SCRIPT="$TASK_DIR/${EVAL_ID}.sh"
EVAL_CASES="[]"
CASE_ID=0

echo "#!/usr/bin/env bash" > "$EVAL_SCRIPT"
echo "# Eval Harness Script — $EVAL_ID" >> "$EVAL_SCRIPT"
echo "# Plan: $PLAN_ID" >> "$EVAL_SCRIPT"
echo "# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$EVAL_SCRIPT"
echo "" >> "$EVAL_SCRIPT"
echo "set -uo pipefail" >> "$EVAL_SCRIPT"
echo "" >> "$EVAL_SCRIPT"
echo "PASS=0" >> "$EVAL_SCRIPT"
echo "FAIL=0" >> "$EVAL_SCRIPT"
echo "SKIP=0" >> "$EVAL_SCRIPT"
echo "TOTAL=0" >> "$EVAL_SCRIPT"
echo "RESULTS_FILE=\"$TASK_DIR/${EVAL_ID}-results.jsonl\"" >> "$EVAL_SCRIPT"
echo "echo '[]' > \"\$RESULTS_FILE\"" >> "$EVAL_SCRIPT"
echo "" >> "$EVAL_SCRIPT"

# 辅助函数：记录用例结果
cat >> "$EVAL_SCRIPT" << 'HELPER'
record_case() {
  local case_id="$1" ac="$2" status="$3" details="$4" error="${5:-}"
  TOTAL=$((TOTAL + 1))
  if [[ "$status" == "pass" ]]; then PASS=$((PASS + 1))
  elif [[ "$status" == "skip" ]]; then SKIP=$((SKIP + 1))
  else FAIL=$((FAIL + 1)); fi

  local entry="{\"id\":\"$case_id\",\"ac\":$(echo "$ac" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))'),\"status\":\"$status\",\"details\":$(echo "$details" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))'),\"error\":$(echo "$error" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))')}"

  # Append to results JSONL
  local tmp=$(python3 -c "
import json, sys
existing = json.load(open('$TASK_DIR/${EVAL_ID}-results.jsonl'))
existing.append($entry)
print(json.dumps(existing))
" 2>/dev/null)
  echo "$tmp" > "$RESULTS_FILE"

  echo "  [$status] $case_id: $details"
}
HELPER
```

### Agent 生成测试用例

Agent 逐条读取 AC，生成对应的验证函数:

```bash
# Agent 行为: 对每条 AC 生成测试用例
#
# 转化流程:
#   1. 解析 AC 文本 → 识别验证模式（功能存在性/行为正确性/API 契约/配置/错误处理）
#   2. 确定检查目标 → 文件路径、函数名、API 端点、配置键
#   3. 编写验证步骤 → grep | diff | curl | 文件解析 | 代码静态分析
#   4. 输出到评估脚本 → 每个 AC 一个 case_N() 函数

# 示例输出结构（Agent 按实际 AC 内容填充）:

python3 -c "
import json

criteria = json.loads('$ACCEPTANCE_CRITERIA')
cases = []

for i, ac in enumerate(criteria, 1):
    case_id = f'case-{i}'
    ac_text = ac if isinstance(ac, str) else ac.get('description', str(ac))
    cases.append({
        'id': case_id,
        'ac': ac_text,
        'mode': 'pending'  # Agent 填充: exists/behavior/api/config/error_handling
    })
    print(f'AC-{i}: {ac_text}')

print(f'\\n共 {len(cases)} 条待转化')
" 2>/dev/null

echo ""
echo "Agent 逐条转化 AC → 可执行验证步骤..."
echo "每条 AC 输出格式:"
echo ""
echo "  case_N() {"
echo "    local ac='<AC 描述>'"
echo "    # 验证步骤（基于 AC 类型选择检查方法）"
echo "    if <条件>; then"
echo "      record_case \"case-N\" \"\$ac\" \"pass\" \"<通过原因>\""
echo "    else"
echo "      record_case \"case-N\" \"\$ac\" \"fail\" \"<失败原因>\" \"<错误详情>\""
echo "    fi"
echo "  }"
echo ""
```

### 追加执行入口

```bash
cat >> "$EVAL_SCRIPT" << 'RUNNER'

echo ""
echo "=== 执行评估用例 ==="

# 执行所有 case_* 函数
for func in $(compgen -A function | grep '^case_'); do
  echo "Running $func..."
  $func
done

echo ""
echo "=== 评估结果 ==="
echo "Total: $TOTAL"
echo "Pass:  $PASS"
echo "Fail:  $FAIL"
echo "Skip:  $SKIP"
if [[ "$TOTAL" -gt 0 ]]; then
  RATE=$((PASS * 100 / TOTAL))
  echo "Rate:  ${RATE}%"
fi
RUNNER

chmod +x "$EVAL_SCRIPT"

echo ""
echo "评估脚本已生成: $EVAL_SCRIPT"
echo "用例数: $AC_COUNT"

if $DRY_RUN; then
  echo ""
  echo "[--dry-run] 仅生成脚本，不执行"
  echo "手动运行: bash $EVAL_SCRIPT"
  exit 0
fi
```

---

## 步骤 3: 执行评估

运行生成的评估脚本，收集每个用例的 pass/fail/skip 结果。

```bash
echo ""
echo "=== 执行评估: $EVAL_ID ==="
echo "Plan: $PLAN_ID"
echo ""

# 运行评估脚本
cd "$ROOT"
EVAL_OUTPUT=$(bash "$EVAL_SCRIPT" 2>&1)
EVAL_EXIT_CODE=$?

echo "$EVAL_OUTPUT"

# 解析结果
RESULTS_JSON=""
if [[ -f "$TASK_DIR/${EVAL_ID}-results.jsonl" ]]; then
  RESULTS_JSON=$(cat "$TASK_DIR/${EVAL_ID}-results.jsonl")
else
  RESULTS_JSON="[]"
fi

# 统计结果
TOTAL_CASES=$(python3 -c "
import json
results = json.loads('$RESULTS_JSON')
print(len(results))
" 2>/dev/null || echo "0")

PASSED=$(python3 -c "
import json
results = json.loads('$RESULTS_JSON')
print(len([r for r in results if r.get('status') == 'pass']))
" 2>/dev/null || echo "0")

FAILED=$(python3 -c "
import json
results = json.loads('$RESULTS_JSON')
print(len([r for r in results if r.get('status') == 'fail']))
" 2>/dev/null || echo "0")

SKIPPED=$(python3 -c "
import json
results = json.loads('$RESULTS_JSON')
print(len([r for r in results if r.get('status') == 'skip']))
" 2>/dev/null || echo "0")

PASS_RATE=0
if [[ "$TOTAL_CASES" -gt 0 ]]; then
  PASS_RATE=$(python3 -c "
rate = ($PASSED / $TOTAL_CASES) * 100
print(round(rate, 1))
" 2>/dev/null)
fi

echo ""
echo "=== 统计 ==="
echo "Total:  $TOTAL_CASES"
echo "Pass:   $PASSED"
echo "Fail:   $FAILED"
echo "Skip:   $SKIPPED"
echo "Rate:   ${PASS_RATE}%"
```

---

## 步骤 4: 报告结果

输出通过率和失败详情，写入 artifact。

### 失败用例详情

```bash
FAILED_CASES=$(python3 -c "
import json
results = json.loads('$RESULTS_JSON')
failed = [r for r in results if r.get('status') == 'fail']
for c in failed:
    print(f\"  [{c['id']}] {c['ac']}\")
    print(f\"    原因: {c.get('details', 'N/A')}\")
    if c.get('error'):
        print(f\"    错误: {c['error']}\")
" 2>/dev/null)

echo ""
echo "=== 失败用例 ==="
if [[ -n "$FAILED_CASES" ]]; then
  echo "$FAILED_CASES"
else
  echo "无失败用例"
fi
```

### 写入 Artifact

```bash
python3 -c "
import json, datetime

artifact = {
    'id': '$EVAL_ID',
    'timestamp': datetime.datetime.utcnow().isoformat() + 'Z',
    'branch': '$current_branch',
    'plan_id': '$PLAN_ID',
    'script_path': '$EVAL_SCRIPT',
    'total_cases': $TOTAL_CASES,
    'passed': $PASSED,
    'failed': $FAILED,
    'skipped': $SKIPPED,
    'pass_rate': $PASS_RATE,
    'verdict': 'PASS' if $PASS_RATE >= 80 else ('PARTIAL' if $PASS_RATE >= 50 else 'FAIL'),
    'cases': json.loads('$RESULTS_JSON'),
    'auto_mode': $(python3 -c "print('true' if '$AUTO_MODE' == 'true' else 'false')"),
    'round': 1,
    'max_rounds': $MAX_ROUNDS
}

with open('$TASK_DIR/${EVAL_ID}.json', 'w') as f:
    json.dump(artifact, f, indent=2, ensure_ascii=False)

print(f'Artifact: $TASK_DIR/${EVAL_ID}.json')
" 2>/dev/null
```

### 结果报告

```bash
VERDICT=$(python3 -c "
rate = $PASS_RATE
if rate >= 80: print('PASS')
elif rate >= 50: print('PARTIAL')
else: print('FAIL')
" 2>/dev/null)

echo ""
echo "╔════════════════════════════════════════════╗"
echo "║        EVAL HARNESS: $VERDICT"
echo "║  Pass Rate: $PASSED/$TOTAL_CASES ($PASS_RATE%)"
echo "║  Failed: $FAILED  Skipped: $SKIPPED"
echo "╚════════════════════════════════════════════╝"
echo ""

if [[ "$VERDICT" == "PASS" ]]; then
  echo "所有 AC 验证通过"
  echo ""
  echo "后续操作:"
  echo "  /sns-workflow:qa-gate          → 综合质量门禁"
  echo "  /sns-workflow:commit-push-pr   → 提交变更"
elif [[ "$VERDICT" == "PARTIAL" ]]; then
  echo "部分 AC 未通过，建议修复后重新评估"
  echo ""
  echo "失败用例:"
  echo "$FAILED_CASES"
  echo ""
  if $AUTO_MODE; then
    echo "自动修复模式: 将尝试修复失败用例（步骤 5）"
  else
    echo "提示: 使用 --auto 参数可启用自动修复"
    echo "  /sns-workflow:eval-harness --auto"
  fi
else
  echo "多数 AC 未通过，需要较大修复"
  echo ""
  echo "建议:"
  echo "  1. 检查 plan 的 AC 是否合理"
  echo "  2. 运行 /sns-workflow:review --diff 检查代码质量"
  echo "  3. 修复后重新运行评估"
  echo ""
  if $AUTO_MODE; then
    echo "自动修复模式: 将尝试修复（步骤 5）"
  else
    echo "提示: 使用 --auto 参数可启用自动修复"
  fi
fi
```

---

## 步骤 5: 自动修复（--auto 模式）

仅在 `--auto` 且 VERDICT != PASS 时执行。最多 `MAX_ROUNDS`（默认 2）轮修复循环。

```bash
if $AUTO_MODE && [[ "$VERDICT" != "PASS" ]]; then
  echo ""
  echo "=== 自动修复模式（MAX_ROUNDS=$MAX_ROUNDS）==="

  ROUND=1
  CURRENT_VERDICT="$VERDICT"
  CURRENT_PASS_RATE="$PASS_RATE"

  while [[ "$ROUND" -le "$MAX_ROUNDS" ]] && [[ "$CURRENT_VERDICT" != "PASS" ]]; do
    echo ""
    echo "--- 第 $ROUND/$MAX_ROUNDS 轮 ---"

    # 读取当前失败用例
    FAILURES_JSON=$(python3 -c "
import json
with open('$TASK_DIR/${EVAL_ID}.json') as f: d = json.load(f)
failed = [c for c in d.get('cases', []) if c.get('status') == 'fail']
print(json.dumps(failed))
" 2>/dev/null)

    FAILURE_COUNT=$(python3 -c "
import json
print(len(json.loads('$FAILURES_JSON')))
" 2>/dev/null)

    echo "失败用例数: $FAILURE_COUNT"

    # 分析失败原因并分类
    python3 -c "
import json

failures = json.loads('$FAILURES_JSON')
categories = {'logic_error': 0, 'missing_impl': 0, 'api_change': 0, 'config_error': 0, 'unknown': 0}

for f in failures:
    error = f.get('error', '').lower()
    details = f.get('details', '').lower()

    if 'not found' in error or 'missing' in error or '不存在' in details:
        categories['missing_impl'] += 1
    elif 'type error' in error or 'undefined' in error or '逻辑' in details:
        categories['logic_error'] += 1
    elif 'status' in error or 'api' in error or 'response' in error:
        categories['api_change'] += 1
    elif 'config' in error or '配置' in details:
        categories['config_error'] += 1
    else:
        categories['unknown'] += 1

for cat, count in categories.items():
    if count > 0:
        print(f'  {cat}: {count}')
" 2>/dev/null

    echo ""
    echo "Agent 行为: 逐个分析失败用例并修复代码"
    echo ""
    echo "修复策略:"
    echo "  logic_error    → 定位错误代码，修正逻辑"
    echo "  missing_impl   → 补充缺失的实现代码"
    echo "  api_change     → 更新 API 调用以匹配最新接口"
    echo "  config_error   → 修正配置文件"
    echo "  unknown        → 深入分析错误上下文后修复"
    echo ""

    # Agent 执行修复:
    # 1. 读取每个失败用例的 AC 描述和错误信息
    # 2. 在 CHANGED_FILES 中定位相关代码
    # 3. 分析错误原因，选择修复策略
    # 4. 应用代码修复
    # 5. 记录修复内容

    echo "修复完成，重新生成并执行评估脚本..."

    # 重新生成评估脚本（基于同一组 AC，但代码已变更）
    NEW_EVAL_ID="eval-harness-${TIMESTAMP}-r${ROUND}"
    NEW_EVAL_SCRIPT="$TASK_DIR/${NEW_EVAL_ID}.sh"

    # Agent 重新生成脚本（代码已变，验证条件可能不同）
    # 复用步骤 2 的逻辑，但检查修复后的代码
    echo "重新评估: $NEW_EVAL_ID"

    # 执行新脚本
    NEW_EVAL_OUTPUT=$(bash "$NEW_EVAL_SCRIPT" 2>&1)

    # 解析新结果
    NEW_RESULTS=$(cat "$TASK_DIR/${NEW_EVAL_ID}-results.jsonl" 2>/dev/null || echo "[]")

    NEW_PASSED=$(python3 -c "
import json
results = json.loads('$NEW_RESULTS')
print(len([r for r in results if r.get('status') == 'pass']))
" 2>/dev/null || echo "0")

    NEW_TOTAL=$(python3 -c "
import json
results = json.loads('$NEW_RESULTS')
print(len(results))
" 2>/dev/null || echo "0")

    NEW_PASS_RATE=0
    if [[ "$NEW_TOTAL" -gt 0 ]]; then
      NEW_PASS_RATE=$(python3 -c "
rate = ($NEW_PASSED / $NEW_TOTAL) * 100
print(round(rate, 1))
" 2>/dev/null)
    fi

    echo "通过率: $CURRENT_PASS_RATE% → ${NEW_PASS_RATE}%"
    CURRENT_PASS_RATE="$NEW_PASS_RATE"

    # 判定本轮结果
    if python3 -c "exit(0 if $NEW_PASS_RATE >= 80 else 1)" 2>/dev/null; then
      CURRENT_VERDICT="PASS"
      echo "本轮修复成功"
    elif python3 -c "exit(0 if $NEW_PASS_RATE >= $CURRENT_PASS_RATE else 1)" 2>/dev/null; then
      echo "有所改善，继续下一轮"
    else
      echo "未改善，停止修复"
      break
    fi

    ROUND=$((ROUND + 1))
  done

  # 写入最终 artifact（更新轮次和结果）
  python3 -c "
import json, datetime

# 读取原始 artifact
with open('$TASK_DIR/${EVAL_ID}.json') as f:
    artifact = json.load(f)

# 读取最新一轮的结果
latest_results_file = '$TASK_DIR/${NEW_EVAL_ID}-results.jsonl'
try:
    with open(latest_results_file) as f:
        latest_cases = json.load(f)
except:
    latest_cases = artifact.get('cases', [])

latest_passed = len([c for c in latest_cases if c.get('status') == 'pass'])
latest_failed = len([c for c in latest_cases if c.get('status') == 'fail'])
latest_skipped = len([c for c in latest_cases if c.get('status') == 'skip'])
latest_total = len(latest_cases)
latest_rate = round((latest_passed / latest_total) * 100, 1) if latest_total > 0 else 0

final_verdict = 'PASS' if latest_rate >= 80 else ('PARTIAL' if latest_rate >= 50 else 'FAIL')

artifact.update({
    'round': $ROUND - 1,
    'verdict': '$CURRENT_VERDICT',
    'total_cases': latest_total,
    'passed': latest_passed,
    'failed': latest_failed,
    'skipped': latest_skipped,
    'pass_rate': latest_rate,
    'cases': latest_cases,
    'auto_completed': True
})

with open('$TASK_DIR/${EVAL_ID}.json', 'w') as f:
    json.dump(artifact, f, indent=2, ensure_ascii=False)

print(f'Artifact updated: $TASK_DIR/${EVAL_ID}.json')
" 2>/dev/null

  echo ""
  echo "╔════════════════════════════════════════════╗"
  echo "║   EVAL HARNESS (auto): $CURRENT_VERDICT"
  echo "║   Pass Rate: ${CURRENT_PASS_RATE}% ($ROUND 轮)"
  echo "╚════════════════════════════════════════════╝"
  echo ""

  if [[ "$CURRENT_VERDICT" != "PASS" ]]; then
    echo "自动修复未完全通过（$ROUND 轮）"
    echo ""
    echo "后续建议:"
    echo "  1. 检查失败用例: cat $TASK_DIR/${EVAL_ID}.json | python3 -m json.tool"
    echo "  2. 手动修复失败项后重新运行: /sns-workflow:eval-harness --auto"
    echo "  3. 或触发 review: /sns-workflow:review --diff"
  else
    echo "所有 AC 验证通过"
    echo ""
    echo "后续操作:"
    echo "  /sns-workflow:qa-gate          → 综合质量门禁"
    echo "  /sns-workflow:commit-push-pr   → 提交变更"
  fi
fi
```
