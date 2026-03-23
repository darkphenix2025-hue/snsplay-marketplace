---
name: sns-workflow:chatroom
description: PK 阶段 —— 多 AI 竞争性辩论与迭代共识。同时将话题发送给所有配置的 AI 参与者，综合最佳方案，迭代直至达成共识或达到最大轮次。
user-invocable: true
allowed-tools: Read, Bash, Task, TaskOutput, AskUserQuestion, Glob, Grep
---

# PK 阶段 —— 多 AI 竞争性辩论

将一个话题同时发送给所有配置的 AI + Claude，综合最佳方案，迭代直至达成共识。

**核心特点：**
- **透明化辩论过程** —— 每轮展示各参与者的立场和意见变化
- **迭代共识** —— 多轮辩论逐步收敛，记录关键转折点
- **完整历程** —— 最终结果包含从初始立场到共识的完整演进

**用法:** `/sns-workflow:chatroom <话题或问题>`

**配置:** `~/.snsplay/chatroom.json` —— 使用 `/sns-workflow:dev-config` Web 门户或手动编辑。

---

## 步骤 1: 解析与加载配置

从技能触发后的参数中提取用户话题。

加载并验证聊天室配置：

```bash
bun -e "
import { loadChatroomConfig } from '${CLAUDE_PLUGIN_ROOT}/scripts/chatroom-config.ts';
import { readPresets } from '${CLAUDE_PLUGIN_ROOT}/scripts/preset-utils.ts';
import { validateChatroomConfig } from '${CLAUDE_PLUGIN_ROOT}/scripts/chatroom-config.ts';
const config = loadChatroomConfig();
const presets = readPresets();
const err = validateChatroomConfig(config, presets);
if (err) { console.error('CONFIG ERROR: ' + err); process.exit(1); }
console.log(JSON.stringify({
  participants: config.participants.map((p, i) => ({
    index: i,
    system_prompt: p.system_prompt || '',
    preset: p.preset,
    model: p.model,
    type: presets.presets[p.preset]?.type || 'unknown',
    timeout_ms: presets.presets[p.preset]?.timeout_ms
  })),
  max_rounds: config.max_rounds
}));
"
```

如果配置出错或无参与者：向用户报告错误并停止。

**解析会话变量：**

1. 解析临时目录：
   ```bash
   bun -e "console.log(require('os').tmpdir())"
   ```
   将结果存储为 `{TMPDIR}`。

2. 计算项目哈希：
   ```bash
   bun -e "const c=require('crypto');console.log(c.createHash('sha256').update(process.env.CLAUDE_PROJECT_DIR||process.cwd()).digest('hex').slice(0,8))"
   ```
   将结果存储为 `{PROJHASH}`。

3. 生成随机后缀：
   ```bash
   bun -e "console.log(require('crypto').randomBytes(2).toString('hex'))"
   ```
   将结果存储为 `{RAND}`。

4. 生成会话 ID：`{PROJHASH}-{Date.now()}-{RAND}` → 存储为 `{SESSION_ID}`

5. 为每个参与者分配从零开始的索引：`p0`, `p1`, `p2`, ...

6. 确保输出目录存在：
   ```bash
   mkdir -p "{TMPDIR}/.snsplay/oneshot"
   ```

7. **启动时不清理** —— 来自其他会话的遗留文件无害。

**向用户显示会话信息：**
- 参与者数量、他们的预设/模型
- 配置的最大轮次
- 会话 ID（用于调试）

---

## 步骤 2: 开场轮次（分发）

**可以并行 —— 在单个消息中分发所有参与者 + 生成 Claude 的立场。**

### 2a. 生成 heredoc 分隔符

生成唯一的分隔符以防止 heredoc 注入：
```bash
bun -e "console.log('VCPTASK_' + require('crypto').randomBytes(4).toString('hex'))"
```
将结果存储为 `{DELIM}`（例如 `VCPTASK_a3f7b2c1`）。

### 2a-bis. 解析参与者系统提示

