---
name: sns-workflow:feature-implement
description: 完整功能开发工作流 —— 使用配置的 feature_workflow 串联需求、规划、规划评审、实现和代码评审阶段技能。
user-invocable: true
allowed-tools: Read, Write, Bash, Glob, Grep, Skill, AskUserQuestion
---

# 功能工作流编排器

端到端运行完整的功能开发流程。按照 `~/.snsplay/sns-workflow.json` 中 `feature_workflow` 定义的顺序串联各个阶段技能。

**任务目录：** `${CLAUDE_PROJECT_DIR}/.snsplay/task/`

---

## 步骤 1: 初始化

1. 创建 `.snsplay/task/` 目录（如果不存在）
2. 保存用户的原始请求到 `.snsplay/task/requirements-prompt.md`
3. 加载工作流配置并展开阶段：

```bash
bun -e "
import { loadWorkflowConfig, expandWorkflowToEntries } from '${CLAUDE_PLUGIN_ROOT}/scripts/workflow-config.ts';
const config = loadWorkflowConfig();
const stages = expandWorkflowToEntries(config, 'feature_workflow');
console.log(JSON.stringify({
  workflow: config.feature_workflow,
  stages,
  max_iterations: config.max_iterations
}));
"
```

4. 写入 `.snsplay/task/workflow-tasks.json`:
```json
{
  "workflow_type": "feature-implement",
  "stages": [<展开的阶段条目>],
  "created_at": "ISO8601"
}
```

5. 向用户展示工作流阶段：
```
功能工作流：requirements → planning → plan-review → implementation → code-review
执行器：共 {count} 个，分布在 {stage_count} 个阶段
```

---

## 步骤 2: 按顺序执行阶段

对 `feature_workflow` 中的每个阶段类型：

### 阶段到技能的映射

| 阶段类型 | 技能 | 说明 |
|---|---|---|
| `requirements` | `Skill(skill: "sns-workflow:requirements")` | 收集需求，创建用户故事产物 |
| `planning` | `Skill(skill: "sns-workflow:plan")` | 创建实现计划与 TDD 测试用例 |
| `plan-review` | `Skill(skill: "sns-workflow:review", args: "--plan")` | 评审计划。拥有评审→修复→再审阅循环 |
| `implementation` | `Skill(skill: "sns-workflow:implement")` | 使用 TDD 循环实现计划 |
| `code-review` | `Skill(skill: "sns-workflow:review", args: "--code")` | 评审代码。拥有评审→修复→再审阅循环 |

### 执行流程

对每个阶段：
1. 宣布：`**阶段：{stage_type}** —— 分发中...`
2. 调用相应的技能（见上方映射）
3. 技能完成后，验证预期的输出产物是否存在
4. 如果评审阶段在耗尽迭代预算后返回 `rejected` → **停止工作流** 并向用户报告

**重要提示：** 评审阶段（`plan-review`、`code-review`）通过 `/sns-workflow:review` 内部处理自己的评审→修复→再审阅循环。编排器只调用技能一次并等待其完成。不要在此处实现循环逻辑。

---

## 步骤 3: 报告

所有阶段完成后：
1. 呈现各阶段状态摘要
2. 如果所有阶段通过 → "功能工作流完成！"
3. 如果有阶段被拒绝 → 报告哪个阶段及剩余的 must_fix 发现
