---
name: sns-workflow:review
description: Agent 交叉审查 —— 两个独立视角审查代码变更/计划/实现，合成综合审查报告。安全+正确性视角 vs 架构+可维护性视角，降低单次审查盲区。
user-invocable: true
allowed-tools: Bash, Read, Write, Grep, Glob
---

# Agent 交叉审查

通过两个独立视角对代码变更、计划或实现进行交叉审查，降低单次审查盲区。

**审查范围**:
- `--diff`（默认）：审查暂存区变更（git diff --cached）
- `--plan`：审查计划产物（`.snsplay/task/plan/`）
- `--code`：审查实现产物（`.snsplay/task/impl-result.json`）

**审查视角**:
- **视角 A**（安全 + 正确性）：输入验证、注入防护、错误处理、边界条件、数据暴露
- **视角 B**（架构 + 可维护性）：代码组织、命名、抽象、可测试性、耦合度

---

## 步骤 1: 检测审查目标

```bash
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")
TASK_DIR="$ROOT/.snsplay/task"

MODE="diff"
for arg in "$@"; do
  case "$arg" in
    --plan) MODE="plan" ;;
    --code) MODE="code" ;;
    --diff) MODE="diff" ;;
  esac
done

echo "=== 交叉审查 ==="
echo "审查模式: $MODE"

# 检查产物依赖
if [[ "$MODE" == "plan" ]] && [[ ! -f "$TASK_DIR/plan/manifest.json" ]]; then
  echo "错误: 缺少计划产物 ($TASK_DIR/plan/manifest.json)"
  echo "请先运行规划阶段"
  exit 1
fi

if [[ "$MODE" == "code" ]] && [[ ! -f "$TASK_DIR/impl-result.json" ]]; then
  echo "错误: 缺少实现产物 ($TASK_DIR/impl-result.json)"
  echo "请先运行实现阶段"
  exit 1
fi
```

---

## 步骤 2: 收集上下文

根据审查模式收集相关上下文。

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REVIEW_ID="review-${TIMESTAMP}"

if [[ "$MODE" == "diff" ]]; then
  DIFF=$(git diff --cached --stat 2>/dev/null)
  FULL_DIFF=$(git diff --cached 2>/dev/null)
  CHANGED_FILES=$(git diff --cached --name-only 2>/dev/null)
  echo ""
  echo "=== 变更统计 ==="
  echo "${DIFF:-(无暂存变更)}"
  echo ""
  echo "变更文件:"
  echo "${CHANGED_FILES:-(无)}"
fi

if [[ "$MODE" == "plan" ]]; then
  echo ""
  echo "=== 计划产物 ==="
  if [[ -f "$TASK_DIR/plan/manifest.json" ]]; then
    cat "$TASK_DIR/plan/manifest.json"
  fi
  echo ""
  echo "=== 计划步骤 ==="
  ls "$TASK_DIR/plan/steps/"*.json 2>/dev/null || echo "无计划步骤"
  echo ""
  if [[ -f "$TASK_DIR/user-story/manifest.json" ]]; then
    echo "=== 用户故事 ==="
    cat "$TASK_DIR/user-story/manifest.json"
  fi
fi

if [[ "$MODE" == "code" ]]; then
  echo ""
  echo "=== 实现结果 ==="
  if [[ -f "$TASK_DIR/impl-result.json" ]]; then
    cat "$TASK_DIR/impl-result.json"
  fi
  echo ""
  echo "=== 实现步骤 ==="
  ls "$TASK_DIR/impl-steps/"*.json 2>/dev/null || echo "无实现步骤文件"
  echo ""
  if [[ -f "$TASK_DIR/plan/manifest.json" ]]; then
    echo "=== 原始计划 ==="
    cat "$TASK_DIR/plan/manifest.json"
  fi
