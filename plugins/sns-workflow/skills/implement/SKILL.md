---
name: sns-workflow:implement
description: 使用 TDD 循环实现计划。逐步分发实现执行器，每个步骤后运行测试，修复失败。每个步骤 5 次失败后升级给用户。
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, TaskOutput, AskUserQuestion
---

# 实现阶段技能

使用 TDD 循环实现已批准的计划。技能编排实现代理逐步执行，每个步骤后运行测试以确保准确性。

**任务目录：** `${CLAUDE_PROJECT_DIR}/.snsplay/task/`

---

## 步骤 1: 验证输入

```
必需：.snsplay/task/user-story/manifest.json
必需：.snsplay/task/plan/manifest.json（带 step_count > 0）
必需：.snsplay/task/plan/test-plan.json（带 test_cases[]）
```

读取 `plan/manifest.json` 获取 `step_count`。读取 `plan/test-plan.json` 获取测试用例。

如果 `test-plan.json` 缺失或没有 `test_cases`，警告用户："未找到测试用例。TDD 循环将被禁用 —— 实现将在无自动化验证的情况下运行。"

## 步骤 1a: 检查评审修复上下文

如果 `.snsplay/task/review-findings-to-fix.json` 存在，这是代码评审失败后的重新实现。读取该文件并将其 `must_fix` 发现注入到实现器提示中作为额外上下文：

```
评审发现需要修复：
以下 must_fix 发现由代码评审员提出。在实现中修复每一个：
{来自 review-findings-to-fix.json 的发现}
```

此文件由 `/sns-workflow:review --code` 在评审循环触发重新实现时写入。

---

## 步骤 2: 加载配置与解析执行器

```bash
bun -e "
import { loadWorkflowConfig, getProviderType } from '${CLAUDE_PLUGIN_ROOT}/scripts/workflow-config.ts';
const config = loadWorkflowConfig();
const stage = config.stages['implementation'];
const executors = stage.executors.map(exec => ({
  ...exec,
  providerType: getProviderType(exec.preset)
}));
console.log(JSON.stringify({ executors, max_tdd_iterations: config.max_tdd_iterations }));
"
```

实现通常使用单个执行器。如果配置了多个，使用第一个（实现本质上是顺序的 —— 一次只有一个代理应该修改代码）。

---

## 步骤 3: TDD 循环

**关键：此循环由本技能编排，而非实现器代理。实现器绝不与用户交互。**

```
对每个计划步骤 N = 1 到 step_count：

  iteration = 0
  step_passed = false

  当 NOT step_passed 且 iteration < max_tdd_iterations：

    3a. 组装实现器提示：
        原始请求：{用户的原始请求}
        ---
        SINGLE_STEP_MODE：仅实现第 {N} 步，共 {step_count} 步。
        阅读 .snsplay/task/plan/steps/{N}.json 处的计划步骤
        阅读 .snsplay/task/user-story/manifest.json 处的用户故事
        {如果 iteration > 0："先前尝试失败。测试失败：\n{failure_output}\n修复问题。"}
        将实现结果写入 .snsplay/task/impl-steps/impl-step-{N}-v{iteration+1}.json

    3b. 使用阶段/角色组合为 `implementation` 阶段解析系统提示：
        ```bash
        bun -e "
        import { loadStageDefinition, getSystemPrompt, composePrompt } from '${CLAUDE_PLUGIN_ROOT}/scripts/system-prompts.ts';
        const stage = loadStageDefinition('implementation', '${CLAUDE_PLUGIN_ROOT}/stages');
        const role = getSystemPrompt('{executor.system_prompt}', '${CLAUDE_PLUGIN_ROOT}/system-prompts/built-in');
        if (!stage) { console.error('FATAL: Stage definition not found for implementation'); process.exit(1); }
        if (!role) { console.error('FATAL: Role prompt not found: {executor.system_prompt}'); process.exit(1); }
        console.log(composePrompt(stage, role));
        "
        ```
        使用组合提示通过提供者路由分发：
        - subscription: Task 带组合提示
        - api: api-task-runner.ts 带 --stage-type implementation --system-prompt "${CLAUDE_PLUGIN_ROOT}/system-prompts/built-in/{executor.system_prompt}.md"
        - cli: cli-executor.ts 带 --stage-type implementation

    3c. 运行 test-plan.json 中的相关测试：
        - 从 .snsplay/task/plan/test-plan.json 读取 test_cases
        - 过滤：test_cases 的 steps[] 数组包含当前步骤 N
        - 对每个匹配的 test_case，通过 Bash 运行其命令：
          ```
          Bash(command: test_case.command, timeout: 120000)
          ```
        - 检查退出码：0 = 通过，非零 = 失败
        - 如果定义了，同时检查输出与 test-plan 的 success_pattern / failure_pattern
        - 收集所有结果：{ test_id, ac_ids, command, passed: boolean, output: string }

    3d. 如果所有测试通过：
        step_passed = true
        记录："步骤 {N}：所有 {count} 个测试通过"
        继续下一步骤

    3e. 如果任何测试失败：
        iteration++
        failure_output = 连接失败的测试输出（每个前 500 字符）
        记录："步骤 {N}：{failed_count}/{total_count} 个测试失败（迭代 {iteration}/{max_tdd_iterations}）"

        如果 iteration >= max_tdd_iterations：
          停止 —— 通过 AskUserQuestion 升级给用户：
          "步骤 {N} 在 {max_tdd_iterations} 次尝试后失败。

           失败的测试：
           {每个失败：- {test_case.description}（AC: {ac_ids}）}

           最后失败输出：
           {failure_output}

           你希望如何继续？"

          选项：
          1. "手动修复并重新运行 /sns-workflow:implement"
          2. "调整测试并重新运行"
          3. "跳过此步骤并继续"

          如果选择 3（跳过）：标记步骤为跳过，继续步骤 N+1
          如果选择 1 或 2：停止执行，用户处理

在所有步骤完成后：
  3f. 运行完整测试套件 —— 执行 test-plan.json 中的所有测试命令：
      ```
      对 test_plan.test_cases 中的每个 test_case：
        Bash(command: test_case.command, timeout: 120000)
      ```
      同时运行 test_plan.commands 中的全局测试命令（例如 "npm test"）：
      ```
      对 test_plan.commands 中的每个命令：
        Bash(command: command, timeout: 120000)
      ```
      收集结果：{ total_tests, passed, failed, skipped_steps }

  3g. 写入最终的 .snsplay/task/impl-result.json：
      ```json
      {
        "status": "complete|partial",
        "steps_completed": N,
        "steps_total": step_count,
        "steps_skipped": [跳过的步骤编号列表],
        "files_modified": ["来自 git diff --name-only 的列表"],
        "files_created": ["新文件列表"],
        "test_results": {
          "total": N,
          "passed": N,
          "failed": N,
          "details": [{ "test_id": "...", "ac_ids": [...], "passed": true|false }]
        }
      }
      ```
```

---

## 步骤 4: 验证输出

循环完成后：
1. `.snsplay/task/impl-result.json` 存在且包含 `status` 字段
2. 所有计划的文件已创建/修改
3. 最终测试套件结果

---

## 步骤 5: 报告结果

向用户呈现：
- 已完成步骤 / 总计
- 测试结果（通过 / 失败）
- 修改/创建的文件
- 建议下一步：`/sns-workflow:review --code`

---

## 回退：无测试计划

如果 `test-plan.json` 缺失或没有 `test_cases`：
- 跳过 TDD 循环
- 一次性分发实现器处理所有步骤（非单步模式）
- 无自动化测试验证
- 警告用户防漂移执行减弱