对于每个具有非空 `system_prompt` 字段的参与者，解析内容：

```bash
bun -e "
import { getSystemPrompt } from '${CLAUDE_PLUGIN_ROOT}/scripts/system-prompts.ts';
const prompt = getSystemPrompt('{SYSTEM_PROMPT}', '${CLAUDE_PLUGIN_ROOT}/system-prompts/built-in');
console.log(prompt ? prompt.content : '');
"
```

存储每个参与者的解析内容。如果结果为空或命令失败，则跳过 —— 参与者使用默认行为（不 prepend 系统提示）。

### 2b. 并行分发所有参与者

对于索引 `{i}` 处的每个参与者：

**输出 ID:** `cr-{SESSION_ID}-p{i}-r1`

**开场提示模板：**

如果参与者具有已解析的 `system_prompt` 内容（来自步骤 2a-bis），在辩论提示前添加它：
```
{system_prompt_content}
---
你正在参与一场关于以下主题的多 AI 辩论。

TOPIC:
{user_topic}

请提供你的分析、建议和推理。要具体明确。

重要提示：只读和分析。不要使用 Write、Edit 或 Bash 工具修改任何文件。
```

如果参与者没有 `system_prompt`（空或无法解析），使用不带前缀的提示：
```
你正在参与一场关于以下主题的多 AI 辩论。

TOPIC:
{user_topic}

请提供你的分析、建议和推理。要具体明确。

重要提示：只读和分析。不要使用 Write、Edit 或 Bash 工具修改任何文件。
```

根据参与者类型路由：

- **Subscription:** `Task(subagent_type: "general-purpose", model: {model}, prompt: {prompt})`

- **API:** `Bash(run_in_background: true)` →
  ```bash
  bun "${CLAUDE_PLUGIN_ROOT}/scripts/one-shot-runner.ts" \
    --type api --output-id cr-{SESSION_ID}-p{i}-r1 \
    --preset "{PRESET}" --model "{MODEL}" \
    --cwd "${CLAUDE_PROJECT_DIR}" --task-stdin <<'{DELIM}'
  {prompt_text}
  {DELIM}
  ```

- **CLI:** `Bash(run_in_background: true)` →
  ```bash
  bun "${CLAUDE_PLUGIN_ROOT}/scripts/one-shot-runner.ts" \
    --type cli --output-id cr-{SESSION_ID}-p{i}-r1 \
    --preset "{PRESET}" --model "{MODEL}" \
    --cwd "${CLAUDE_PROJECT_DIR}" --task-stdin <<'{DELIM}'
  {prompt_text}
  {DELIM}
  ```

### 2c. Claude 生成自己的开场立场

后台任务运行时，内联生成你自己对话题的分析。这是 Claude 在辩论中的开场立场。

---

## 步骤 3: 收集响应（顺序执行）

**关键：** 逐个轮询后台任务。不要在同一个消息中发出多个 TaskOutput 调用 —— 这会导致级联失败。

**Subscription 参与者：** 结果已在步骤 2 的 Task 调用中直接返回。已收集。

**API/CLI 参与者：** 对每个参与者依次执行：

1. 派生超时时间：`min(timeout_ms + 120000, 600000)`，其中 `timeout_ms` 是预设配置的超时时间（API 默认 300000，CLI 默认 1200000）。

2. 轮询完成状态：
   ```
   TaskOutput(task_id: "{id}", block: true, timeout: {computed_timeout})
   ```

3. 如果 TaskOutput 返回但任务仍在运行，重复：
   ```
   TaskOutput(task_id: "{id}", block: true, timeout: 600000)
   ```
   继续重复直到任务完成。

4. 读取输出文件：
   ```
   Read("{TMPDIR}/.snsplay/oneshot/cr-{SESSION_ID}-p{i}-r{round}.json")
   ```
   解析 JSON。提取 `result` 字段获取成功响应。注意 `error` 字段记录失败。