fi
```

---

## 步骤 3: 视角 A — 安全 + 正确性审查

**审查指令**: 以下是一个独立的审查任务。请仅从**安全和正确性**视角审查以下内容，忽略架构和风格问题。

**审查范围**:
- **输入验证**: 外部输入是否经过校验和消毒
- **注入防护**: SQL/命令/路径注入风险
- **权限控制**: 是否有越权操作
- **错误处理**: 异常是否被正确捕获和处理，错误信息是否泄露敏感细节
- **边界条件**: 空值、边界值、并发场景
- **数据暴露**: 日志/输出中是否包含密钥、token、用户数据
- **依赖安全**: 是否使用未经验证的三方代码路径

**审查对象**:
- 模式 `diff`: 审查上方 git diff 中的全部变更
- 模式 `plan`: 审查 `$TASK_DIR/plan/manifest.json` 及相关步骤文件
- 模式 `code`: 审查 `$TASK_DIR/impl-result.json` 及相关实现步骤

**输出要求**: 为每个发现生成以下 JSON 对象:
```
{
  "id": "A-001",
  "severity": "critical|high|medium|low|info",
  "category": "injection|auth|data_exposure|edge_case|error_handling|dependency",
  "location": "相对路径:行号",
  "description": "问题描述",
  "suggestion": "修复建议",
  "evidence": "相关代码片段"
}
```

如果无任何发现，输出 `[]` 并声明"安全+正确性审查通过"。

---

## 步骤 4: 视角 B — 架构 + 可维护性审查

**审查指令**: 以下是一个独立的审查任务。请仅从**架构和可维护性**视角审查以下内容，忽略安全和权限问题。这是**第二次独立审查**，不要重复视角 A 的发现。

**审查范围**:
- **内聚性**: 模块职责是否清晰单一
- **耦合度**: 模块间依赖是否合理
- **命名**: 变量/函数/文件命名是否自解释
- **可测试性**: 代码是否易于单元测试
- **抽象层次**: 是否存在过度抽象或抽象泄漏
- **重复代码**: 是否存在可提取的重复逻辑
- **文件组织**: 文件结构和目录布局是否合理
- **技术债务**: 是否引入临时方案或未清理的遗留代码

**审查对象**: 与步骤 3 相同的审查对象

**输出要求**: 为每个发现生成以下 JSON 对象:
```
{
  "id": "B-001",
  "severity": "critical|high|medium|low|info",
  "category": "cohesion|coupling|naming|testability|abstraction|duplication|organization|tech_debt",
  "location": "相对路径:行号",
  "description": "问题描述",
  "suggestion": "修复建议",
  "evidence": "相关代码片段"
}
```

如果无任何发现，输出 `[]` 并声明"架构+可维护性审查通过"。

---

## 步骤 5: 综合去重与优先级排序

将视角 A 和视角 B 的发现合并：

1. **去重**: 同一文件 + 相似问题的发现合并（标记为 "dup_detected"，保留更详细的版本）
2. **分类**: 按 fix_type 分为:
   - `must_fix`（critical/high severity，阻止批准）
   - `advisory`（medium/low/info，信息性建议）
3. **排序**: must_fix 按 severity 降序，advisory 按 severity 降序
4. **判定**:
   - 存在 must_fix → `overall_status: "needs_changes"`
   - 无 must_fix → `overall_status: "approved"`

将完整结果写入 `$TASK_DIR/review-${TIMESTAMP}.json`，格式如下:
```json
{
  "id": "review-${TIMESTAMP}",
  "review_type": "${MODE}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "files_reviewed": ["变更文件列表"],
  "diff_summary": "简要变更说明",
  "pass_a": {
    "perspective": "security+correctness",
    "findings": [视角 A 的全部发现]
  },
  "pass_b": {
    "perspective": "architecture+maintainability",
    "findings": [视角 B 的全部发现]
  },
  "synthesis": {
    "must_fix": [必须修复的发现],
    "advisory": [建议性发现],
    "deduplicated": 去重数量,
    "overall_status": "approved|needs_changes",
    "summary": "综合审查结论（2-3 句话）"
  }
}
```

确保 artifact 文件存在且内容完整。如果 `$TASK_DIR` 不存在，先 `mkdir -p "$TASK_DIR"`。

---

## 步骤 6: 汇总报告

输出审查结论:

```bash
ARTIFACT="$TASK_DIR/review-${TIMESTAMP}.json"
if [[ -f "$ARTIFACT" ]]; then
  echo ""
  echo "=== review 完成 ==="
  echo "审查 ID: ${REVIEW_ID}"
  echo "审查模式: $MODE"
  echo "Artifact: $ARTIFACT"

  # 统计发现
  MUST_FIX_COUNT=$(grep -c '"severity": "critical"\|"severity": "high"' "$ARTIFACT" 2>/dev/null || echo "0")
  ADVISORY_COUNT=$(grep -c '"severity": "medium"\|"severity": "low"\|"severity": "info"' "$ARTIFACT" 2>/dev/null || echo "0")

  echo ""
  echo "审查结果:"
  echo "  must_fix: $MUST_FIX_COUNT 项"
  echo "  advisory: $ADVISORY_COUNT 项"
  echo ""

  if [[ "$MUST_FIX_COUNT" -gt 0 ]]; then
    echo "状态: needs_changes — 需要修复 $MUST_FIX_COUNT 项问题后再提交"
  else
    echo "状态: approved — 审查通过"
  fi
else
  echo "错误: 审查 artifact 未生成"
  exit 1
fi
```
