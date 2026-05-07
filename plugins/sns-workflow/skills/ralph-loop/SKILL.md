---
name: sns-workflow:ralph-loop
description: Ralph Wiggum Loop 执行控制 —— 持续检测技能体系与 Harness Engineering 文章标准的差距，自动触发开发直到所有差距补齐。
user-invocable: true
allowed-tools: Bash, Read, Write, Grep, Glob, AskUserQuestion, Agent, mcp__chrome-devtools__take_snapshot, mcp__chrome-devtools__take_screenshot, mcp__chrome-devtools__navigate_page
---

# Ralph Wiggum Loop 执行控制

持续监督开发进度，循环执行「分析差距 → 制定计划 → 执行开发 → 验证结果 → 再分析差距」，直到所有 Harness Engineering 文章标准均已满足。

**用法**:
- `ralph-loop` — 运行一轮差距分析
- `ralph-loop --auto` — 自动循环直到所有差距补齐
- `ralph-loop --max-rounds 10` — 自定义最大循环轮次（默认 5）
- `ralph-loop --min-gaps 2` — 剩余 ≤N 个差距时视为完成（默认 0）
- `ralph-loop --stall-limit 3` — 连续 N 轮差距不减少时停止（默认 2）
- `ralph-loop --stop-on-review` — 遇到 review 问题暂停（需要人工确认）

**数据目录**: `.snsplay/task/ralph-loop/`

**产物**: `.snsplay/task/ralph-loop/ralph-round-{N}.json`

---

## 步骤 1: 初始化环境

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/context.sh"
source "$SHELL_DIR/skill-logger.sh"
sns_skill_start "ralph-loop" "$*"

current_branch=$(git branch --show-current)
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")
TASK_DIR="$ROOT/.snsplay/task"
RALPH_DIR="$TASK_DIR/ralph-loop"
mkdir -p "$RALPH_DIR"

# 解析参数
AUTO_MODE=false
MAX_ROUNDS=5
MIN_GAPS=0
STALL_LIMIT=2
STOP_ON_REVIEW=false

for arg in "$@"; do
  case "$arg" in
    --auto) AUTO_MODE=true ;;
    --stop-on-review) STOP_ON_REVIEW=true ;;
    --max-rounds) NEXT_IS_ROUNDS=true ;;
    --min-gaps) NEXT_IS_MIN_GAPS=true ;;
    --stall-limit) NEXT_IS_STALL=true ;;
    *)
      [[ "$NEXT_IS_ROUNDS" == "true" ]] && MAX_ROUNDS="$arg" && NEXT_IS_ROUNDS=false
      [[ "$NEXT_IS_MIN_GAPS" == "true" ]] && MIN_GAPS="$arg" && NEXT_IS_MIN_GAPS=false
      [[ "$NEXT_IS_STALL" == "true" ]] && STALL_LIMIT="$arg" && NEXT_IS_STALL=false
      ;;
  esac
done

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)

echo "=== Ralph Wiggum Loop ==="
echo "分支: $current_branch"
echo "模式: $([ "$AUTO_MODE" = true ] && echo "自动 ($MAX_ROUNDS 轮)" || echo "单轮分析")"
echo "终止条件:"
echo "  - 最大轮次: $MAX_ROUNDS"
echo "  - 最小差距: $MIN_GAPS (≤$MIN_GAPS 即完成)"
echo "  - 停滞检测: $STALL_LIMIT 轮差距不减少即停止"
echo "停止策略: $([ "$STOP_ON_REVIEW" = true ] && echo "review 暂停" || echo "全自动")"
```

---

## 步骤 2: 差距分析（Gap Analysis）

Agent 基于 Harness Engineering 文章进行结构化差距分析。

### 2a: 读取参考标准

```bash
REFERENCE="$ROOT/docs/references/harness-engineering.md"

if [[ ! -f "$REFERENCE" ]]; then
  echo "错误: Harness Engineering 参考文章不存在"
  echo "请保存文章到: $REFERENCE"
  exit 1
