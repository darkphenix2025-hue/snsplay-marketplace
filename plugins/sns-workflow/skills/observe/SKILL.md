---
name: sns-workflow:observe
description: 智能体可观测性 —— 汇总工作流执行状态、成功率、耗时指标、错误模式。读取 .snsplay/task/ 产物文件和日志，生成运维视角的运行报告（覆盖 review/heal/ui-verify artifact）。
user-invocable: true
allowed-tools: Bash
---

# 智能体可观测性

汇总展示当前项目的 sns-workflow 执行状态、成功率、耗时指标、错误模式。

**数据来源**:
- `.snsplay/task/` — 工作流产物文件（manifest、impl-result、review 输出）
- `.snsplay/sns-workflow.log` — 调试日志（需启用 debug 模式）
- `.snsplay/task/cli_trace.log` — CLI 进程 stderr 追踪

---

## 步骤 1: 检查工作流状态

```bash
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")
TASK_DIR="$ROOT/.snsplay/task"

if [[ ! -d "$TASK_DIR" ]]; then
  echo "=== 可观测性报告 ==="
  echo ""
  echo "无活动工作流（.snsplay/task/ 目录不存在）"
  echo ""
  echo "提示: 运行 /sns-workflow:once 启动工作流"
  exit 0
fi

echo "=== 工作流状态 ==="

# 检查工作流类型
if [[ -f "$TASK_DIR/workflow-tasks.json" ]]; then
  workflow_type=$(grep -o '"workflow_type"[[:space:]]*:[[:space:]]*"[^"]*"' "$TASK_DIR/workflow-tasks.json" | head -1 | sed 's/.*:"//;s/"$//')
  echo "工作流类型: ${workflow_type:-未知}"

  # 检查当前阶段
  stages=$(grep -o '"output_file"[[:space:]]*:[[:space:]]*"[^"]*"' "$TASK_DIR/workflow-tasks.json" | sed 's/.*:"//;s/"$//')
  echo ""
  echo "阶段列表:"
  echo "$stages" | while read stage_file; do
    status="pending"
    if [[ -n "$stage_file" ]]; then
      # 检查产物文件是否存在且有状态
      artifact="$TASK_DIR/$stage_file"
      if [[ -f "$artifact" ]]; then
        art_status=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$artifact" | head -1 | sed 's/.*:"//;s/"$//')
        if [[ -n "$art_status" ]]; then
          status="$art_status"
        else
          status="done"
        fi
      fi
    fi
    case "$status" in
      approved) icon="✓" ;;
      needs_changes|needs_clarification) icon="~" ;;
      rejected) icon="✗" ;;
      done) icon="✓" ;;
      *) icon="○" ;;
    esac
    echo "  $icon $stage_file ($status)"
  done
else
  echo "工作流类型: 无 workflow-tasks.json"
fi

# 检查各阶段完成标记
echo ""
echo "阶段完成状态:"
[[ -f "$TASK_DIR/user-story/manifest.json" ]] && echo "  ✓ 需求分析 (user-story)" || echo "  ○ 需求分析"
[[ -f "$TASK_DIR/plan/manifest.json" ]] && echo "  ✓ 架构设计 (plan)" || echo "  ○ 架构设计"
[[ -f "$TASK_DIR/impl-result.json" ]] && echo "  ✓ 实现 (impl-result)" || echo "  ○ 实现"

# 检查实现结果
if [[ -f "$TASK_DIR/impl-result.json" ]]; then
  impl_status=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$TASK_DIR/impl-result.json" | head -1 | sed 's/.*:"//;s/"$//')
  steps=$(grep -o '"steps_completed"[[:space:]]*:[[:space:]]*[0-9]*' "$TASK_DIR/impl-result.json" | head -1 | sed 's/.*://')
  echo ""
  echo "实现状态: $impl_status (完成步骤: $steps)"
fi
```

---

## 步骤 2: 输出审核统计

