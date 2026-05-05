---
name: sns-workflow:once
description: 使用指定的 AI 提供者和模型运行单个任务。支持 subscription、API 和 CLI 预设。
user-invocable: true
allowed-tools: Read, Bash, Task, TaskOutput, AskUserQuestion, Glob, Grep
---

# 一次性任务运行器

使用任何配置的 AI 提供者运行单个任意任务 —— 无工作流、无评审、无编排。

**用法：** `/sns-workflow:once use <provider> [model <model>] <task description>`

**示例：**
```
/sns-workflow:once use minimax M2.5 model to help me design a new UI
/sns-workflow:once use codex o3 model to refactor the auth module
/sns-workflow:once use anthropic-subscription sonnet model to explain the codebase
/sns-workflow:once use minimax to analyze performance bottlenecks
```

---

## 步骤 1: 解析参数

从用户消息中提取三部分内容：
- **提供者名称** —— 预设名称（例如 "minimax"、"codex"、"anthropic-subscription"）
- **模型** —— 模型标识符（例如 "M2.5"、"o3"、"sonnet"）
- **任务** —— 其余所有内容（实际要做的工作）

用户消息跟随技能触发器。常见模式：
- `use <provider> <model> model to <task>`
- `use <provider> model <model> to <task>`
- `use <provider> to <task>`（省略模型 —— 将使用默认值）

---

## 步骤 2: 解析预设

列出可用预设：

```bash
bun -e "
import { readPresets } from '${CLAUDE_PLUGIN_ROOT}/scripts/preset-utils.ts';
const presets = readPresets();
console.log(JSON.stringify(Object.entries(presets.presets).map(([k,v]) => ({
  name: k, type: v.type, models: v.models || ['haiku','sonnet','opus']
}))));
"
```

**确定性匹配提供者名称：**
1. **精确匹配**（不区分大小写）→ 使用它
2. **唯一前缀匹配**（不区分大小写）→ 使用它（例如 "mini" 匹配 "MiniMax-API"，如果没有其他预设以 "mini" 开头）
3. **多个匹配** → 使用 AskUserQuestion 列出匹配项，让用户选择
4. **无匹配** → 报告错误并提供可用预设名称

**验证模型：**
- 如果用户指定了模型，检查它是否存在于预设的 `models[]` 列表中
- 如果用户未指定模型：
  - Subscription 预设：默认为 `sonnet`
  - API/CLI 预设：默认为 `preset.models[0]`
- 对于 subscription 预设（无 `models[]`），有效模型为：`haiku`、`sonnet`、`opus`

---

## 步骤 3: 根据提供者类型路由

读取匹配预设的 `type` 字段并相应路由：

### Subscription（`type: "subscription"`）

直接使用 Task 工具 —— 无需外部进程：

```
Task(
  subagent_type: "general-purpose",
  model: "<model>",
  prompt: "<task>"
)
```

子代理在项目目录中工作，具有完整的工具访问权限。完成后向其报告输出。

### API（`type: "api"`）

运行一次性运行器脚本：

```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/one-shot-runner.ts" \
  --type api \
  --preset "<exact_preset_name>" \
  --model "<model>" \
  --cwd "${CLAUDE_PROJECT_DIR}" \
  --task-stdin <<'TASK_EOF'
<task_text>
TASK_EOF
```

使用 `--task-stdin` 与 heredoc 以避免 OS argv 大小限制和 ps 暴露。

**派生超时：** 读取 `~/.snsplay/ai-presets.json` → 按名称查找预设 → 读取 `timeout_ms`（如果未设置或查找失败则默认：300000）。

**重要提示：** Bash 工具有硬最大超时 600,000ms（10 分钟）。API 任务可能运行更长时间（例如 30 分钟）。始终使用 `run_in_background: true` 以防止 Bash 工具过早杀死进程。

启动后：
1. 保存从 Bash 工具返回的 `task_id`。如果 `run_in_background` 未返回 `task_id`，向用户报告分发失败 —— 不要在前景模式下重试。
2. **关键 —— 使用正确的超时轮询（不是默认 30 秒）：**
   ```
   TaskOutput(task_id: "<task_id>", block: true, timeout: min(timeout_ms + 120000, 600000))
   ```
   对于 5 分钟预设（默认 300000ms），这 = `min(420000, 600000)` = **420000ms（7 分钟）**。
   默认 TaskOutput 超时仅为 30 秒 —— 对于通常耗时 2-5 分钟的 API 任务来说太短了。
3. 如果 TaskOutput 返回但任务仍在运行（未完成），重复 `TaskOutput` 与 `timeout: 600000` 直到完成。

脚本：
1. 生成 `api-task-runner.ts` 与预设、模型和任务（通过 stdin）
2. 任务运行器创建 V2 Agent SDK 会话，运行任务，然后退出
3. 输出 JSON 事件到 stdout

