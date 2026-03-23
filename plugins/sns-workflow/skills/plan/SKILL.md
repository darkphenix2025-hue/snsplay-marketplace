---
name: sns-workflow:plan
description: 从现有需求创建详细的实现计划。读取用户故事产物，分发规划执行器，编写带测试用例和步骤到 AC 映射的计划。
user-invocable: true
allowed-tools: Read, Write, Bash, Glob, Grep, Task, TaskOutput, AskUserQuestion
---

# 规划阶段技能

从现有需求创建详细的实现计划。使用执行器系统分发规划代理。

**任务目录：** `${CLAUDE_PROJECT_DIR}/.snsplay/task/`

---

## 步骤 1: 验证输入

检查必需的输入产物是否存在：

```
必需：.snsplay/task/user-story/manifest.json（带 format_version 且 ac_count > 0）
可选：.snsplay/task/rca-diagnosis.json（如果存在则提供漏洞修复上下文）
```

如果 `user-story/manifest.json` 缺失，告诉用户先运行 `/sns-workflow:requirements`。

读取 `user-story/manifest.json` 并验证 `ac_count > 0`。读取 `user-story/acceptance-criteria.json` 获取完整的 AC 列表。

---

## 步骤 1a: 清理旧状态

删除先前运行遗留的澄清状态以避免误报：
```bash
rm -f .snsplay/task/plan/status.json
```

## 步骤 1b: 检查评审修复上下文

如果 `.snsplay/task/review-findings-to-fix.json` 存在，这是评审失败后的重新规划。读取该文件并将其 `must_fix` 发现注入到每个执行器提示中作为额外上下文：

```
评审发现需要解决：
以下 must_fix 发现由计划评审员提出。在修订计划中解决每一个：
{来自 review-findings-to-fix.json 的发现}
```

此文件由 `/sns-workflow:review --plan` 在评审循环触发重新规划时写入。

---

## 步骤 2: 加载配置与解析执行器

```bash
bun -e "
import { loadWorkflowConfig, getProviderType } from '${CLAUDE_PLUGIN_ROOT}/scripts/workflow-config.ts';
const config = loadWorkflowConfig();
const stage = config.stages['planning'];
const executors = stage.executors.map(exec => ({
  ...exec,
  providerType: getProviderType(exec.preset)
}));
console.log(JSON.stringify({ executors, max_tdd_iterations: config.max_tdd_iterations }));
"
```

解析输出以获取执行器列表及其系统提示、提供者类型、预设和模型。

---

## 步骤 3: 提示组装（防漂移）

为每个执行器组装提示：

```
原始请求：{来自对话上下文的用户原始请求}
---

你正在执行规划阶段。

阅读 .snsplay/task/user-story/manifest.json 处的用户故事，然后阅读所有章节文件。
{如果 rca-diagnosis.json 存在："同时阅读 .snsplay/task/rca-diagnosis.json 获取根因上下文。"}

根据规划代理的指示创建详细的实现计划。

关键要求：
1. 每个计划步骤必须包含 ac_ids[] 引用验收标准
2. 在 plan/test-plan.json 中编写映射到 AC ID 的测试用例
3. 步骤必须是原子的且可独立测试
4. 不要添加验收标准未证明的功能或步骤

使用多文件格式将输出写入 .snsplay/task/plan/（meta.json, steps/{N}.json, test-plan.json, risk-assessment.json, dependencies.json, files.json, 最后 manifest.json）。
```

---

## 步骤 4: 分发执行器

**使用阶段/角色组合解析系统提示。** 组合 `planning` 阶段定义与执行器的角色提示：
```bash
bun -e "
import { loadStageDefinition, getSystemPrompt, composePrompt } from '${CLAUDE_PLUGIN_ROOT}/scripts/system-prompts.ts';
const stage = loadStageDefinition('planning', '${CLAUDE_PLUGIN_ROOT}/stages');
const role = getSystemPrompt('{executor.system_prompt}', '${CLAUDE_PLUGIN_ROOT}/system-prompts/built-in');
if (!stage) { console.error('FATAL: Stage definition not found for planning'); process.exit(1); }
if (!role) { console.error('FATAL: Role prompt not found: {executor.system_prompt}'); process.exit(1); }
console.log(composePrompt(stage, role));
"
```

使用组合作为系统提示内容，然后根据提供者类型路由每个执行器：