```bash
TASK_DIR="$ROOT/.snsplay/task"

echo ""
echo "=== 审核统计 ==="

# plan review
plan_review_count=$(ls "$TASK_DIR"/plan-review-*.json 2>/dev/null | wc -l | tr -d ' ')
echo "计划审核: $plan_review_count 份输出"

# code review
code_review_count=$(ls "$TASK_DIR"/code-review-*.json 2>/dev/null | wc -l | tr -d ' ')
echo "代码审核: $code_review_count 份输出"

# RCA
rca_count=$(ls "$TASK_DIR"/rca-*.json 2>/dev/null | wc -l | tr -d ' ')
echo "根因分析: $rca_count 份输出"

# requirements analysis
req_count=$(ls "$TASK_DIR"/analysis-*.json 2>/dev/null | wc -l | tr -d ' ')
echo "需求分析: $req_count 份输出"

# review findings
if [[ -f "$TASK_DIR/review-findings-to-fix.json" ]]; then
  echo ""
  echo "⚠ 有审核未解决问题（review-findings-to-fix.json 存在）"
fi

# cross-review
review_count=$(ls "$TASK_DIR"/review-*.json 2>/dev/null | wc -l | tr -d ' ')
echo "交叉审查: $review_count 份输出"

# heal plans
heal_count=$(ls "$TASK_DIR"/heal-*.json 2>/dev/null | wc -l | tr -d ' ')
echo "恢复计划: $heal_count 份输出"

# ui-verify
uiv_count=$(ls "$TASK_DIR"/ui-verify-*.json 2>/dev/null | wc -l | tr -d ' ')
echo "UI 验证: $uiv_count 份输出"
```

---

## 步骤 2.5: UI 验证详细报告

