---
name: sns-workflow:review
description: 评审计划或实现。分发评审执行器，验证输出，并拥有评审→修复→再审阅循环。使用 --plan 进行计划评审，--code 进行代码评审。
user-invocable: true
allowed-tools: Read, Write, Bash, Glob, Grep, Task, TaskOutput, AskUserQuestion, Skill
---

# 评审阶段技能

评审计划或代码实现。使用执行器系统分发评审员。拥有完整的评审→修复→再审阅循环 —— 如果评审员发现 `must_fix` 问题，此技能自动分发修复阶段并重新评审。

**任务目录：** `${CLAUDE_PROJECT_DIR}/.snsplay/task/`
**用法：** `/sns-workflow:review --plan` 或 `/sns-workflow:review --code`

---

## 步骤 1: 确定评审类型

从用户调用中解析 `--plan` 或 `--code` 标志。

- `--plan` → 计划评审（使用 `stages['plan-review']` 执行器）
- `--code` → 代码评审（使用 `stages['code-review']` 执行器）
- 两者皆无 → 询问用户运行哪种评审

---

## 步骤 2: 验证输入

**对于计划评审（`--plan`）：**
```
必需：.snsplay/task/user-story/manifest.json
必需：.snsplay/task/plan/manifest.json
```

**对于代码评审（`--code`）：**
```
必需：.snsplay/task/user-story/manifest.json
必需：.snsplay/task/plan/manifest.json
必需：.snsplay/task/impl-result.json
```

如果任何必需产物缺失，告诉用户先运行哪个阶段。

---

## 步骤 3: 加载配置与解析执行器

```bash
bun -e "
import { loadWorkflowConfig, getProviderType } from '${CLAUDE_PLUGIN_ROOT}/scripts/workflow-config.ts';
const config = loadWorkflowConfig();
const stageType = '{plan-review or code-review}';
const stage = config.stages[stageType];
const executors = stage.executors.map(exec => ({
  ...exec,
  providerType: getProviderType(exec.preset)
}));
console.log(JSON.stringify({ executors, max_iterations: config.max_iterations }));
"
```

---

## 步骤 4: 提示组装（防漂移）

为每个执行器组装评审提示：

**计划评审提示：**
```
原始请求：{用户的原始请求}
---

你正在执行计划评审阶段。
你的系统提示名称是：{executor.system_prompt}
你的模型是：{executor.model}
设置 revision_number 为：{revision_number}

阅读 .snsplay/task/user-story/manifest.json 处的用户故事（然后各个部分）。
阅读 .snsplay/task/plan/manifest.json 处的计划（然后各个步骤文件）。

根据验收标准评审计划。对每个发现：
- 包含 contract_reference（关联哪个 AC、计划步骤或安全规则）
- 包含 evidence（具体 file:line 或计划引用）
- 设置 fix_type 为 must_fix（阻止批准）或 advisory（信息性）

重要提示：needs_changes 需要至少一个带证据的 must_fix 发现。仅 advisory 发现不能阻止批准。

将输出写入 .snsplay/task/{output_file}。
```

**代码评审提示：**
```
原始请求：{用户的原始请求}
---

你正在执行代码评审阶段。
你的系统提示名称是：{executor.system_prompt}
你的模型是：{executor.model}
设置 revision_number 为：{revision_number}

阅读用户故事、计划和实现结果。
根据验收标准和计划评审实现。

对每个发现：
- 包含 contract_reference、evidence 和 fix_type
- needs_changes 需要至少一个 must_fix 发现

将输出写入 .snsplay/task/{output_file}。
```

---

## 步骤 5: 分发执行器

为每个执行器确定输出文件名。如果 `workflow-tasks.json` 存在且包含 `stages[]` 条目，使用此执行器存储的 `output_file`。否则计算：

```bash
bun -e "
import { getV3OutputFileName } from '${CLAUDE_PLUGIN_ROOT}/types/stage-definitions.ts';
console.log(getV3OutputFileName('{stage-type}', '{executor-name}', {index}, '{preset}', '{model}', 1));
"
```

**使用阶段/角色组合解析系统提示**。阶段类型取决于评审类型：`plan-review`（对于 `--plan`）或 `code-review`（对于 `--code`）。

**对于 subscription 分发**，将阶段定义和角色提示组合为单个系统提示：
```bash
bun -e "
import { loadStageDefinition, getSystemPrompt, composePrompt } from '${CLAUDE_PLUGIN_ROOT}/scripts/system-prompts.ts';
const stage = loadStageDefinition('{plan-review|code-review}', '${CLAUDE_PLUGIN_ROOT}/stages');
const role = getSystemPrompt('{executor.system_prompt}', '${CLAUDE_PLUGIN_ROOT}/system-prompts/built-in');
if (!stage) { console.error('FATAL: Stage definition not found for {plan-review|code-review}'); process.exit(1); }
if (!role) { console.error('FATAL: Role prompt not found: {executor.system_prompt}'); process.exit(1); }
console.log(composePrompt(stage, role));
"
```
使用组合作为 Task 分发中的系统提示内容：

