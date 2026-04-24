# 工作流技能开发规范

> **目标受众**: 有经验的开发者
> **适用范围**: 所有工作流管理技能开发
> **最后更新**: 2026-04-24

---

## 一、架构总览

### 1.1 核心概念

```
阶段 (Stage) + 角色 (Role) + 执行器 (Executor) + 预设 (Preset) = 工作流技能
```

| 概念 | 定义 | 文件位置 |
|------|------|----------|
| **阶段** | 定义"做什么" — 固定类型的执行单元 | `stages/*.md` |
| **角色** | 定义"谁来做" — 专业领域提示 | `system-prompts/` |
| **执行器** | 阶段的具体执行实例，绑定角色 + 模型 | 配置文件定义 |
| **预设** | AI 提供者配置 (subscription/api/cli) | `~/.snsplay/ai-presets.json` |

### 1.2 Git 分支管理架构

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Git 分支架构总览                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  生产环境线 (Product Line)                                              │
│  main ──► release ──► 测试 ──► main ──► tag ──► product                │
│                                                                         │
│  feature 开发线 (多 worktree 并行)                                       │
│  ┌───────────────────────┐                                              │
│  │ worktree-001 (基线)    │ ── feature/* ──► PR ──► main               │
│  └───────────────────────┘ ───────────────────────────────────────────┘ │
│  ┌───────────────────────┐                                              │
│  │ worktree-002 (基线)    │ ── feature/* ──► PR ──► main               │
│  └───────────────────────┘ ───────────────────────────────────────────┘ │
│  ┌───────────────────────┐                                              │
│  │ worktree-003 (基线)    │ ── feature/* ──► PR ──► main               │
│  └───────────────────────┘ ───────────────────────────────────────────┘ │
│                                                                         │
│  Hotfix 线                                                              │
│  worktree 中修补 ──► product (tag) ──► main (PR)                        │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.3 分支定义与职责

| 分支类型 | 命名规范 | 来源 | 合并目标 | 用途 |
|----------|---------|------|----------|------|
| **main** | `main` | - | release/hotfix 来源 | 开发主线 |
| **product** | `product` | tag | - | 生产环境版本线 |
| **release** | `release/v<major>.<minor>.<patch>` | main | main→tag→product | 发布候选 |
| **hotfix** | `hotfix/v<major>.<minor>.<patch>` | tag | product (tag) → main (PR) | 生产紧急修复 |
| **worktree** | `worktree-<NNN>` | main | - | 长期开发容器 (不随 Feature 删除) |
| **feature** | `feature/<name>` | worktree | main | 单次 Feature 开发 (临时分支) |

### 1.4 版本号规范

采用语义化版本号 (SemVer)：`v<major>.<minor>.<patch>`

| 版本类型 | 递增规则 | 示例 | 触发场景 |
|----------|---------|------|----------|
| **major** | 不兼容的 API 变更 | v1.0.0 → v2.0.0 | release 发布后 |
| **minor** | 向后兼容的功能新增 | v1.0.0 → v1.1.0 | feature 合并到 main |
| **patch** | 向后兼容的问题修复 | v1.0.0 → v1.0.1 | hotfix 合并到 product |

### 1.5 核心工作流

#### 1.5.1 Worktree 管理

**Worktree 策略：**

- 按需手工创建，不预初始化
- worktree 长期保留，不随 Feature 完成而删除
- 每个 worktree 对应一个同名的长期分支

```bash
# 创建新的 worktree (在 .claude/worktrees 目录下)
git worktree add -b worktree-001 .claude/worktrees/worktree-001 main

# 查看当前 worktree 列表
git worktree list
```

**Worktree 状态管理：**

| 状态 | 说明 | 识别方式 |
|------|------|----------|
| **空闲 (Idle)** | 与 main 同步，无进行中的 Feature | `git status` 干净，分支为 `worktree-NNN` |
| **占用 (Busy)** | 有进行中的 Feature 分支 | 当前在 `feature/*` 分支 |
| **落后 (Behind)** | 落后于 main | `git status` 显示落后提交数 |

#### 1.5.2 Feature 开发工作流 (集成 Worktree 管理)

**双模式开发策略：**

根据任务复杂度选择两种开发模式：

| 模式 | 适用场景 | 分支策略 | 流程 |
|------|---------|---------|------|
| **快捷模式** | 基于 worktree 的 bug 修补和微调 | 直接在 `worktree-NNN` 分支开发 | [可选sync] → 开发 → 快速 PR → 合并 → hard reset 到最新 main |
| **Feature 模式** | 新功能开发、大重构 | 创建 `feature/*` 分支 | feature (自动sync) → 开发 → PR → 合并 → 删除 feature 分支 → 回到 worktree |

**快捷模式流程：**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        快捷模式开发流程                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  步骤 1: 进入 worktree                                                   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  cd .claude/worktrees/worktree-003                                │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                    │
│                                    ▼                                    │
│  步骤 2: [可选] sns-workflow:sync                                      │
│  │  sns-workflow sync                                                │   │
│  │  # 可选：同步 main 最新代码到 worktree 分支                        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                    │
│                                    ▼                                    │
│  步骤 3: 开发                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  # 修改代码...                                                    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                    │
│                                    ▼                                    │
│  步骤 4: sns-workflow:commit-push-pr                                  │   │
│  │  # 自动：commit + push + PR + merge                                │   │
│  │  # 自动：hard reset worktree 分支到最新 main                       │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**快捷模式命令示例：**

```bash
# ========== 步骤 1: 进入 worktree ==========
cd .claude/worktrees/worktree-003

# ========== [可选] 步骤 2: 同步 main 最新代码 ==========
sns-workflow sync
# 可选执行：确保开发基于最新 main

# ========== 步骤 3: 开发 ==========
# 修改代码...

# ========== 步骤 4: 提交+推送+PR+合并+重置 ==========
sns-workflow commit-push-pr
# 自动执行：git push
# 自动执行：gh pr create --base main --head worktree-003
# 自动执行：gh pr merge --squash --delete-branch
# 自动执行：git fetch origin main && git reset --hard origin/main
```

**Feature 模式流程：**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Feature 开发完整流程                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  步骤 1: 进入 worktree                                                   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  cd .claude/worktrees/worktree-003                                │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                    │
│                                    ▼                                    │
│  步骤 2: sns-workflow:feature                                         │   │
│  │  # 自动：sync (同步 main 最新代码)                                  │   │
│  │  # 自动：创建 feature/* 分支                                        │   │
│  │  # 等待用户输入 feature 名称                                        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                    │
│                                    ▼                                    │
│  步骤 3: 开发                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  # 开发代码...                                                    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                    │
│                                    ▼                                    │
│  步骤 4: sns-workflow:commit-push-pr                                  │   │
│  │  # 自动：commit + push + PR + merge                                │   │
│  │  # 自动：删除 feature/* 分支                                        │   │
│  │  # 自动：回到 worktree-NNN 分支                                     │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**详细命令步骤：**

```bash
# ========== 步骤 1: 进入 worktree ==========
cd .claude/worktrees/worktree-003

# ========== 步骤 2: 开始功能开发 (自动 sync + 创建 feature 分支) ==========
sns-workflow feature
# 提示输入 feature 名称，如：user-auth-module
# 自动执行：git fetch + rebase origin/main
# 自动执行：git checkout -b feature/user-auth-module

# ========== 步骤 3: 开发 ==========
# 开发代码...

# ========== 步骤 4: 提交+推送+PR+合并+清理 ==========
sns-workflow commit-push-pr
# 自动执行：git push
# 自动执行：gh pr create --base main --head feature/user-auth-module
# 自动执行：gh pr merge --squash --delete-branch
# 自动执行：git checkout worktree-003 (回到 worktree 分支)
```

#### 1.5.3 Release 发布工作流

```
1. 从 main 切出 release 分支 (sns-workflow:release):
   sns-workflow release v1.0.0
   # git checkout -b release/v1.0.0 main
   # git checkout main && git merge release/v1.0.0 (测试完成后)

2. 在 release 分支进行测试和必要修复

3. 发布到生产线 (sns-workflow:publish):
   sns-workflow publish v1.0.0
   # git checkout main && git tag -a v1.0.0 -m "Release v1.0.0"
   # git checkout product && git merge main && git push origin product --tags

4. release 后调整主版本号:
   v1.0.0 → v2.0.0 (下次 release)
```

#### 1.5.4 Hotfix 修复工作流

**Hotfix 策略:**
- 从空闲 worktree 执行修复
- 先合并到 product (打新 tag)
- 再创建 PR 合并回 main

```
1. 选择空闲 worktree:
   cd .claude/worktrees/worktree-003
   sns-workflow sync

2. 从最新 tag 切出 hotfix 分支:
   git checkout -b hotfix/v1.0.1 v1.0.0

3. 修复:
   # 修改代码...

4. 推送到 product (打新 tag):
   sns-workflow commit-push-pr
   # 自动检测 hotfix/* 分支
   # 自动：git push origin hotfix/v1.0.1
   # 自动：gh pr create --base product --head hotfix/v1.0.1
   # 自动：合并后打新 tag v1.0.1
   # 自动：创建从 product 到 main 的 PR (同步修复)

5. 回到 worktree 分支:
   git checkout worktree-003
```

### 1.2 工作流技能分类

```
┌─────────────────────────────────────────────────────────────────────┐
│                        工作流技能金字塔                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   ┌───────────────────────────────────────────────────────────┐     │
│   │ Level 1: 编排技能 (Orchestration Skills)                  │     │
│   │ - 管理阶段执行顺序                                          │     │
│   │ - 处理阶段间产物传递                                        │     │
│   │ - 评审→修复循环控制                                         │     │
│   │ 示例：feature-implement, bug-fix                           │     │
│   └───────────────────────────────────────────────────────────┘     │
│                                    │                                │
│                                    ▼                                │
│   ┌───────────────────────────────────────────────────────────┐     │
│   │ Level 2: 阶段技能 (Stage Skills)                           │     │
│   │ - 执行单一阶段类型                                          │     │
│   │ - 并行分发多个执行器                                        │     │
│   │ - 验证输出产物                                              │     │
│   │ 示例：plan, requirements, rca, implement                   │     │
│   └───────────────────────────────────────────────────────────┘     │
│                                    │                                │
│                                    ▼                                │
│   ┌───────────────────────────────────────────────────────────┐     │
│   │ Level 3: 评审技能 (Review Skills)                          │     │
│   │ - 计划评审 (--plan) / 代码评审 (--code)                    │     │
│   │ - 多评审员意见聚合                                          │     │
│   │ - 自动循环直到通过                                          │     │
│   │ 示例：review                                               │     │
│   └───────────────────────────────────────────────────────────┘     │
│                                    │                                │
│                                    ▼                                │
│   ┌───────────────────────────────────────────────────────────┐     │
│   │ Level 4: 工具技能 (Utility Skills)                         │     │
│   │ - 配置管理                                                  │     │
│   │ - 单次任务执行                                              │     │
│   │ - 提示生成                                                  │     │
│   │ 示例：dev-config, once, create-prompt                      │     │
│   └───────────────────────────────────────────────────────────┘     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 二、技能开发规范

### 2.1 SKILL.md 文件结构

```markdown
---
name: sns-workflow:<skill-name>
description: <一句话描述>
user-invocable: true|false
allowed-tools: <工具列表>
---

# <技能名称>

## 前置条件
- 必需的输入产物
- 必需的前置阶段

## 执行步骤

### 步骤 1: 验证输入
[检查必需的产物文件是否存在]

### 步骤 2: 加载配置与解析执行器
[加载工作流配置，解析执行器提供者类型]

### 步骤 3: 提示组装
[组合阶段定义 + 角色提示 + 任务上下文]

### 步骤 4: 分发执行器
[根据提供者类型路由到不同后端]

### 步骤 5: 验证输出
[检查输出产物是否符合协议]

### 步骤 6: 报告结果
[向用户报告执行状态和下一步建议]

## 错误处理
[定义各种错误场景的处理方式]

## 输出产物
[列出所有输出文件路径]
```

### 2.2 执行器分发模式

```typescript
// 根据预设类型路由到不同执行后端
function dispatchExecutor(executor: Executor, prompt: string) {
  const providerType = getProviderType(executor.preset);
  
  switch (providerType) {
    case 'subscription':
      // 直接使用 Claude Agent SDK 子代理
      return Task({
        subagent_type: "general-purpose",
        model: executor.model,
        prompt: prompt
      });
      
    case 'api':
      // 后台运行 API 任务执行器
      return Bash({
        run_in_background: true,
        command: `bun api-task-runner.ts --preset ${executor.preset} --model ${executor.model}`
      });
      
    case 'cli':
      // 通过 CLI 工具执行
      return Task({
        subagent_type: "general-purpose",
        prompt: `Run: bun cli-executor.ts --preset ${executor.preset} ...`
      });
  }
}
```

### 2.3 产物文件命名规范

| 产物类型 | 命名模式 | 示例 |
|----------|---------|------|
| 用户故事 | `user-story/manifest.json` | `user-story/manifest.json` |
| 计划 | `plan/manifest.json` + `plan/steps/{N}.json` | `plan/steps/1.json` |
| 测试计划 | `plan/test-plan.json` | `plan/test-plan.json` |
| 计划评审 | `plan-review-{system_prompt}-{provider}-{model}-{index}.json` | `plan-review-plan-reviewer-anthropic-sonnet-1.json` |
| 代码评审 | `code-review-{system_prompt}-{provider}-{model}-{index}.json` | `code-review-code-reviewer-anthropic-sonnet-1.json` |
| RCA | `rca-{system_prompt}-{provider}-{model}-{index}-v{version}.json` | `rca-root-cause-analyst-anthropic-sonnet-1-v1.json` |
| 实现结果 | `impl-result.json` | `impl-result.json` |
| 实现步骤 | `impl-steps/impl-step-{N}-v{version}.json` | `impl-steps/impl-step-1-v1.json` |

### 2.4 状态协议

| 状态 | 含义 | 下一步 |
|------|------|--------|
| `approved` | 评审通过 | 进入下一阶段 |
| `needs_changes` | 需要修改 | 自动分发修复阶段，然后重新评审 |
| `needs_clarification` | 需要用户澄清 | 通过 AskUserQuestion 提问 |
| `rejected` | 重大问题 | 停止工作流，升级给用户 |

---

## 三、标准工作流模式

### 3.1 功能开发工作流

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        功能开发工作流                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────┐                                                        │
│  │ requirements │                                                        │
│  │ 收集需求     │                                                        │
│  └──────┬──────┘                                                        │
│         │ 输出：user-story/manifest.json                                │
│         ▼                                                               │
│  ┌─────────────┐                                                        │
│  │  planning   │                                                        │
│  │  创建计划   │                                                        │
│  └──────┬──────┘                                                        │
│         │ 输出：plan/manifest.json + steps/{N}.json                     │
│         ▼                                                               │
│  ┌─────────────┐                                                        │
│  │ plan-review │                                                        │
│  │  计划评审   │───[needs_changes]───┐                                 │
│  └──────┬──────┘                    │                                  │
│         │ [approved]                ▼                                  │
│         │                    ┌─────────────┐                           │
│         │                    │  plan (fix) │                           │
│         │                    │  修复计划   │                           │
│         │                    └─────────────┘                           │
│         ▼                                                               │
│  ┌─────────────┐                                                        │
│  │implementation│                                                       │
│  │  TDD 实现    │                                                        │
│  └──────┬──────┘                                                        │
│         │ 输出：impl-result.json                                        │
│         ▼                                                               │
│  ┌─────────────┐                                                        │
│  │ code-review │                                                        │
│  │  代码评审   │───[needs_changes]───┐                                 │
│  └──────┬──────┘                    │                                  │
│         │ [approved]                ▼                                  │
│         │                    ┌─────────────┐                           │
│         │                    │ implement   │                           │
│         │                    │  修复代码   │                           │
│         │                    └─────────────┘                           │
│         ▼                                                               │
│  ┌─────────────┐                                                        │
│  │   COMPLETE  │                                                        │
│  └─────────────┘                                                        │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.2 漏洞修复工作流

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        漏洞修复工作流                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────┐                                                        │
│  │     RCA     │ 多执行器并行诊断                                        │
│  │  根因分析   │                                                        │
│  └──────┬──────┘                                                        │
│         │ 输出：rca-diagnosis.json                                      │
│         ▼                                                               │
│  ┌─────────────┐                                                        │
│  │ requirements │                                                        │
│  │  修复需求   │                                                        │
│  └──────┬──────┘                                                        │
│         │ 输出：user-story/manifest.json                                │
│         ▼                                                               │
│  ┌─────────────┐                                                        │
│  │  planning   │                                                        │
│  │  修复计划   │                                                        │
│  └──────┬──────┘                                                        │
│         │ 输出：plan/manifest.json                                      │
│         ▼                                                               │
│  ┌─────────────┐                                                        │
│  │ plan-review │                                                        │
│  │  计划评审   │                                                        │
│  └──────┬──────┘                                                        │
│         ▼                                                               │
│  ┌─────────────┐                                                        │
│  │implementation│                                                       │
│  │  TDD 实现    │                                                        │
│  └──────┬──────┘                                                        │
│         ▼                                                               │
│  ┌─────────────┐                                                        │
│  │ code-review │                                                        │
│  │  代码评审   │                                                        │
│  └──────┬──────┘                                                        │
│         ▼                                                               │
│  ┌─────────────┐                                                        │
│  │   COMPLETE  │                                                        │
│  └─────────────┘                                                        │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.3 评审→修复循环

```typescript
// 伪代码：评审技能核心循环
async function runReviewLoop(reviewType: 'plan' | 'code', maxIterations: number) {
  let iteration = 0;
  let aggregatedStatus = 'pending';
  
  while (aggregatedStatus === 'needs_changes' && iteration < maxIterations) {
    // 1. 分发所有评审员
    const reviews = await distributeReviewers(reviewType);
    
    // 2. 聚合评审状态
    aggregatedStatus = aggregateStatus(reviews);
    
    if (aggregatedStatus === 'needs_changes') {
      // 3. 收集所有 must_fix 发现
      const findings = collectMustFixFindings(reviews);
      
      // 4. 写入修复上下文文件
      writeJson('.snsplay/task/review-findings-to-fix.json', {
        findings,
        review_type: reviewType
      });
      
      // 5. 分发修复阶段
      await Skill({
        skill: reviewType === 'plan' ? 'sns-workflow:plan' : 'sns-workflow:implement'
      });
      
      // 6. 清理修复上下文
      rm('.snsplay/task/review-findings-to-fix.json');
      
      iteration++;
    }
  }
  
  if (iteration >= maxIterations) {
    reportUser({
      message: `评审循环耗尽 (${maxIterations} 次)`,
      remainingFindings: collectMustFixFindings(reviews)
    });
  }
}
```

---

## 四、配置规范

### 4.1 工作流配置结构

```json
{
  "version": "3.0",
  "stages": {
    "<stage_type>": {
      "executors": [
        {
          "system_prompt": "<role_name>",
          "preset": "<preset_name>",
          "model": "<model_name>",
          "parallel": true|false
        }
      ]
    }
  },
  "feature_workflow": ["requirements", "planning", "plan-review", "implementation", "code-review"],
  "bugfix_workflow": ["rca", "requirements", "planning", "plan-review", "implementation", "code-review"],
  "max_iterations": 10,
  "max_tdd_iterations": 5
}
```

### 4.2 预设类型定义

```typescript
// API 预设
interface ApiPreset {
  type: 'api';
  name: string;
  base_url: string;
  api_key: string;
  models: string[];
  protocol?: 'anthropic' | 'openai';
  timeout_ms?: number;
}

// Subscription 预设
interface SubscriptionPreset {
  type: 'subscription';
  name: string;
}

// CLI 预设
interface CliPreset {
  type: 'cli';
  name: string;
  command: string;
  args_template: string;
  supports_resume?: boolean;
  models: string[];
}
```

### 4.3 阶段定义格式

```markdown
---
stage: <stage_type>
description: <一句话描述>
tools: <允许的工具列表>
disallowedTools: <禁止的工具列表>
---

# <阶段名称>

## 输出协议 (强制)
[必须输出的产物文件列表和格式]

## 系统流程
[阶段执行的详细步骤]

## 质量标准
[输出产物的质量要求]
```

### 4.4 角色提示格式

```markdown
---
name: <role_name>
description: <角色描述>
tools: <允许的工具列表>
disallowedTools: <禁止的工具列表>
---

# <角色描述>
[详细的角色定位和职责说明]

## 职责
[具体职责列表]

## 工作流程
[执行流程说明]
```

---

## 五、开发检查单

### 5.1 新增技能检查单

```markdown
## 新增技能检查单

### 定义阶段
- [ ] 创建 `skills/<skill-name>/SKILL.md`
- [ ] 定义元数据 (name, description, user-invocable, allowed-tools)
- [ ] 编写执行步骤文档

### 配置阶段
- [ ] 更新 `marketplace.json` (如需要发布)
- [ ] 添加技能触发命令

### 实现阶段
- [ ] 实现输入验证逻辑
- [ ] 实现配置加载逻辑
- [ ] 实现执行器分发逻辑
- [ ] 实现输出验证逻辑

### 测试阶段
- [ ] 编写单元测试
- [ ] 编写集成测试
- [ ] 编写端到端测试

### 文档阶段
- [ ] 更新技能 README
- [ ] 编写使用示例
- [ ] 编写故障排查指南
```

### 5.2 新增阶段类型检查单

```markdown
## 新增阶段类型检查单

### 定义阶段
- [ ] 创建 `stages/<stage-type>.md`
- [ ] 定义阶段元数据 (stage, description, tools, disallowedTools)
- [ ] 定义输出协议

### 角色阶段
- [ ] 创建或复用角色提示 `system-prompts/built-in/<role>.md`
- [ ] 或添加领域特定角色 `system-prompts/agents/<domain>/<role>.md`

### 类型定义阶段
- [ ] 更新 `types/stage-definitions.ts` 添加新 StageType
- [ ] 定义输出文件名生成规则
- [ ] 定义阶段验证规则

### 配置阶段
- [ ] 在默认工作流配置中添加新阶段
- [ ] 定义阶段依赖关系

### 测试阶段
- [ ] 验证阶段定义格式
- [ ] 验证角色提示格式
- [ ] 验证输出协议
```

### 5.3 新增执行器检查单

```markdown
## 新增执行器检查单

### 配置阶段
- [ ] 添加 AI 预设到 `~/.snsplay/ai-presets.json`
- [ ] 验证预设格式符合类型定义
- [ ] 测试预连接

### 集成阶段
- [ ] 实现执行器分发逻辑 (如为新类型)
- [ ] 实现错误处理逻辑
- [ ] 实现超时处理逻辑

### 测试阶段
- [ ] 测试执行器基本功能
- [ ] 测试错误恢复
- [ ] 测试超时处理
```

---

## 六、最佳实践

### 6.1 防漂移机制

| 机制 | 目的 | 实现方式 |
|------|------|----------|
| 原始请求注入 | 防止执行器偏离原始需求 | 每个执行器提示包含逐字原始请求 |
| TDD 循环 | 确保每步实现正确 | 实现每步后运行测试，失败时循环 (最多 5 次) |
| 步骤到 AC 映射 | 确保计划步骤覆盖验收标准 | 每个计划步骤必须引用 AC ID (`ac_ids[]`) |
| 基于证据的评审 | 阻止性发现需要具体证据 | `contract_reference` + `evidence` 字段 |
| 需求来源追踪 | AC 追踪其来源 | `original_request`, `user_answer`, `specialist_suggestion` |

### 6.2 错误处理规范

| 场景 | 处理方式 |
|------|---------|
| 产物文件缺失 | 报告用户需要先运行哪个前置阶段 |
| 执行器失败 | 记录失败，继续处理其余执行器 |
| 合成器失败 | 保留变体目录用于手动恢复，报告错误 |
| TDD 循环耗尽 | 通过 AskUserQuestion 升级给用户，提供选项 |
| 评审迭代耗尽 | 报告剩余 must_fix 发现，建议手动修复 |
| 多 RCA 诊断冲突 | 通过 AskUserQuestion 呈现两个诊断，让用户选择 |

### 6.3 命名规范

```typescript
// 文件名 sanitization
function sanitizeForFilename(input: string): string {
  return input
    .toLowerCase()
    .replace(/[\s_]+/g, '-')
    .replace(/[^a-z0-9.-]/g, '')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '');
}

// 示例
"Plan Reviewer" → "plan-reviewer"
"Root Cause Analyst" → "root-cause-analyst"
"Anthropic Subscription" → "anthropic"
```

### 6.4 提示组装模式

```typescript
// 组合阶段定义 + 角色提示
function composePrompt(stage: StagePrompt, role: SystemPrompt): string {
  return `${stage.content}\n\n---\n\n${role.content}`;
}

// 添加任务上下文
function assembleFullPrompt(
  stage: StagePrompt,
  role: SystemPrompt,
  taskContext: string,
  originalRequest: string
): string {
  return `## 原始请求
${originalRequest}

---

## 任务上下文
${taskContext}

---

${composePrompt(stage, role)}`;
}
```

---

## 七、调试指南

### 7.1 常见问题排查

| 问题 | 可能原因 | 排查步骤 |
|------|---------|---------|
| 技能无法触发 | 命令名称不匹配 | 检查 `SKILL.md` 中的 `name` 字段 |
| 执行器分发失败 | 预设配置错误 | 检查 `~/.snsplay/ai-presets.json` 格式 |
| 产物文件未生成 | 执行器输出不符合协议 | 检查阶段定义的输出协议 |
| 评审循环无限执行 | 评审员发现无法修复 | 检查 `max_iterations` 配置 |
| TDD 循环卡住 | 测试无法通过 | 检查测试用例是否正确 |

### 7.2 调试命令

```bash
# 查看工作流配置
bun -e "import { loadWorkflowConfig } from 'workflow-config.ts'; console.log(JSON.stringify(loadWorkflowConfig(), null, 2));"

# 查看可用系统提示
bun -e "import { discoverSystemPrompts } from 'system-prompts.ts'; console.log(discoverSystemPrompts());"

# 测试预设连接
bun -e "import { readPresets } from 'preset-utils.ts'; console.log(readPresets());"

# 查看阶段定义
cat stages/<stage-type>.md
```

### 7.3 日志位置

| 日志类型 | 位置 |
|---------|------|
| 执行器输出 | `.snsplay/task/<stage>/` |
| 评审结果 | `.snsplay/task/*.json` |
| 工作流状态 | `.snsplay/task/workflow-tasks.json` |
| 错误日志 | `.snsplay/logs/` |

---

## 八、扩展指南

### 8.1 新增领域特定角色

1. 在 `system-prompts/agents/<domain>/` 创建新角色文件
2. 遵循角色提示格式
3. 在工作流配置中引用新角色

### 8.2 自定义工作流

修改 `~/.snsplay/sns-workflow.json`:

```json
{
  "feature_workflow": ["planning", "implementation"],  // 简化工作流
  "stages": {
    "planning": {
      "executors": [
        { "system_prompt": "planner", "preset": "anthropic-subscription", "model": "opus" }
      ]
    }
  }
}
```

### 8.3 新增评审规则

1. 创建 `rules/<review-type>-guidelines.md`
2. 定义评审发现严重级别 (blocking, must_fix, should_fix, suggestion)
3. 在评审技能中引用新规则

---

## 九、附录

### 9.1 文件路径参考

```
插件根目录：/projects/snsplay-marketplace/plugins/sns-workflow/

关键文件:
- 工作流配置：~/.snsplay/sns-workflow.json
- AI 预设：~/.snsplay/ai-presets.json
- 阶段定义：plugins/sns-workflow/stages/*.md
- 角色提示：plugins/sns-workflow/system-prompts/built-in/*.md
- 技能定义：plugins/sns-workflow/skills/*/SKILL.md
- 类型定义：plugins/sns-workflow/types/*.ts
- 脚本工具：plugins/sns-workflow/scripts/*.ts
```

### 9.2 工具权限参考

| 技能类型 | 允许的工具 |
|---------|-----------|
| 编排技能 | Read, Write, Bash, Glob, Grep, Skill, AskUserQuestion |
| 阶段技能 | Read, Write, Bash, Glob, Grep, Task, TaskOutput, AskUserQuestion |
| 评审技能 | Read, Write, Bash, Glob, Grep, Task, TaskOutput, AskUserQuestion, Skill |
| 工具技能 | 根据具体功能定义 |

### 9.3 术语表

| 术语 | 定义 |
|------|------|
| Stage | 阶段，固定类型的执行单元 |
| Role | 角色，专业领域系统提示 |
| Executor | 执行器，阶段的具体执行实例 |
| Preset | AI 提供者预设配置 |
| Artifact | 产物，阶段执行输出的 JSON 文件 |
| Review Loop | 评审→修复→再审阅的自动循环 |
| TDD Loop | 测试→实现→验证的自动循环 |
