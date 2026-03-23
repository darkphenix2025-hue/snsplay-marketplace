---
name: sns-workflow:rca
description: 漏洞根因分析。并行分发 RCA 执行器，将发现合并为单一诊断产物。仅输出诊断 —— 不创建用户故事或计划。
user-invocable: true
allowed-tools: Read, Write, Bash, Glob, Grep, Task, TaskOutput, AskUserQuestion
---

# RCA 阶段技能

通过分发根因分析执行器来诊断漏洞。将发现合并为单一诊断产物。不创建用户故事或计划 —— 用户接下来链接到 `/sns-workflow:requirements` → `/sns-workflow:plan`。

**任务目录：** `${CLAUDE_PROJECT_DIR}/.snsplay/task/`

---

## 步骤 1: 加载配置与解析执行器

```bash
bun -e "
import { loadWorkflowConfig, getProviderType } from '${CLAUDE_PLUGIN_ROOT}/scripts/workflow-config.ts';
const config = loadWorkflowConfig();
const stage = config.stages['rca'];
const executors = stage.executors.map(exec => ({
  ...exec,
  providerType: getProviderType(exec.preset)
}));
console.log(JSON.stringify({ executors }));
"
```

---

## 步骤 2: 提示组装（防漂移）

为每个 RCA 执行器：

```
原始请求：{来自对话的用户漏洞描述}
---

你正在执行根因分析阶段。

诊断上述漏洞。不要修复 —— 仅诊断。

1. 复现漏洞（如果可能）
2. 从症状到源头追踪数据流
3. 用证据识别根因
4. 记录受影响的文件和修复约束

将输出写入 .snsplay/task/{output_file}

输出 JSON 格式：
{
  "root_cause": { "summary": "...", "category": "logic|config|dependency|concurrency|..." },
  "root_file": "path/to/file.ts",
  "root_line": 42,
  "confidence": "high|medium|low",
  "affected_files": ["..."],
  "fix_constraints": ["minimal change", "..."],
  "evidence": ["trace of how you found it"],
  "excluded_hypotheses": ["things you ruled out and why"]
}
```

---

## 步骤 3: 确定输出文件名

为每个执行器计算输出文件名：

```bash
bun -e "
import { getV3OutputFileName } from '${CLAUDE_PLUGIN_ROOT}/types/stage-definitions.ts';
console.log(getV3OutputFileName('rca', '{executor-name}', {index}, '{preset}', '{model}', 1));
"
```

---

## 步骤 4: 分发执行器

**使用阶段/角色组合解析系统提示。** 组合 `rca` 阶段定义与执行器的角色提示：
```bash
bun -e "
import { loadStageDefinition, getSystemPrompt, composePrompt } from '${CLAUDE_PLUGIN_ROOT}/scripts/system-prompts.ts';
const stage = loadStageDefinition('rca', '${CLAUDE_PLUGIN_ROOT}/stages');
const role = getSystemPrompt('{executor.system_prompt}', '${CLAUDE_PLUGIN_ROOT}/system-prompts/built-in');
if (!stage) { console.error('FATAL: Stage definition not found for rca'); process.exit(1); }
if (!role) { console.error('FATAL: Role prompt not found: {executor.system_prompt}'); process.exit(1); }
console.log(composePrompt(stage, role));
"
```

使用组合作为系统提示内容，然后根据提供者类型路由：

- **subscription:** `Task(subagent_type: "general-purpose", model: "<model>", prompt: "<composed_prompt>\n---\n<assembled RCA prompt>")`
- **api:** `Bash(run_in_background: true)` → `api-task-runner.ts --stage-type rca --system-prompt "${CLAUDE_PLUGIN_ROOT}/system-prompts/built-in/{executor.system_prompt}.md"`
- **cli:** `Task(subagent_type: "general-purpose", prompt: "Run: bun cli-executor.ts --stage-type rca ...")`

将相邻的 `parallel: true` 执行器分组 → 同时分发。顺序执行器 → 一次分发一个。

---

## 步骤 5: 合并发现

所有 RCA 执行器完成后，读取所有输出文件并合并：

**多执行器带合成器：**
当配置多个执行器时，所有分析师（包括合成器 —— 最后一个执行器）使用现有的 v3 输出模式写入单独的 RCA 文件。合成器进行自己的根因分析并阅读先前的输出以形成诊断。

下面的合并逻辑在所有 RCA 输出（包括合成器的）上运行。合成器不能覆盖分歧仲裁 —— 如果诊断冲突，技能仍然通过 AskUserQuestion 升级给用户。

1. **如果 RCA 一致**（相同的 root_file，相似的 root_cause）：
   - 使用最详细的诊断
   - 合并所有证据

2. **如果 RCA 不一致**（不同的 root_file 或矛盾的根因）：
   - 通过 AskUserQuestion 向用户呈现两个诊断
   - 询问："两个分析对根因的判断不一致。哪个正确？"
   - 包含每个的摘要
   - 使用用户的选择

3. **写入合并的诊断**到 `.snsplay/task/rca-diagnosis.json`：
```json
{
  "root_cause": "...",
  "root_file": "path/to/file.ts",
  "root_line": 42,
  "confidence": "high",
  "affected_files": ["..."],
  "fix_constraints": ["..."],
  "evidence": ["..."],
  "sources": ["rca-executor1-...", "rca-executor2-..."]
}
```

---

## 步骤 6: 报告结果

向用户呈现合并的诊断：
- 根因摘要
- 根文件和行号
- 置信度
- 受影响的文件
- 修复约束

建议下一步：
- `/sns-workflow:requirements`（从 RCA 上下文创建最小用户故事）
- 然后 `/sns-workflow:plan` → `/sns-workflow:implement`