### CLI（`type: "cli"`）

**前提条件：** CLI 预设必须配置了 `one_shot_args_template`。此模板仅使用 `{model}`、`{prompt}` 和 `{reasoning_effort}` 占位符（无 `{output_file}` 或 `{schema_path}` —— 这些仅用于工作流）。

如果预设没有 `one_shot_args_template`，向用户报告错误并建议通过 `/sns-workflow:dev-config` 配置它。

运行一次性运行器脚本：

```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/one-shot-runner.ts" \
  --type cli \
  --preset "<exact_preset_name>" \
  --model "<model>" \
  --cwd "${CLAUDE_PROJECT_DIR}" \
  --task-stdin <<'TASK_EOF'
<task_text>
TASK_EOF
```

**派生超时：** 读取 `~/.snsplay/ai-presets.json` → 按名称查找预设 → 读取 `timeout_ms`（如果未设置或查找失败则 CLI 默认：1200000 —— 匹配脚本的 20 分钟默认值）。

**重要提示：** Bash 工具有硬最大超时 600,000ms（10 分钟）。CLI 任务可能运行更长时间（例如 Codex 带 20 分钟超时）。始终使用 `run_in_background: true` 以防止 Bash 工具过早杀死进程。

启动后：
1. 保存从 Bash 工具返回的 `task_id`。如果 `run_in_background` 未返回 `task_id`，向用户报告分发失败 —— 不要在前景模式下重试。
2. **关键 —— 使用正确的超时轮询（不是默认 30 秒）：**
   ```
   TaskOutput(task_id: "<task_id>", block: true, timeout: min(timeout_ms + 120000, 600000))
   ```
   对于 20 分钟 CLI 预设（默认 1200000ms），这 = `min(1320000, 600000)` = **600000ms（10 分钟）**。
   默认 TaskOutput 超时仅为 30 秒 —— 对于通常耗时 5-20 分钟的 CLI 任务来说太短了。
3. 如果 TaskOutput 返回但任务仍在运行（未完成），重复 `TaskOutput` 与 `timeout: 600000` 直到完成。

CLI 工具直接在项目目录中运行（例如 Codex `exec --full-auto`）。其输出流式传输到终端。

---

## 步骤 4: 报告结果

任务完成后，读取脚本的 stdout JSON 输出：

### 成功（退出码 0）
```json
{"event": "complete", "provider": "minimax", "model": "M2.5", "result": "..."}
```

报告：提供者、使用的模型，以及完成的摘要。

### 验证错误（退出码 1）
```json
{"event": "error", "phase": "validation", "error": "..."}
```

报告验证错误（错误的模型、缺失的预设、错误的模板）。

### 执行错误（退出码 2）
```json
{"event": "error", "phase": "api_execution|cli_execution", "error": "..."}
```

报告出错内容（会话失败、CLI 未安装、认证错误）。

### 超时（退出码 3）
```json
{"event": "error", "phase": "api_execution|cli_execution", "error": "..."}
```

报告任务超时。建议通过 `/sns-workflow:dev-config` 增加预设的 `timeout_ms`。

---

## 错误处理

| 场景 | 操作 |
|----------|--------|
| 预设未找到 | 列出可用预设，建议 `/sns-workflow:dev-config list` |
| 模型不在预设中 | 列出预设的可用模型 |
| 多个预设匹配 | AskUserQuestion 与匹配名称 |
| CLI 预设缺少 `one_shot_args_template` | 报告错误，建议 `/sns-workflow:dev-config` 添加它 |
| CLI 工具未安装 | 报告错误，建议安装工具 |
| API 任务运行器失败 | 从脚本输出报告错误 |
| 任务超时 | 报告超时，建议增加 `timeout_ms` |

---

## 反模式

- 不要运行完整工作流 —— 这是单个一次性任务
- 不要创建工作流任务（TaskCreate/TaskUpdate）—— 无需编排
- 不要跳过预设解析步骤 —— 始终先验证提供者和模型
- 不要猜测预设类型 —— 始终从预设文件读取
- 对于 subscription：不要运行 one-shot-runner.ts 脚本 —— 直接使用 Task 工具
- 当后台 TaskOutput 返回空时不要回退到前景 Bash —— 任务可能仍在运行。增加 TaskOutput 超时。
- 不要在前景模式下重试相同的 API/CLI 任务 —— Bash 工具的 2 分钟默认超时总是短于典型任务持续时间（API 2-5 分钟，CLI 5-20 分钟）。前景模式总是会过早杀死进程。
- 不要对 API/CLI 任务使用默认 TaskOutput 超时（30 秒）—— 始终按照上述轮询说明传递计算的超时。