5. **CLI 输出规范化：** 去除 ANSI 转义序列（`/\x1b\[[0-9;]*[a-zA-Z]/g` 模式）。有用的内容可能与横幅或进度输出混合。

**错误处理：**
- 如果参与者超时或出错：记录失败，继续处理其余参与者。
- **法定人数规则：** 至少需要 1 个外部响应 + Claude 自己的响应才能继续。如果所有外部参与者都失败，向用户报告错误并停止。

---

## 步骤 4: 综合与检查共识

读取所有收集到的响应（Claude 自己的 + 所有外部参与者）。

### 每轮必须向用户展示

**在每轮收集完所有响应后，必须立即向用户展示该轮的讨论情况：**

```
## 第 {N}/{max_rounds} 轮讨论

### 各参与者立场：

**Claude**:
{claude_position_summary}

**参与者 p0** ({preset}/{model}):
{p0_position_summary}

**参与者 p1** ({preset}/{model}):
{p1_position_summary}

...（列出所有参与者）

### 共识检查状态：
- 同意：{count} 人
- 部分同意：{count} 人（列出名字）
- 不同意：{count} 人（列出名字和主要原因）

### 当前综合方案：
{claude_synthesis}

{继续下一轮 / 达成共识}
```

---

**第一轮（开场）：**
- 识别每个参与者的最强观点
- 注意一致和分歧的领域
- 综合一个结合最佳元素的方案
- **展示上述第 1 轮讨论摘要给用户**

**后续轮次：**
- 应用 CLI 输出规范化（如上所述去除 ANSI）
- 在每个响应的任何位置搜索共识关键字（不仅限于第一行）：
  - `AGREE` —— 参与者接受综合方案
  - `DISAGREE: <reason>` —— 参与者拒绝并给出具体原因
  - `PARTIAL: <accepted> / <contested>` —— 部分同意
- 如果未找到关键字，解释整体情感以分类为同意/不同意/部分同意
- **展示上述第 N 轮讨论摘要给用户**

**决策：**
- 如果所有参与者都同意 → 转到 **步骤 6**
- 如果达到最大轮次 → 转到 **步骤 6**（报告最终状态）
- 如果有不同意见且还有剩余轮次 → 完善综合方案，转到 **步骤 5**

---

## 步骤 5: 后续轮次

生成新的 heredoc 分隔符（与步骤 2a 相同的方法）。

**共识检查提示模板：**

如果参与者具有已解析的 `system_prompt` 内容（来自步骤 2a-bis），在共识检查提示前添加它：
```
{system_prompt_content}
---
多 AI 辩论 —— 第 {N} 轮共识检查

原始话题：
{user_topic}

辩论历史摘要：
{summary_of_positions_from_all_rounds}

当前综合方案：
{claude_synthesis}

你是否同意这个综合方案？回应以下选项之一：
- AGREE —— 如果你接受这个方法
- DISAGREE: <你的具体反对意见和替代方案> —— 如果你拒绝它
- PARTIAL: <你接受的部分> / <你争议的部分> —— 如果你部分同意

然后解释你的推理。

重要提示：只读和分析。不要修改任何文件。
```

如果参与者没有 `system_prompt`（空或无法解析），使用不带前缀的提示：
```
多 AI 辩论 —— 第 {N} 轮共识检查

原始话题：
{user_topic}

辩论历史摘要：
{summary_of_positions_from_all_rounds}

当前综合方案：
{claude_synthesis}

你是否同意这个综合方案？回应以下选项之一：
- AGREE —— 如果你接受这个方法
- DISAGREE: <你的具体反对意见和替代方案> —— 如果你拒绝它
- PARTIAL: <你接受的部分> / <你争议的部分> —— 如果你部分同意

然后解释你的推理。

重要提示：只读和分析。不要修改任何文件。
```

使用与步骤 2b 相同的模式分发给所有参与者（并行分发，`run_in_background: true`）。

第 N 轮的输出 ID：`cr-{SESSION_ID}-p{i}-rN`