fi

# 读取参考文章
echo ""
echo "=== 差距分析 ==="
echo "参考文档: $REFERENCE"
echo ""
echo "Agent 行为: 读取 Harness Engineering 文章，提取所有实践要求"
```

### 2b: 盘点现有能力

```bash
# 获取所有现有技能列表
SKILLS_DIR="$ROOT/plugins/sns-workflow/skills"
EXISTING_SKILLS=$(ls "$SKILLS_DIR" | tr '\n' ' ')
SKILL_COUNT=$(ls -d "$SKILLS_DIR"/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')

echo "现有技能 (${SKILL_COUNT} 个):"
for skill in $(ls "$SKILLS_DIR"); do
  if [[ -f "$SKILLS_DIR/$skill/SKILL.md" ]]; then
    desc=$(grep -o 'description:.*' "$SKILLS_DIR/$skill/SKILL.md" | head -1 | sed 's/description: *//')
    echo "  ✓ $skill: $desc"
  fi
done
```

### 2c: Agent 执行差距分析

```bash
# Agent 基于以下矩阵进行分析:
#
# Harness Engineering 关键实践 vs 当前覆盖状态:
#
# | # | 实践要求 | 当前覆盖 | 状态 |
# |---|---------|---------|------|
# | 1 | 文档即 TOC，非百科全书 | CLAUDE.md ~100 行 + docs/ 分层索引 | ✅ |
# | 2 | 渐进式文档加载 | design-docs/exec-plans/references/product-specs | ✅ |
# | 3 | doc-gardening 定时维护 | doc-garden + drift-scanner | ✅ |
# | 4 | 六层架构 + 强制依赖方向 | arch-lint + 六层架构 | ✅ |
# | 5 | Golden principles 注册表 | .snsplay/principles.json (17 条) | ✅ |
# | 6 | PR 合并与清理 | merge-pr | ✅ |
# | 7 | 错误恢复 | heal | ✅ |
# | 8 | 交叉审查 | review | ✅ |
# | 9 | UI 验证 | ui-verify | ✅ |
# | 10 | 开发服务器管理 | dev-server | ✅ |
# | 11 | 可观测性 | observe + status | ✅ |
# | 12 | 计划即一等制品 | plan（混合模式 + artifact）| ✅ |
# | 13 | 质量门禁 (QA Gate) | qa-gate | ✅ |
# | 14 | Agent 自主闭环 | ralph-loop（本技能）| ✅ |
# | 15 | Evaluation harness | 通用任务完成度评估 | ❌ 缺失 |
# | 16 | Per-worktree 日志栈 | 真实日志查询能力 | ❌ 缺失 |
# | 17 | Auto-merge 流水线 | PR 自动合入增强 | ❌ 缺失 |
# | 18 | Video 录制取证 | Bug 复现/修复视频 | ❌ 缺失 |
# | ... | [Agent 动态检测新实践] | ... | ... |

echo "Agent 开始差距分析..."
echo ""
echo "分析矩阵:"
echo "  - 读取 Harness Engineering 文章所有实践要求"
echo "  - 对比现有技能能力"
echo "  - 识别 MISSING 项"
echo "  - 生成差距报告"
```

### 2d: 生成差距报告

```bash
# Agent 分析后生成差距报告
GAP_REPORT=$(python3 -c "
import json

# Agent 动态分析的差距（Agent 在此步骤后直接输出）
# 以下为 Agent 分析后的占位，实际内容由 Agent 在步骤 3 的差距分析中确定
gaps = [
    # Agent 根据 Harness Engineering 文章分析的结果将填入此处
    # 格式: {'id': 'gap-N', 'practice': '...', 'status': 'covered|missing|partial', 'priority': 'high|medium|low'}
]

report = {
    'round': 1,
    'timestamp': '$TIMESTAMP',
    'skill_count': $SKILL_COUNT,
    'gaps': gaps,
    'total_gaps': len(gaps),
    'covered_practices': [g for g in gaps if g['status'] == 'covered'],
    'missing_practices': [g for g in gaps if g['status'] == 'missing'],
    'partial_practices': [g for g in gaps if g['status'] == 'partial']
}

print(json.dumps(report, indent=2, ensure_ascii=False))
" 2>/dev/null)

echo ""
echo "差距报告: $RALPH_DIR/ralph-round-1.json"
echo "缺失实践数: $(echo "$GAP_REPORT" | python3 -c "import sys,json; print(json.load(sys.stdin)['total_gaps'])" 2>/dev/null)

# 生成机器可读的完成度检查清单
python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
checklist = []
for g in data.get('gaps', []):
    checklist.append({
        'id': g['id'],
        'practice': g['practice'],
        'status': g['status'],
        'completion_criteria': g.get('description', ''),
        'verified': False
    })
with open('$RALPH_DIR/checklist.json', 'w') as f:
    json.dump({'items': checklist, 'generated_round': 1}, f, indent=2, ensure_ascii=False)
print(f'完成度清单: $RALPH_DIR/checklist.json ({len(checklist)} 项)')
" <<< "$GAP_REPORT""
```

---

## 步骤 3: Agent 执行差距分析（Agent 行为）

**Agent 在此步骤执行以下行为**:

1. **读取** `docs/references/harness-engineering.md` 提取所有实践要求
2. **读取** `docs/ARCHITECTURE.md` 获取当前技能列表
3. **逐个技能读取** `plugins/sns-workflow/skills/*/SKILL.md` 了解能力细节
4. **对比** 实践要求与现有能力，生成差距矩阵
5. **输出** 差距报告到 `$RALPH_DIR/ralph-round-{N}.json`

差距报告格式:
```json
{
  "round": 1,
  "timestamp": "20260507T...",
  "skill_count": 20,
  "gaps": [
    {
      "id": "gap-15",
      "practice": "Evaluation harness",
      "description": "通用任务完成度评估，补充 qa-gate 仅覆盖已有验证的空白",
      "status": "missing",
      "priority": "high",
      "suggested_skill": "eval-harness"
    },
    {
      "id": "gap-16",
      "practice": "Per-worktree 日志栈",
      "description": "Per-worktree LogQL/PromQL 栈，让 agent 能查询运行时日志",
      "status": "missing",
      "priority": "medium",
      "suggested_skill": "log-stack"
    }
  ]
}
```

---

## 步骤 4: 缺口补齐（开发缺失技能）

根据差距报告，自动触发开发。

```bash
MISSING_COUNT=$(echo "$GAP_REPORT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(len(data.get('missing_practices', [])))
" 2>/dev/null)

PARTIAL_COUNT=$(echo "$GAP_REPORT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(len(data.get('partial_practices', [])))
" 2>/dev/null)

TOTAL_GAPS=$((MISSING_COUNT + PARTIAL_COUNT))

echo ""
echo "=== 缺口统计 ==="
echo "缺失: $MISSING_COUNT"
echo "部分覆盖: $PARTIAL_COUNT"
echo "待补齐: $TOTAL_GAPS"
```

### 4a: 单轮模式 — 仅展示差距

```bash
if ! $AUTO_MODE; then
  echo ""
  echo "╔══════════════════════════════════════╗"
  echo "║  Ralph Loop 差距分析完成"

  if [[ "$TOTAL_GAPS" -eq 0 ]]; then
    echo "║  ✅ 所有实践均已覆盖"
  else
    echo "║  ⚠ 发现 $TOTAL_GAPS 个待补齐项"
  fi

  echo "╚══════════════════════════════════════╝"

  if [[ "$TOTAL_GAPS" -gt 0 ]]; then
    echo ""
    echo "待补齐实践:"
    echo "$GAP_REPORT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for g in data.get('missing_practices', []):
    print(f\"  ❌ [{g['priority']}] {g['practice']} → {g.get('suggested_skill', 'new-skill')}\")
for g in data.get('partial_practices', []):
    print(f\"  ⚠ [{g['priority']}] {g['practice']} → 增强 {g.get('suggested_skill', 'existing-skill')}\")
" 2>/dev/null

    echo ""
    echo "运行 /sns-workflow:ralph-loop --auto 自动补齐所有缺口"
  fi

  exit 0
fi
```

### 4b: Auto 模式 — 自动触发开发

```bash
if [[ "$TOTAL_GAPS" -eq 0 ]]; then
  echo ""
  echo "✅ 所有 Harness Engineering 实践均已覆盖"
  echo ""
  echo "最终报告: $RALPH_DIR/ralph-round-1.json"
  exit 0
fi

# 按优先级排序缺口
echo ""
echo "开始自动补齐..."

# Agent 行为: 逐个处理缺失实践
echo "Agent 行为: 对每个缺失实践"
echo "  1. 分析实践要求"
echo "  2. 设计新技能或增强现有技能"
echo "  3. 创建 SKILL.md"
echo "  4. 更新注册文件"
echo "  5. 运行 review 和 qa-gate 验证"
echo ""
echo "提示: 如果 STOP_ON_REVIEW=true，每轮开发后暂停等待确认"
```

---

## 步骤 5: Ralph Loop 循环

三层终止条件：

| 条件 | 触发 | 结果 |
|------|------|------|
| **硬终止** | 达到 `MAX_ROUNDS` 轮 | 强制停止，报告剩余差距 |
| **成功终止** | 所有差距标记为 covered（`≤MIN_GAPS`） | 正常完成 |
| **停滞终止** | 连续 `STALL_LIMIT` 轮差距不减少 | 判定为无法自动补齐，停止 |

```bash
ROUND=0
PREV_GAPS=-1
STALL_COUNT=0
TERMINATION_REASON=""

while [[ "$ROUND" -lt "$MAX_ROUNDS" ]]; do
  ROUND=$((ROUND + 1))

  # === 步骤 5a: 差距分析（每轮重新执行）===
  echo ""
  echo "╔══════════════════════════════════════╗"
  echo "║  Round $ROUND/$MAX_ROUNDS"
  echo "╚══════════════════════════════════════╝"

  # Agent 重新执行差距分析（步骤 2-3 逻辑）
  # 1. 读取 Harness Engineering 文章
  # 2. 读取当前技能列表 (ls skills/*/SKILL.md)
  # 3. 逐个读取 SKILL.md description 字段
  # 4. 对比实践要求，更新 checklist
  echo ""
  echo "→ 重新执行差距分析..."

  # Agent 行为: 更新 checklist.json
  # Agent 对每个 checklist item 判断:
  #   - status: "covered" | "missing" | "partial"
  #   - verified: true | false (Agent 确认过)
  # 输出到 $RALPH_DIR/ralph-round-$ROUND.json

  # 读取当前差距数
  GAPS_FOUND=$(python3 -c "
import json
with open('$RALPH_DIR/checklist.json') as f:
    data = json.load(f)
missing = sum(1 for item in data['items'] if item['status'] != 'covered')
print(missing)
" 2>/dev/null)

  VERIFIED_COUNT=$(python3 -c "
import json
with open('$RALPH_DIR/checklist.json') as f:
    data = json.load(f)
print(sum(1 for item in data['items'] if item.get('verified', False)))
" 2>/dev/null)

  TOTAL_COUNT=$(python3 -c "
import json
with open('$RALPH_DIR/checklist.json') as f:
    data = json.load(f)
print(len(data['items']))
" 2>/dev/null)

  echo "  差距数: $GAPS_FOUND / $TOTAL_COUNT"
  echo "  已验证: $VERIFIED_COUNT / $TOTAL_COUNT"

  # === 步骤 5b: 三层终止条件检查 ===

  # 1. 成功终止: 所有差距 ≤ MIN_GAPS
  if [[ "$GAPS_FOUND" -le "$MIN_GAPS" ]]; then
    TERMINATION_REASON="success"
    echo ""
    echo "✅ 成功终止: 差距数 $GAPS_FOUND ≤ 最小阈值 $MIN_GAPS"
    break
  fi

  # 2. 停滞终止: 连续 STALL_LIMIT 轮差距不减少
  if [[ "$PREV_GAPS" -ge 0 ]] && [[ "$GAPS_FOUND" -ge "$PREV_GAPS" ]]; then
    STALL_COUNT=$((STALL_COUNT + 1))
    echo "  停滞检测: 连续 $STALL_COUNT/$STALL_LIMIT 轮差距未减少"
    if [[ "$STALL_COUNT" -ge "$STALL_LIMIT" ]]; then
      TERMINATION_REASON="stalled"
      echo ""
      echo "⏹ 停滞终止: 连续 $STALL_LIMIT 轮差距未减少 ($GAPS_FOUND)"
      break
    fi
  else
    STALL_COUNT=0
    echo "  停滞检测: 差距减少中 (之前: $PREV_GAPS → 当前: $GAPS_FOUND)"
  fi

  PREV_GAPS=$GAPS_FOUND

  # === 步骤 5c: 开发缺失技能 ===
  if [[ "$GAPS_FOUND" -gt "$MIN_GAPS" ]] && [[ "$ROUND" -lt "$MAX_ROUNDS" ]]; then
    echo ""
    echo "→ Agent 开发缺失技能..."
    # Agent 行为:
    # 1. 读取 checklist.json，筛选 status != "covered" 的项
    # 2. 对每个缺失项: 分析实践要求 → 设计技能 → 创建 SKILL.md → 注册
    # 3. 更新 CLAUDE.md 和 ARCHITECTURE.md
    # 4. 运行 review --diff 和 qa-gate 验证新技能

    # 如果 STOP_ON_REVIEW=true，暂停等待人工确认
    if $STOP_ON_REVIEW; then
      echo ""
      echo "⏸ 暂停等待确认 (STOP_ON_REVIEW)"
      # Agent 使用 AskUserQuestion 询问
      echo "提示: 开发完成，确认继续下一轮分析？"
    fi
  fi
done

# 设置终止原因（如果循环自然结束）
if [[ -z "$TERMINATION_REASON" ]]; then
  if [[ "$GAPS_FOUND" -le "$MIN_GAPS" ]]; then
    TERMINATION_REASON="success"
  else
    TERMINATION_REASON="max_rounds"
  fi
fi
```

---

## 步骤 6: 最终报告

```bash
echo ""
echo "╔══════════════════════════════════════╗"

case "$TERMINATION_REASON" in
  success)
    echo "║  ✅ 成功 — 所有差距已补齐"
    echo "║  轮次: $ROUND, 剩余差距: $GAPS_FOUND"
    ;;
  stalled)
    echo "║  ⏹ 停滞 — 连续 $STALL_LIMIT 轮差距不减少"
    echo "║  轮次: $ROUND, 剩余差距: $GAPS_FOUND"
    ;;
  max_rounds)
    echo "║  ⏹ 上限 — 达到最大轮次 $MAX_ROUNDS"
    echo "║  剩余差距: $GAPS_FOUND"
    ;;
esac

echo "╚══════════════════════════════════════╝"

# 生成最终报告
python3 -c "
import json

report = {
    'final_round': $ROUND,
    'max_rounds': $MAX_ROUNDS,
    'termination_reason': '$TERMINATION_REASON',
    'total_gaps_remaining': $GAPS_FOUND,
    'min_gaps_threshold': $MIN_GAPS,
    'stall_limit': $STALL_LIMIT,
    'stall_count_at_termination': $STALL_COUNT,
    'rounds': []
}

# 读取所有轮次报告
import glob
round_files = sorted(glob.glob('$RALPH_DIR/ralph-round-*.json'))
for rf in round_files:
    with open(rf) as f:
        data = json.load(f)
        report['rounds'].append({
            'round': data.get('round'),
            'total_gaps': data.get('total_gaps', 0),
            'missing_count': len(data.get('missing_practices', [])),
            'partial_count': len(data.get('partial_practices', []))
        })

# 读取最终检查清单
with open('$RALPH_DIR/checklist.json') as f:
    report['final_checklist'] = json.load(f)

with open('$RALPH_DIR/ralph-final.json', 'w') as f:
    json.dump(report, f, indent=2, ensure_ascii=False)

print(f'最终报告: \$RALPH_DIR/ralph-final.json')
print(f'终止原因: {report[\"termination_reason\"]}')
print(f'轮次: {report[\"final_round\"]}')
print(f'剩余差距: {report[\"total_gaps_remaining\"]}')
" 2>/dev/null
```

### 完成状态

```bash
case "$TERMINATION_REASON" in
  success)
    echo ""
    echo "所有 Harness Engineering 实践均已覆盖"
    echo "覆盖清单:"
    python3 -c "
