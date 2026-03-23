---
name: sns-workflow:create-prompt
description: 为 sns-workflow 执行器创建自定义系统提示。引导用户定义名称、描述、工具和提示内容。保存到 ~/.snsplay/system-prompts/。
user-invocable: true
allowed-tools: Read, Write, Bash, Glob, Grep, AskUserQuestion
---

# 创建自定义系统提示

引导用户创建可用于 sns-workflow 执行器的自定义系统提示。

**自定义提示目录：** `~/.snsplay/system-prompts/`
**内置提示：** `${CLAUDE_PLUGIN_ROOT}/system-prompts/built-in/`

---

## 步骤 1: 显示现有提示

列出所有可用的系统提示，让用户知道存在什么：

```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/system-prompts.ts" discover
```

向用户呈现列表："以下是当前的系统提示（内置 + 自定义）。你想创建哪种类型的提示？"

---

## 步骤 2: 收集信息

通过 AskUserQuestion 询问用户：

1. **提示类型？** —— 选项：reviewer、planner、analyst、implementer、custom
2. **名称** —— 必须唯一，小写带连字符（例如 `perf-reviewer`、`security-analyst`）
3. **描述** —— 一行摘要说明此提示的作用
4. **用途** —— 此提示应擅长什么具体任务/焦点领域？

如果用户选择了类别（非 "custom"），提供显示相关内置提示作为起始模板：
- reviewer → 显示 `code-reviewer.md` 或 `plan-reviewer.md`
- planner → 显示 `planner.md`
- analyst → 显示 `root-cause-analyst.md`
- implementer → 显示 `implementer.md`

---

## 步骤 3: 工具（仅角色提示）

**自定义系统提示仅是角色/视角定义。** 阶段规则（输出格式、流程、完成要求）和工具权限在分发时由阶段定义自动提供。自定义提示不应包含工具、输出格式或完成要求。

在 frontmatter 中留空 `tools` —— 阶段定义在运行时提供工具列表。

---

## 步骤 4: 帮助编写系统提示内容

根据用户的用途，帮助他们编写系统提示主体。角色提示定义代理带来的**视角和专业知识** —— 而非输出格式或流程（这些来自阶段定义）。

包括：

1. **角色定义** —— "你是一名 [角色]，在 [领域] 拥有专业知识。"
2. **核心能力** —— 3-5 个此代理擅长的要点

不要包含输出格式、流程/工作流或完成要求 —— 这些由阶段定义在分发时提供。

向用户呈现草稿以供审查。如果他们想要更改则迭代。

---

## 步骤 5: 验证名称

检查名称是否与内置提示冲突：

```bash
bun -e "
import { discoverSystemPrompts } from '${CLAUDE_PLUGIN_ROOT}/scripts/system-prompts.ts';
const builtInDir = '${CLAUDE_PLUGIN_ROOT}/system-prompts/built-in';
const prompts = discoverSystemPrompts(builtInDir);
const name = '{USER_CHOSEN_NAME}';
const collision = prompts.find(p => p.name === name);
console.log(JSON.stringify({ collision: !!collision, source: collision?.source }));
"
```

如果检测到冲突，告诉用户并要求不同的名称。

---

## 步骤 6: 写入文件

组装带有 YAML frontmatter 的完整文件并写入：

```markdown
---
name: {name}
description: {description}
tools: {comma-separated tools}
model: inherit
---

{system prompt content}
```

使用 Write 工具写入 `~/.snsplay/system-prompts/{name}.md`：
```
Write(file_path: "~/.snsplay/system-prompts/{name}.md", content: "{assembled content}")
```

首先确保 `~/.snsplay/system-prompts/` 目录存在：
```bash
mkdir -p ~/.snsplay/system-prompts
```

---

## 步骤 7: 验证

验证提示是否成功创建：

```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/system-prompts.ts" list
```

新提示应出现在 "custom" 下。告诉用户：

"自定义提示 '{name}' 创建成功！使用方法：
1. 前往 `/sns-workflow:dev-config` → Executors 选项卡
2. 创建带 system_prompt: '{name}' 的新执行器
3. 在 Stages 选项卡中将执行器分配到阶段"

---

## 反模式

- 不要创建与内置提示名称匹配的提示
- 不要写入内置提示目录（`system-prompts/built-in/`）
- 不要跳过验证步骤 —— 始终检查名称冲突
- 不要创建过于通用的提示 —— 每个提示应有清晰、专注的用途