使用与步骤 3 相同的顺序模式收集响应。

带着新的响应返回 **步骤 4**。

---

## 步骤 6: 展示结果与清理

### 向用户展示最终结果：

**如果达成共识：**
```
## 已达成共识（第 {N}/{max_rounds} 轮）

所有 {count} 个参与者就以下方法达成一致：

{final_synthesis}

---

## 辩论历程摘要

### 第 1 轮：初始立场
- **Claude**: {position_summary}
- **p0** ({preset}/{model}): {position_summary}
- **p1** ({preset}/{model}): {position_summary}
- ...

### 第 2 轮：共识检查
- **Claude**: AGREE/DISAGREE/PARTIAL - {reason_if_any}
- **p0** ({preset}/{model}): AGREE/DISAGREE/PARTIAL - {reason_if_any}
- **p1** ({preset}/{model}): AGREE/DISAGREE/PARTIAL - {reason_if_any}
- ...

{更多轮次...}

### 最终轮（第 {N} 轮）：
- **Claude**: AGREE
- **p0** ({preset}/{model}): AGREE
- **p1** ({preset}/{model}): AGREE
- ...

---

### 关键转折点：
{描述导致共识的关键综合点或妥协}
```

**如果耗尽最大轮次仍未达成完全共识：**
```
## 辩论完成 —— 未达成完全共识（第 {max_rounds}/{max_rounds} 轮）

### 最佳综合方案：
{final_synthesis}

---

## 辩论历程摘要

### 第 1 轮：初始立场
...

### 第 {max_rounds} 轮：最终立场
- **Claude**: {status} - {reason}
- **p0** ({preset}/{model}): {status} - {reason}
- ...

---

### 剩余分歧：
- {preset}/{model} (p1): DISAGREE — {reason}

### 达成一致的领域：
{agreed_points}
```

### 清理

仅删除此会话的输出文件：
```bash
rm -f "{TMPDIR}/.snsplay/oneshot/cr-{SESSION_ID}-"*
```

---

## 已知限制

1. **参与者仓库变更：** API 参与者（通过 api-task-runner 的 Write/Edit/Bash 工具）和 CLI 参与者（通过其本地 shell 访问，例如 Codex `--full-auto`）都保留修改仓库的能力，尽管提示指令要求只读和分析。这只是提示级别的强制执行。结构性只读模式是后续功能。

2. **CLI 输出噪音：** CLI 工具可能会在实际响应旁边发出横幅、ANSI 序列、进度输出或调试文本。SKILL 会去除 ANSI 并在响应的任何位置搜索共识关键字，但嘈杂的输出仍可能混淆综合。

3. **Web 门户：** 配置可通过 `/sns-workflow:dev-config` Web 门户（Chatroom 选项卡）或手动编辑 `~/.snsplay/chatroom.json` 获得。

---

## 错误处理

| 场景 | 操作 |
|----------|--------|
| 未配置参与者 | 报告错误，建议编辑 `~/.snsplay/chatroom.json` |
| 配置验证失败 | 报告具体错误 |
| 所有外部参与者失败 | 向用户报告错误（未达法定人数） |
| 单个参与者失败 | 记录失败，继续处理其余参与者（如达到法定人数） |
| 耗尽最大轮次 | 展示最佳综合方案并注明分歧 |

---

## 反模式

- 不要在同一个消息中发出多个 TaskOutput 调用 —— 级联失败
- 不要使用固定的 heredoc 分隔符（如 `TASK_EOF`）—— 每次分发都生成随机的
- 不要清理来自其他会话的文件 —— 只清理 `cr-{SESSION_ID}-*`
- 不要跳过 Claude 自己的立场 —— Claude 始终是参与者
- 不要为后台任务使用前景 Bash 回退 —— 始终使用 `run_in_background: true` + TaskOutput 轮询
- 不要使用默认 TaskOutput 超时（30 秒）—— 始终从预设的 `timeout_ms` 计算