import json
with open('$RALPH_DIR/checklist.json') as f:
    for item in json.load(f)['items']:
        icon = '✅' if item['status'] == 'covered' else '⚠️'
        print(f\"  {icon} {item['practice']}: {item['status']}\")
" 2>/dev/null
    echo ""
    echo "后续:"
    echo "  /sns-workflow:ralph-loop  → 定期重新验证"
    echo "  /sns-workflow:qa-gate     → 提交前质量检查"
    ;;
  stalled)
    echo ""
    echo "⚠ 自动补齐停滞（连续 $STALL_LIMIT 轮差距不减少）"
    echo "未覆盖实践:"
    python3 -c "
import json
with open('$RALPH_DIR/checklist.json') as f:
    for item in json.load(f)['items']:
        if item['status'] != 'covered':
            print(f\"  ❌ [{item['status']}] {item['practice']}\")
" 2>/dev/null
    echo ""
    echo "建议:"
    echo "  1. 查看停滞报告: $RALPH_DIR/ralph-final.json"
    echo "  2. 手动补齐剩余差距后重新验证"
    echo "  3. 或放宽条件: --min-gaps 2"
    ;;
  max_rounds)
    echo ""
    echo "⚠ 达到最大轮次 ($MAX_ROUNDS)，仍有 $GAPS_FOUND 个差距"
    echo "未覆盖实践:"
    python3 -c "
