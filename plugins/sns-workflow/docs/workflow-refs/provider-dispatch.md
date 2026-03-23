# 工作流提供者分发路由

> **何时执行**：从主循环（步骤 5c）分发任务到代理时，或从分阶段实现循环分发实现者和评审员时。

---

## 按提供者类型路由

从 `workflow-tasks.json` 的 stages[] 读取阶段的 `providerType` 字段以确定路由：

### 如果 providerType 是 'subscription'

使用 Task 工具（无 `team_name` —— 一次性子代理）：

```
Task(subagent_type: "general-purpose", model: "<model>", prompt: "...")
// 不要添加 team_name 或 name 参数。这是一次性子代理，而非队友。
```

### 如果 providerType 是 'api'

使用 `api-task-runner.ts` —— 每个调用的脚本创建 V2 Agent SDK 会话，运行任务，然后退出。

**派生超时：** 读取 `~/.snsplay/ai-presets.json` -> 查找与阶段的 `provider` 名称匹配的预设 -> 读取 `timeout_ms`（如果未设置或查找失败则默认：300000）。

**重要提示：** Bash 工具有硬最大超时 600,000ms（10 分钟）。API 任务可能运行更长时间（例如 30 分钟）。始终使用 `run_in_background: true` 以防止 Bash 工具过早杀死进程。

```bash
# 使用 run_in_background: true 运行 —— 保存 task_id
bun "${CLAUDE_PLUGIN_ROOT}/scripts/api-task-runner.ts" \
  --preset "<stage.provider>" \
  --model "<stage.model>" \
  --cwd "${CLAUDE_PROJECT_DIR}" \
  --task-timeout "<timeout_ms>" \
  --task-stdin <<'TASK_EOF'
...prompt...
TASK_EOF
```

**仅对于评审阶段（plan-review、code-review）：** 在 api-task-runner.ts 调用中添加 `--system-prompt` 参数指向相应的评审指南：
- 计划评审：`"${CLAUDE_PLUGIN_ROOT}/rules/plan-review-guidelines.md"`
- 代码评审：`"${CLAUDE_PLUGIN_ROOT}/rules/code-review-guidelines.md"`

保存 `task_id` 以及工作流任务 ID、提供者和模型。如果未返回 `task_id`，视为分发失败 —— 不要在前景模式下重试。

然后轮询完成状态：
```
TaskOutput(task_id, block: true, timeout: min(timeout_ms + 120000, 600000))
```
如果 TaskOutput 返回但任务仍在运行（未完成），重复 `TaskOutput` 与 `timeout: 600000` 直到后台任务完成。

使用 `--task-stdin` 与 heredoc 以避免 OS argv 大小限制和 ps 暴露。
解析最终输出获取 JSON：`{ event: "complete", result: "..." }` 或 `{ event: "error", error: "..." }`。退出码 3 = 超时。
api-task-runner 创建带 Read/Write/Edit/Bash 的 V2 Agent SDK 会话 —— 它**可以**修改磁盘上的文件。API 提供者支持所有阶段类型包括实现和 RCA。

### 如果 providerType 是 'cli'

任务描述指定确切的 cli-executor.ts 调用与 `--output-file` 和可选 `--model` 标志：

```
Task(
  subagent_type: "general-purpose",
  prompt: "Run: bun '${CLAUDE_PLUGIN_ROOT}/scripts/cli-executor.ts' \
    --type {plan|code} \
    --plugin-root '${CLAUDE_PLUGIN_ROOT}' \
    --preset '{stage.provider}' \
    --model '{stage.model}' \
    --output-file '${CLAUDE_PROJECT_DIR}/.snsplay/task/{stage.output_file}'
  评审 {plan|code} 并将输出写入指定文件。"
  // 不要添加 team_name 或 name。这是一次性子代理，而非队友。
)
```

`--preset` 标志从 `~/.snsplay/ai-presets.json` 选择 CLI 预设。预设的 `args_template` 包含占位符（`{model}`、`{output_file}`、`{prompt}`、`{schema_path}`），执行器在运行时替换。

不要传递 model 参数到 Task 工具。模型通过 --model 标志传递给 cli-executor.ts。

### 阶段类型自动解析

`--stage-type` 标志启用从 `stages/{type}.md` 自动解析阶段定义。传递时，运行器加载阶段定义 markdown 并将其前置到系统提示内容。与 `--system-prompt` 结合注入角色提示文件 —— 运行器将 `stage + role` 组合到系统提示层。示例：

```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/api-task-runner.ts" \
  --preset "<stage.provider>" \
  --model "<stage.model>" \
  --stage-type "<stage.type>" \
  --system-prompt "${CLAUDE_PLUGIN_ROOT}/system-prompts/built-in/<role>.md" \
  --cwd "${CLAUDE_PROJECT_DIR}" \
  --task-timeout "<timeout_ms>" \
  --task-stdin <<'TASK_EOF'
...prompt...
TASK_EOF
```

当提供 `--stage-type` 时，运行器从 `stages/` 自动解析阶段定义。`--system-prompt` 标志提供角色提示内容。两者结合将 `stage_definition + role_prompt` 组合作为会话的系统提示。如果省略 `--system-prompt`，仅使用阶段定义（无角色视角）。