- **subscription:** `Task(subagent_type: "general-purpose", model: "<model>", prompt: "<composed_prompt>\n---\n<assembled review prompt>")`
- **api:** `Bash(run_in_background: true)` → `api-task-runner.ts` 带 `--stage-type {plan-review|code-review} --system-prompt "${CLAUDE_PLUGIN_ROOT}/system-prompts/built-in/{executor.system_prompt}.md"`（阶段定义通过 --stage-type 自动解析，角色提示通过 --system-prompt）
- **cli:** `Task(subagent_type: "general-purpose", prompt: "Run: bun cli-executor.ts --stage-type {plan-review|code-review} ...")` —— 传递 `--changes-summary` 与评审员身份和 revision_number，以便 CLI 提示包含它们

- 将相邻的 `parallel: true` 执行器分组 → 同时分发，等待全部完成
- 顺序执行器 → 一次分发一个，等待每个完成

**关键：你必须分发所有配置的执行器。** 不要跳过任何执行器 —— 即使先前的评审员已经批准。最后一个顺序执行器（合成器）专门为跨模型验证配置。跳过它会破坏多评审工作流的目的。配置中的每个执行器都有存在的理由。

---

## 步骤 6: 验证与聚合结果

所有执行器完成后，在聚合前验证每个输出文件：

**验证（聚合前必需）：**
1. **验证所有执行器输出存在** —— 根据执行器列表计数输出文件。如果任何执行器的输出文件缺失，该执行器未被分发。这是分发失败 —— 返回步骤 5 分发缺失的执行器。不要聚合部分结果。
2. 解析 JSON —— 如果无效，视为**阶段失败**（不要跳过）
3. 验证必需字段：`id`, `reviewer`, `model`, `revision_number`, `status`, `summary`, `findings`
   - 计划评审：还需要 `requirements_coverage`
   - 代码评审：还需要 `acceptance_criteria_verification`, `checklist`
4. 验证 `status` 是以下之一：`approved`, `needs_changes`, `needs_clarification`, `rejected`
5. 验证任何 `needs_changes` 状态至少有一个带 `contract_reference` 和 `evidence` 的 `must_fix` 发现
6. **如果任何评审员输出格式错误或缺失 → 报告哪个执行器失败并要求用户重新运行。不要用部分结果继续。**

**聚合（仅当所有输出有效时）：**

当配置多个执行器时，所有评审员（包括合成器 —— 最后一个执行器）写入单独的评审文件。合成器进行自己的评审，并可能去重/总结先前评审员的发现，但它不能压制 `must_fix` 发现。

1. 收集所有评审员的所有发现
2. 确定总体状态：
   - 如果任何评审员返回带 `must_fix` 发现的 `needs_changes` → 总体 `needs_changes`
   - 如果全部返回 `approved` → 总体 `approved`
   - 如果任何返回 `needs_clarification` → 总体 `needs_clarification`
   - 如果任何返回 `rejected` → 总体 `rejected`
3. 向用户呈现聚合结果：
   - 每个评审员的状态
   - 合并的 must_fix 发现
   - 合并的 advisory 发现
   - 缺失的 AC 覆盖率

---

## 步骤 7: 评审→修复→再审阅循环

聚合后，处理结果。`max_iterations` 是每个评审阶段的预算。

```
iteration = 0
WHILE aggregated_status == 'needs_changes' AND iteration < max_iterations:
  7a. 收集所有评审员的所有 must_fix 发现
  7b. 写入 .snsplay/task/review-findings-to-fix.json:
      { "findings": [<聚合的 must_fix 发现>], "review_type": "plan|code" }
  7c. 向用户呈现发现摘要
  7d. 通过 Skill 工具分发修复：
      - 如果 --plan: Skill(skill: "sns-workflow:plan")
      - 如果 --code: Skill(skill: "sns-workflow:implement")
  7e. 删除 .snsplay/task/review-findings-to-fix.json
  7f. 准备重新分发：
      - 记录 expected_revision = 当前 revision_number + 1
      - 删除所有预期的评审输出文件（防止旧文件通过验证）
  7g. 重新分发所有评审员：
      - 在提示中传递 expected_revision:
        "这是复审修订版 {expected_revision}。设置 revision_number 为 {expected_revision}。"
      - 对于 CLI 执行器：使用 --resume 标志与 --changes-summary
      - 写入相同的输出文件（使用 workflow-tasks.json 中存储的 output_file）
  7h. 重新验证和重新聚合（重复步骤 6）
      - 额外验证每个输出的 revision_number === expected_revision（拒绝旧输出）
  7h. iteration++

IF aggregated_status == 'needs_clarification':
  → 通过 AskUserQuestion 提出合并的 clarification_questions
  → 用户回应后，重新分发评审员（不消耗迭代预算）

IF aggregated_status == 'rejected':
  → 向用户呈现拒绝，停止（不消耗迭代次数）

IF aggregated_status == 'approved':
  → 向用户报告批准，建议下一步
```

---

## 步骤 8: 报告

向用户呈现最终的聚合评审并建议下一步：
- 如果批准 → `/sns-workflow:implement`（对于计划评审）或 "完成"（对于代码评审）
- 如果 max_iterations 后仍需修改 → 报告剩余 must_fix 发现，建议手动修复
- 如果被拒绝 → 建议重大返工或从头开始 `/sns-workflow:plan`
