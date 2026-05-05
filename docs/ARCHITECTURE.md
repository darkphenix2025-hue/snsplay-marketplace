# ARCHITECTURE

> 此文件为自动生成，请根据项目实际情况填写内容。

---

## SNS-Workflow 架构参考 (v2/v3)

> 以下内容由迁移脚本自动追加，来自 plugins/sns-workflow/docs/workflow.md

# SNS-Workflow 工作流

SNS-Workflow 有两种架构：**v3 阶段技能**（基于执行器的细粒度架构）和 **v2 工作流技能**（基于团队的单体架构）。

---

## v3 架构：模块化阶段技能

### 核心概念

```
阶段定义 + 角色提示（.md 文件）+ 预设 + 模型 = 执行器
阶段 = 执行器集合（并行/顺序）
阶段技能 = 可单独调用的命令，运行阶段的所有执行器
```

- **阶段定义** —— 6 种固定类型（requirements、planning、plan-review、implementation、code-review、rca），定义每个工作流阶段发生什么
- **角色提示** —— 可重用的代理角色定义。内置（`system-prompts/built-in/*.md`，只读）+ 自定义（`~/.snsplay/system-prompts/*.md`）
- **执行器** —— system_prompt + preset + model 的命名组合。定义于 `~/.snsplay/sns-workflow.json`
- **阶段** —— 6 种固定类型，每个包含执行器引用数组。执行器可并行或顺序运行
- **工作流** —— 用户配置的阶段有序列表

### 阶段技能

| 技能 | 命令 | 用途 |
|-------|---------|---------|
| 规划 | `/sns-workflow:plan` | 创建实现计划与测试用例及步骤到 AC 映射 |
| 评审 | `/sns-workflow:review` | 评审计划（`--plan`）或代码（`--code`）。多执行器、基于证据的发现 |
| 实现 | `/sns-workflow:implement` | 使用 TDD 循环实现 —— 每步后测试，失败时升级 |
| 需求 | `/sns-workflow:requirements` | 收集需求并追踪来源。最小 4 文件输出 |
| RCA | `/sns-workflow:rca` | 根因分析。仅输出诊断 |

### 典型工作流

**功能开发：**
```
/sns-workflow:requirements → /sns-workflow:plan → /sns-workflow:review --plan → /sns-workflow:implement → /sns-workflow:review --code
```

**漏洞修复：**
```
/sns-workflow:rca → /sns-workflow:requirements → /sns-workflow:plan → /sns-workflow:review --plan → /sns-workflow:implement → /sns-workflow:review --code
```

每个阶段从 `.snsplay/task/` 读取输入产物并写入输出产物。无团队模式，阶段间无持久状态。

### 防漂移机制

1. **原始请求注入** —— 每个执行器提示都包含逐字的原始请求
2. **TDD 循环** —— 实现每步后运行测试，失败时循环（最多 5 次重试）
3. **步骤到 AC 映射** —— 每个计划步骤必须引用验收标准
4. **基于证据的评审** —— 阻止性发现需要 `contract_reference` + `evidence`
5. **需求来源追踪** —— AC 追踪其来源（original_request、user_answer、specialist_suggestion）

### 配置格式（v3）

文件：`~/.snsplay/sns-workflow.json` 带 `"version": "3.0"`

```json
{
  "version": "3.0",
  "stages": {
    "planning": { "executors": [{ "system_prompt": "planner", "preset": "anthropic-subscription", "model": "opus" }] },
    "plan-review": { "executors": [{ "system_prompt": "plan-reviewer", "preset": "anthropic-subscription", "model": "sonnet" }] }
  },
  "feature_workflow": ["requirements", "planning", "plan-review", "implementation", "code-review"],
  "bugfix_workflow": ["rca", "requirements", "planning", "plan-review", "implementation", "code-review"],
  "max_iterations": 10,
  "max_tdd_iterations": 5
}
```

### 输出文件

| 文件模式 | 阶段类型 |
|------|-------------|
| `.snsplay/task/user-story/manifest.json` | requirements |
| `.snsplay/task/plan/manifest.json` | planning |
| `.snsplay/task/plan/test-plan.json` | planning（TDD 测试用例） |
| `.snsplay/task/{stage}-{system_prompt}-{provider}-{model}-{index}.json` | plan-review, code-review |
| `.snsplay/task/rca-{system_prompt}-{provider}-{model}-{index}-v{version}.json` | rca |
| `.snsplay/task/workflow-tasks.json` | 工作流状态（由编排器创建） |
| `.snsplay/task/impl-result.json` | implementation |
| `.snsplay/task/rca-diagnosis.json` | rca（合并） |

### 提供者分发

所有阶段技能解析执行器的系统提示，将其嵌入任务提示，并通过 `general-purpose` 子代理分发：
- **subscription** → `Task(subagent_type: "general-purpose", model, prompt: "<system_prompt>\n---\n<task>")`
- **api** → `Bash(run_in_background: true)` → `api-task-runner.ts` → `TaskOutput`
- **cli** → `Task(subagent_type: "general-purpose", prompt: "Run: bun cli-executor.ts ...")`

---

## 角色提示（内置）

| 角色提示 | 用途 |
|-------------|---------|
| `requirements-gatherer` | 业务分析师 + 产品经理混合 |
| `planner` | 架构师 + 全栈规划 |
| `plan-reviewer` | 架构 + 安全 + QA 验证 |
| `implementer` | 全栈 + TDD 实现 |
| `code-reviewer` | 安全 + 性能 + QA 评审 |
| `root-cause-analyst` | 自主漏洞诊断 |

位于 `system-prompts/built-in/`。用户在 `~/.snsplay/system-prompts/` 创建自定义角色提示。

---

## 脚本

| 命令 | 用途 |
|---------|---------|
| `bun workflow-config.ts validate-v3` | 验证 v3 配置 |
| `bun workflow-config.ts migrate` | 迁移 v2 → v3 配置（首次加载时自动） |
| `bun system-prompts.ts list` | 列出所有系统提示（内置 + 自定义） |
| `bun system-prompts.ts discover` | 显示完整发现详情 |

---

## 评审状态

- `approved` —— 进入下一阶段
- `needs_changes` —— 修复并重新评审（需要带证据的 `must_fix` 发现）
- `needs_clarification` —— 询问用户，然后重新运行
- `rejected` —— 重大问题，升级给用户