- **subscription:** `Task(subagent_type: "general-purpose", model: "<model>", prompt: "<composed_prompt>\n---\n<assembled task prompt>")`
- **api:** `Bash(run_in_background: true)` → `api-task-runner.ts --preset <preset> --model <model> --stage-type planning --system-prompt "${CLAUDE_PLUGIN_ROOT}/system-prompts/built-in/{executor.system_prompt}.md" --task-stdin` → `TaskOutput(timeout: min(timeout_ms + 120000, 600000))`
- **cli:** `Task(subagent_type: "general-purpose", prompt: "Run: bun '${CLAUDE_PLUGIN_ROOT}/scripts/cli-executor.ts' --stage-type planning ...")`

**单个执行器（常见情况）：** 直接路由 —— 写入 `.snsplay/task/plan/`。无变体间接。

**多个执行器（带合成器的多规划器）：**
非合成器规划器（除最后一个外）各自写入单独的变体目录：
- **通过 name-helper 计算 dirname**（确定性，无临时格式）：
  ```bash
  bun "${CLAUDE_PLUGIN_ROOT}/scripts/name-helper.ts" --type plan-variant --index {0-based-index} --system-prompt {system_prompt_name} --provider {preset_name} --model {model_name}
  ```
- 修改组装的提示："使用多文件格式将输出写入 .snsplay/task/{computed_dirname}/。"

根据并行/串行配置分发（将相邻的 `parallel: true` 分组 → 同时执行）。

最后一个执行器（合成器）最后运行，使用增强的提示 —— 它进行自己的规划并阅读所有先前的变体：
```
---
合成器模式：你是多执行器规划阶段中的最后一个规划器。

先前的计划变体位于：
{list of .snsplay/task/plan-{index}-*/manifest.json paths}

除了创建自己的计划外，你还必须：
1. 阅读上面列出的所有先前计划变体
2. 合并每个变体的最佳元素
3. 将最终的合成计划写入 .snsplay/task/plan/（标准多文件格式）
4. 在 meta.json 中注意哪个变体贡献了关键决策

重要提示：如果你不确定任何架构决策、步骤顺序或范围边界，
不要假设。而是：
1. 写入 .snsplay/task/plan/status.json：
   {"status": "needs_clarification", "clarification_questions": ["Q1?", "Q2?"]}
2. 不要写 manifest.json（这表示完成）
3. 停止并让编排器处理向用户提问

如果没有问题，继续写入所有产物包括 manifest.json。
```

**合成后清理：** 仅在验证 `.snsplay/task/plan/manifest.json` 存在后：
```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/name-helper.ts" --type plan-variants --list --task-dir .snsplay/task | xargs -I{} rm -rf ".snsplay/task/{}"
```
如果合成失败，保留变体目录用于手动恢复。

**失败处理：**
- 非合成器失败：记录，继续处理其余
- 所有非合成器失败：合成器单独运行
- 合成器失败：不要清理变体，报告错误

---

## 步骤 5: 检查澄清

合成器完成后，检查 `.snsplay/task/plan/status.json`：

1. 如果存在且 `status == "needs_clarification"`：
   a. 读取 `clarification_questions[]` 数组
   b. 通过 AskUserQuestion 向用户呈现问题
   c. 收集答案
   d. 删除 `status.json`（防止旧状态）
   e. 仅重新分发合成器（最后一个执行器），使用相同的合成增强加上：
      ```
      澄清答案：
      - Q1? → A1
      - Q2? → A2
      ```
   f. 返回此步骤（最多 3 轮 —— 超过则升级给用户）
2. 如果 `status.json` 不存在，继续步骤 6

---

## 步骤 6: 验证输出

执行器完成后，验证：

1. `.snsplay/task/plan/manifest.json` 存在且 `step_count > 0`
2. 每个 `plan/steps/{N}.json` 文件存在且包含 `ac_ids[]`
3. `plan/test-plan.json` 存在且包含 `test_cases[]`

如果验证失败，向用户报告缺失的内容。

---

## 步骤 7: 报告结果

向用户呈现摘要：
- 计划标题和摘要
- 步骤数量
- 测试用例数量
- 合成自 {N} 个计划变体（如果使用了多规划器）
- 任何未映射的 AC（没有 ac_ids 的步骤）
- 建议下一步：`/sns-workflow:review --plan` 或 `/sns-workflow:implement`