```bash
TASK_DIR="$ROOT/.snsplay/task"

echo ""
echo "=== UI 验证详细报告 ==="

if [[ "$uiv_count" -eq 0 ]] 2>/dev/null || [[ ! -f "$(ls -t "$TASK_DIR"/ui-verify-*.json 2>/dev/null | head -1)" ]]; then
  echo "无 UI 验证产物"
else
  # 按模式分类统计
  snapshot_count=$(ls "$TASK_DIR"/ui-verify-*.json 2>/dev/null | xargs grep -l '"mode"[[:space:]]*:[[:space:]]*"snapshot"' 2>/dev/null | wc -l | tr -d ' ')
  verify_count=$(ls "$TASK_DIR"/ui-verify-*.json 2>/dev/null | xargs grep -l '"mode"[[:space:]]*:[[:space:]]*"verify"' 2>/dev/null | wc -l | tr -d ' ')
  reproduce_count=$(ls "$TASK_DIR"/ui-verify-*.json 2>/dev/null | xargs grep -l '"mode"[[:space:]]*:[[:space:]]*"reproduce"' 2>/dev/null | wc -l | tr -d ' ')
  audit_count=$(ls "$TASK_DIR"/ui-verify-*.json 2>/dev/null | xargs grep -l '"mode"[[:space:]]*:[[:space:]]*"audit"' 2>/dev/null | wc -l | tr -d ' ')

  echo "模式分布: snapshot=$snapshot_count verify=$verify_count reproduce=$reproduce_count audit=$audit_count"

  # 最新 verify 差异报告
  latest_verify=$(ls -t "$TASK_DIR"/ui-verify-*.json 2>/dev/null | xargs grep -l '"mode"[[:space:]]*:[[:space:]]*"verify"' 2>/dev/null | head -1)
  if [[ -n "$latest_verify" ]] && [[ -f "$latest_verify" ]]; then
    severity=$(grep -o '"severity"[[:space:]]*:[[:space:]]*"[^"]*"' "$latest_verify" | head -1 | sed 's/.*:"//;s/"$//')
    total_changes=$(grep -o '"total_changes"[[:space:]]*:[[:space:]]*[0-9]*' "$latest_verify" | head -1 | sed 's/.*://')
    echo ""
    echo "最新差异验证:"
    echo "  严重度: ${severity:-unknown}"
    echo "  变更总数: ${total_changes:-0}"
    if [[ "$severity" == "significant" ]] || [[ "$severity" == "moderate" ]]; then
      echo "  ⚠ 存在需关注的页面变更"
    fi
  fi

  # 最新 reproduce 结果
  latest_repro=$(ls -t "$TASK_DIR"/ui-verify-*.json 2>/dev/null | xargs grep -l '"mode"[[:space:]]*:[[:space:]]*"reproduce"' 2>/dev/null | head -1)
  if [[ -n "$latest_repro" ]] && [[ -f "$latest_repro" ]]; then
    reproducible=$(grep -o '"reproducible"[[:space:]]*:[[:space:]]*[a-z]*' "$latest_repro" | head -1 | sed 's/.*://')
    echo ""
    echo "最新 Bug 复现:"
    echo "  可复现: ${reproducible:-unknown}"
  fi

  # 最新 audit 健康度
  latest_audit=$(ls -t "$TASK_DIR"/ui-verify-*.json 2>/dev/null | xargs grep -l '"mode"[[:space:]]*:[[:space:]]*"audit"' 2>/dev/null | head -1)
  if [[ -n "$latest_audit" ]] && [[ -f "$latest_audit" ]]; then
    health_val=$(grep -o '"overall_health"[[:space:]]*:[[:space:]]*"[^"]*"' "$latest_audit" | head -1 | sed 's/.*:"//;s/"$//')
    critical=$(grep -o '"critical_issues"[[:space:]]*:[[:space:]]*[0-9]*' "$latest_audit" | head -1 | sed 's/.*://')
    echo ""
    echo "最新审计健康度:"
    echo "  整体: ${health_val:-unknown}"
    echo "  关键问题: ${critical:-0}"
    if [[ "$health_val" == "poor" ]] || [[ -n "$critical" ]] && [[ "$critical" -gt 0 ]] 2>/dev/null; then
      echo "  ⚠ 页面健康度需关注"
    fi
  fi

  # 基线状态
  if [[ -f "$TASK_DIR/ui-verify-baseline.json" ]]; then
    baseline_ts=$(grep -o '"timestamp"[[:space:]]*:[[:space:]]*"[^"]*"' "$TASK_DIR/ui-verify-baseline.json" | head -1 | sed 's/.*:"//;s/"$//')
    echo ""
    echo "基线: 已保存 (${baseline_ts:-unknown})"
  else
    echo ""
    echo "基线: 未建立（运行 /sns-workflow:ui-verify --snapshot）"
  fi
fi
```

---

## 步骤 3: 成功率与重试统计

```bash
TASK_DIR="$ROOT/.snsplay/task"

echo ""
echo "=== 成功率与重试 ==="

# 从 impl-result 判断实现状态
if [[ -f "$TASK_DIR/impl-result.json" ]]; then
  impl_status=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$TASK_DIR/impl-result.json" | head -1 | sed 's/.*:"//;s/"$//')
  echo "实现结果: $impl_status"

  # 检查测试通过率
  test_pass=$(grep -o '"tests_passed"[[:space:]]*:[[:space:]]*[0-9]*' "$TASK_DIR/impl-result.json" | head -1 | sed 's/.*://')
  test_fail=$(grep -o '"tests_failed"[[:space:]]*:[[:space:]]*[0-9]*' "$TASK_DIR/impl-result.json" | head -1 | sed 's/.*://')
  [[ -n "$test_pass" ]] && echo "  测试通过: $test_pass"
  [[ -n "$test_fail" ]] && echo "  测试失败: $test_fail"
else
  echo "实现结果: 无"
fi

# 统计修订轮次（通过 revision_number 字段）
echo ""
echo "修订轮次:"
for manifest in "$TASK_DIR"/user-story/manifest.json "$TASK_DIR"/plan/manifest.json; do
  if [[ -f "$manifest" ]]; then
    rev=$(grep -o '"revision_number"[[:space:]]*:[[:space:]]*[0-9]*' "$manifest" | head -1 | sed 's/.*://')
    name=$(basename "$(dirname "$manifest")")
    echo "  $name: ${rev:-0} 轮"
  fi
done

# 统计实现步骤数
impl_steps=$(ls "$TASK_DIR"/impl-steps/impl-step-*.json 2>/dev/null | wc -l | tr -d ' ')
echo "  实现步骤: $impl_steps"
```

