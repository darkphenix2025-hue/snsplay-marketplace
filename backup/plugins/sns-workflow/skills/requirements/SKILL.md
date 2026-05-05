---
name: sns-workflow:requirements
description: 收集需求并创建用户故事产物。简化的输出专注于验收标准和范围。支持多执行器分析与来源追踪。
user-invocable: true
allowed-tools: Read, Write, Bash, Glob, Grep, Task, TaskOutput, AskUserQuestion, WebSearch
---

# 需求阶段技能

从用户收集需求并创建用户故事产物。分发需求执行器，将结果综合为最小化的产物集。

**任务目录：** `${CLAUDE_PROJECT_DIR}/.snsplay/task/`

---

## 步骤 1: 加载配置与解析执行器

```bash
bun -e "
import { loadWorkflowConfig, getProviderType } from '${CLAUDE_PLUGIN_ROOT}/scripts/workflow-config.ts';
const config = loadWorkflowConfig();
const stage = config.stages['requirements'];
const executors = stage.executors.map(exec => ({
  ...exec,
  providerType: getProviderType(exec.preset)
}));
console.log(JSON.stringify({ executors }));
"
```

---

## 步骤 2: 检查 RCA 上下文

如果 `.snsplay/task/rca-diagnosis.json` 存在，则这是漏洞修复的需求阶段。读取诊断结果并将其作为需求执行器的上下文。

---

## 步骤 2a: 清理旧状态

删除先前运行遗留的澄清状态以避免误报：
```bash
rm -f .snsplay/task/user-story/status.json
```

---

## 步骤 3: 提示组装（防漂移）

**单个执行器（典型）：**
```
原始请求：{来自对话的用户原始请求}
---

你正在执行需求阶段。

{如果存在 RCA 上下文："漏洞修复上下文 —— 阅读 .snsplay/task/rca-diagnosis.json 获取根因。"}

从用户请求中收集需求。专注于：
1. 清晰的验收标准（Given/When/Then 格式）
2. 范围（in_scope / out_of_scope）
3. 每个 AC 必须包含 "source" 字段："original_request"、"user_answer" 或 "specialist_suggestion"
4. 超出原始请求的建议放入 "candidate_additions" —— 不要放入主 AC

不要添加原始请求中没有的功能。最多问 2-3 个澄清问题。

输出：将最小的用户故事产物写入 .snsplay/task/user-story/：
- meta.json（id, title, description）
- acceptance-criteria.json（数组，每个 AC 带 source 字段）
- scope.json（in_scope, out_of_scope, assumptions, candidate_additions）
- manifest.json（最后写入 —— 表示完成）

不要写 requirements.json 或 test-criteria.json（这些已移到规划器）。
```

**多执行器（带合成器的分析师）：**
如果配置了多个执行器进行需求分析：
1. 非合成器执行器（除最后一个外的所有）：每个写入一个分析文件。
   - **通过 name-helper 计算文件名**（确定性，无临时格式）：
     ```bash
     bun "${CLAUDE_PLUGIN_ROOT}/scripts/name-helper.ts" --type analysis --index {0-based-index} --system-prompt {system_prompt_name} --provider {preset_name} --model {model_name}
     ```
   - **分析文件格式：** 有效的 JSON（非 markdown）。必须可被 `JSON.parse()` 解析：
     ```json
     {"acceptance_criteria": [...], "scope": {...}, "risks": [...], "questions": [...]}
     ```
   - 根据并行/串行配置分发（将相邻的 `parallel: true` 分组 → 同时执行）
2. 最后一个执行器（合成器）最后运行，使用增强的提示：
   - 执行自己的需求分析
   - 同时读取所有先前的 `analysis-*.json` 文件
   - 综合并写入规范输出到 `user-story/`

   合成器提示增强（附加到常规需求提示后）：
   ```
   ---
   合成器模式：你是多执行器阶段中的最后一个执行器。

   先前的分析输出位于：
   {list of .snsplay/task/analysis-*.json paths}

   除了执行自己的需求分析外，你还必须：
   1. 阅读所有先前的分析输出（见上）
   2. 综合每个分析中的最佳验收标准
   3. 将最终合并的用户故事产物写入 .snsplay/task/user-story/

   重要提示：如果你不确定任何需求、范围决策或验收标准，
   不要假设。而是：
   1. 写入 .snsplay/task/user-story/status.json：
      {"status": "needs_clarification", "clarification_questions": ["Q1?", "Q2?"]}
   2. 不要写 manifest.json（这表示完成）
   3. 停止并让编排器处理向用户提问

   如果没有问题，继续写入所有产物包括 manifest.json。
   你的输出是权威结果。
   ```

**失败处理：**
- 如果非合成器执行器失败：记录失败，继续处理其余执行器
- 如果所有非合成器执行器都失败：合成器单独运行（单执行器模式）
- 如果合成器失败：向用户报告错误，保留任何 analysis-*.json 文件用于调试

---

## 步骤 4: 分发执行器

**使用阶段/角色组合解析系统提示。** 组合 `requirements` 阶段定义与执行器的角色提示：
```bash
bun -e "
import { loadStageDefinition, getSystemPrompt, composePrompt } from '${CLAUDE_PLUGIN_ROOT}/scripts/system-prompts.ts';
const stage = loadStageDefinition('requirements', '${CLAUDE_PLUGIN_ROOT}/stages');
const role = getSystemPrompt('{executor.system_prompt}', '${CLAUDE_PLUGIN_ROOT}/system-prompts/built-in');
if (!stage) { console.error('FATAL: Stage definition not found for requirements'); process.exit(1); }
if (!role) { console.error('FATAL: Role prompt not found: {executor.system_prompt}'); process.exit(1); }
console.log(composePrompt(stage, role));
"
```

使用组合作为系统提示内容，然后根据提供者类型路由：

- **subscription:** `Task(subagent_type: "general-purpose", model: "<model>", prompt: "<composed_prompt>\n---\n<assembled task prompt>")`
- **api:** `Bash(run_in_background: true)` → `api-task-runner.ts --stage-type requirements --system-prompt "${CLAUDE_PLUGIN_ROOT}/system-prompts/built-in/{executor.system_prompt}.md"` → `TaskOutput`
- **cli:** `Task(subagent_type: "general-purpose", prompt: "Run: bun cli-executor.ts --stage-type requirements ...")`

---

## 步骤 5: 检查澄清

合成器完成后，检查 `.snsplay/task/user-story/status.json`：

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

完成后验证：
1. `.snsplay/task/user-story/manifest.json` 存在且 `ac_count > 0`
2. `acceptance-criteria.json` 有带 `source` 字段的条目
3. `scope.json` 有 `in_scope` 和 `out_of_scope`
4. 如果 `scope.json` 中存在 `candidate_additions`，向用户呈现以获得批准

---

## 步骤 7: 报告结果

向用户呈现：
- 验收标准数量
- 关键范围项目
- 任何待批准的候选附加项
- 建议下一步：`/sns-workflow:plan`