import json
with open('$RALPH_DIR/checklist.json') as f:
    for item in json.load(f)['items']:
        if item['status'] != 'covered':
            print(f\"  ❌ [{item['status']}] {item['practice']}\")
" 2>/dev/null
    echo ""
    echo "继续:"
    echo "  /sns-workflow:ralph-loop --auto --max-rounds $((MAX_ROUNDS + 5))"
    ;;
esac
```

---

## 辅助: 差距基准线

维护一个差距基准线文件，记录每次分析的差距变化趋势。

```bash
# 更新差距基准线
python3 -c "
import json, os

baseline_file = '$RALPH_DIR/gap-baseline.json'
current_gaps = $GAPS_FOUND

baseline = {'rounds': []}
if os.path.exists(baseline_file):
    with open(baseline_file) as f:
        baseline = json.load(f)

baseline['rounds'].append({
    'round': $FINAL_ROUND,
    'gaps': current_gaps,
    'skill_count': $SKILL_COUNT
})
baseline['latest_gaps'] = current_gaps
baseline['latest_round'] = $FINAL_ROUND

with open(baseline_file, 'w') as f:
    json.dump(baseline, f, indent=2)

print(f'基准线已更新: \$baseline_file')
" 2>/dev/null

sns_skill_end "success"
```
