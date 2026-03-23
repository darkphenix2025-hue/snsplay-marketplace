---
name: sns-workflow:bug-fix
description: 漏洞修复工作流 —— 串联根因分析、需求、规划、规划评审、实现和代码评审阶段技能，使用配置的 bugfix_workflow
user-invocable: true
allowed-tools: Read, Write, Bash, Glob, Grep, Skill, AskUserQuestion
---

# 漏洞修复工作流编排器

端到端运行完整的漏洞修复流程。按照 `~/.snsplay/sns-workflow.json` 中 `bugfix_workflow` 定义的顺序串联各个阶段技能。

**任务目录:** `${CLAUDE_PROJECT_DIR}/.snsplay/task/`

---

## 步骤 1: 初始化

1. 创建 `.snsplay/task/` 目录（如果不存在）
2. 保存用户的漏洞报告到 `.snsplay/task/requirements-prompt.md`
3. 加载工作流配置并展开阶段：

```bash
bun -e "
import { loadWorkflowConfig, expandWorkflowToEntries } from '${CLAUDE_PLUGIN_ROOT}/scripts/workflow-config.ts';
const config = loadWorkflowConfig();
const stages = expandWorkflowToEntries(config, 'bugfix_workflow');
console.log(JSON.stringify({
  workflow: config.bugfix_workflow,
  stages,
  max_iterations: config.max_iterations
}));
"
```

4. 写入 `.snsplay/task/workflow-tasks.json`:
```json
{
  "workflow_type": "bug-fix",
  "stages": [<展开的阶段条目>],
  "created_at": "ISO8601"
}
```

5. 向用户展示工作流阶段：
```
漏洞修复工作流：rca → requirements → planning → plan-review → implementation → code-review
执行器：共 {count} 个，分布在 {stage_count} 个阶段
```

---

## 步骤 2: 按顺序执行阶段

对 `bugfix_workflow` 中的每个阶段类型：

### 阶段到技能的映射

| 阶段类型 | 技能 | 说明 |
|---|---|---|
| `rca` | `Skill(skill: "sns-workflow:rca")` | 根因分析。输出 `rca-diagnosis.json` |
| `requirements` | `Skill(skill: "sns-workflow:requirements")` | 自动读取 `rca-diagnosis.json` 作为上下文 |
| `planning` | `Skill(skill: "sns-workflow:plan")` | 创建修复方案，包含 TDD 测试用例 |
| `plan-review` | `Skill(skill: "sns-workflow:review", args: "--plan")` | 评审方案。拥有评审→修复→再审阅循环 |
| `implementation` | `Skill(skill: "sns-workflow:implement")` | 使用 TDD 循环实现修复 |
| `code-review` | `Skill(skill: "sns-workflow:review", args: "--code")` | 评审代码。拥有评审→修复→再审阅循环 |

### 执行流程

与功能工作流相同：
1. 宣布每个阶段
2. 调用相应的技能
3. 验证输出产物是否存在
4. 如果评审阶段返回 `rejected` → **停止工作流**

---

## 步骤 3: 报告

所有阶段完成后：
1. 展示各阶段状态汇总
2. 如果所有阶段通过 → "漏洞修复工作流完成！"
3. 如果有阶段被拒绝 → 报告哪个阶段及剩余发现