---

## 步骤 4: 调试日志分析

```bash
LOG_DIR="$ROOT/.snsplay"
LOG_FILE="$LOG_DIR/sns-workflow.log"

echo ""
echo "=== 调试日志 ==="

if [[ ! -f "$LOG_FILE" ]]; then
  echo "日志文件不存在（debug 模式未启用）"
  echo "启用: 在 ~/.snsplay/config.json 设置 { \"debug\": true }"
else
  log_size=$(wc -c < "$LOG_FILE" | tr -d ' ')
  log_lines=$(wc -l < "$LOG_FILE" | tr -d ' ')
  echo "日志大小: $((log_size / 1024)) KB"
  echo "日志行数: $log_lines"

  # 统计事件类型
  echo ""
  echo "事件分布:"
  grep -o '\[[^]]*\]' "$LOG_FILE" 2>/dev/null | sort | uniq -c | sort -rn | while read count event; do
    echo "  $event: $count"
  done

  # 统计错误
  error_count=$(grep -c 'error\|FAILED\|Error' "$LOG_FILE" 2>/dev/null || echo "0")
  if [[ "$error_count" -gt 0 ]]; then
    echo ""
    echo "错误 ($error_count 项):"
    grep 'error\|FAILED\|Error' "$LOG_FILE" 2>/dev/null | tail -5 | while IFS= read -r line; do
      echo "  $line"
    done
  fi
fi
```

---

## 步骤 5: CLI 错误追踪

```bash
TRACE_FILE="$ROOT/.snsplay/task/cli_trace.log"

echo ""
echo "=== CLI 错误追踪 ==="

if [[ ! -f "$TRACE_FILE" ]]; then
  echo "无 CLI 追踪记录"
else
  trace_lines=$(wc -l < "$TRACE_FILE" | tr -d ' ')
  echo "追踪记录: $trace_lines 行"

  # 分类错误类型
  auth_errors=$(grep -ci 'auth\|login\|credential' "$TRACE_FILE" 2>/dev/null || echo "0")
  timeout_errors=$(grep -ci 'timeout\|timed out\|ETIMEDOUT' "$TRACE_FILE" 2>/dev/null || echo "0")
  not_found=$(grep -ci 'not found\|ENOENT\|command not found' "$TRACE_FILE" 2>/dev/null || echo "0")
  terminal_errors=$(grep -ci 'stdin is not a terminal\|TTY' "$TRACE_FILE" 2>/dev/null || echo "0")

  echo ""
  echo "错误分类:"
  [[ "$auth_errors" -gt 0 ]] && echo "  认证错误: $auth_errors"
  [[ "$timeout_errors" -gt 0 ]] && echo "  超时: $timeout_errors"
  [[ "$not_found" -gt 0 ]] && echo "  命令未找到: $not_found"
  [[ "$terminal_errors" -gt 0 ]] && echo "  终端错误: $terminal_errors"

  if [[ "$auth_errors" -eq 0 ]] && [[ "$timeout_errors" -eq 0 ]] && [[ "$not_found" -eq 0 ]] && [[ "$terminal_errors" -eq 0 ]]; then
    echo "  无分类错误"
  fi
fi
```

---

## 步骤 6: 输出汇总报告

```bash
echo ""
echo "=== 可观测性汇总 ==="

# 健康评分
health="healthy"
issues=""

# 检查失败状态
if [[ -f "$TASK_DIR/impl-result.json" ]]; then
  impl_status=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$TASK_DIR/impl-result.json" | head -1 | sed 's/.*:"//;s/"$//')
  [[ "$impl_status" == "failed" ]] && health="degraded" && issues="$issues  实现失败\n"
  [[ "$impl_status" == "partial" ]] && health="warning" && issues="$issues  部分实现\n"
fi

# 检查审核未解决问题
if [[ -f "$TASK_DIR/review-findings-to-fix.json" ]]; then
  health="warning"
  issues="$issues  待修复审核问题\n"
fi

# 检查交叉审查状态
latest_review=$(ls -t "$TASK_DIR"/review-*.json 2>/dev/null | head -1)
if [[ -n "$latest_review" ]]; then
  review_status=$(grep -o '"overall_status"[[:space:]]*:[[:space:]]*"[^"]*"' "$latest_review" | head -1 | sed 's/.*:"//;s/"$//')
  [[ "$review_status" == "needs_changes" ]] && health="warning" && issues="$issues  最新审查待修复\n"
fi

# 检查 UI 验证状态
latest_verify=$(ls -t "$TASK_DIR"/ui-verify-*.json 2>/dev/null | xargs grep -l '"mode"[[:space:]]*:[[:space:]]*"verify"' 2>/dev/null | head -1)
if [[ -n "$latest_verify" ]] && [[ -f "$latest_verify" ]]; then
  sev=$(grep -o '"severity"[[:space:]]*:[[:space:]]*"[^"]*"' "$latest_verify" | head -1 | sed 's/.*:"//;s/"$//')
  [[ "$sev" == "significant" ]] && health="degraded" && issues="$issues  UI 差异严重 (significant)\n"
  [[ "$sev" == "moderate" ]] && [[ "$health" == "healthy" ]] && health="warning" && issues="$issues  UI 差异中等 (moderate)\n"
fi

latest_audit=$(ls -t "$TASK_DIR"/ui-verify-*.json 2>/dev/null | xargs grep -l '"mode"[[:space:]]*:[[:space:]]*"audit"' 2>/dev/null | head -1)
if [[ -n "$latest_audit" ]] && [[ -f "$latest_audit" ]]; then
  audit_health=$(grep -o '"overall_health"[[:space:]]*:[[:space:]]*"[^"]*"' "$latest_audit" | head -1 | sed 's/.*:"//;s/"$//')
  [[ "$audit_health" == "poor" ]] && health="degraded" && issues="$issues  页面审计健康度差 (poor)\n"
  [[ "$audit_health" == "fair" ]] && [[ "$health" == "healthy" ]] && health="warning" && issues="$issues  页面审计健康度一般 (fair)\n"
fi

# 检查漂移扫描基线
BASELINE="$TASK_DIR/drift-baseline.json"
if [[ -f "$BASELINE" ]]; then
  drift_score=$(grep -o '"total_score"[[:space:]]*:[[:space:]]*[0-9]*' "$BASELINE" | head -1 | sed 's/.*://' || echo "")
  drift_grade=$(grep -o '"grade"[[:space:]]*:[[:space:]]*"[^"]*"' "$BASELINE" | head -1 | sed 's/.*:"//;s/"$//' || echo "")
  if [[ -n "$drift_grade" ]] && [[ "$drift_grade" == "D" ]]; then
    health="degraded" && issues="$issues  漂移扫描等级 D (${drift_score:-?}/100)\n"
  fi
fi

# 检查 CLI 错误
if [[ -f "$TRACE_FILE" ]]; then
  trace_errors=$(grep -ci 'error\|failed' "$TRACE_FILE" 2>/dev/null || echo "0")
  [[ "$trace_errors" -gt 10 ]] && health="degraded" && issues="$issues  CLI 错误过多 ($trace_errors)\n"
fi

echo "系统状态: $health"
if [[ -n "$issues" ]]; then
  echo "问题:"
  echo -e "$issues"
else
  echo "  无问题"
fi

echo "数据目录: $TASK_DIR"
echo "日志文件: ${LOG_FILE:-未启用}"
```
