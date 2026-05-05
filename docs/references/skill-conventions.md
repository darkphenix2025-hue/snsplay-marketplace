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
│                        Git 分支与版本架构总览                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  版本发布线 (tag 驱动)                                                  │
│  main (x.y.z-dev.N)                                                     │
│      └──► release/x.y.z (x.y.z-rc.N) ──► tag vX.Y.Z ──► 线上服务       │
│                                                                         │
│  并行开发线 (多 worktree)                                               │
│  worktree-001 ──► [快捷模式: 直接开发] ───────────────► PR ──► main     │
│  worktree-002 ──► [Feature 模式: feature/*] ──────────► PR ──► main     │
│  worktree-003 ──► [Feature 模式: feature/*] ──────────► PR ──► main     │
│                                                                         │
│  线上热修复线                                                           │
│  tag vX.Y.Z ──► hotfix/x.y.(z+1) ──► tag vX.Y.(Z+1) ──► 回流 main/release│
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.3 分支定义与职责

| 类型 | 命名规范 | 来源 | 目标 | 用途 |
|------|---------|------|------|------|
| **main** | `main` | 默认主线 | `release/*`、被 worktree/feature/hotfix/release 回流 | 下一开发版本主线 |
| **release** | `release/<major>.<minor>.<patch>` | `main` | `tag`、`main` | 发布冻结、测试验证、发布候选演进 |
| **hotfix** | `hotfix/<major>.<minor>.<patch>` | 正式 `tag` | `tag`、`main`、活动中的 `release/*` | 线上紧急修复 |
| **worktree** | `worktree-<NNN>` | `main` | 通过 PR 合并到 `main` | 长期开发容器，可直接开发也可承载 feature |
| **feature** | `feature/<name>` | `worktree-<NNN>` | `main` | 新功能开发、大改动、实验性需求 |
| **tag** | `v<major>.<minor>.<patch>` | `release/*` 或 `hotfix/*` | 线上部署 | 唯一真实线上版本锚点 |

**关键约束：**

- 线上服务只认正式 `tag`，不认 `main`、`worktree`、`feature/*`
- `main` 上的变更必须经过 `release/*` 才能形成常规发布
- 线上问题只能通过 `hotfix/*` 修复，禁止直接在 `main` 上修线上版本
- `worktree` 是开发容器，不是版本语义单位
- 版本升级由变更性质决定，不由分支名称决定

### 1.4 版本号与状态模型

采用语义化版本号 (SemVer)：

```text
MAJOR.MINOR.PATCH[-PRERELEASE]
```

| 状态 | 版本示例 | 所在位置 | 说明 |
|------|---------|---------|------|
| **开发态** | `1.6.0-dev.3` | `main` | 下一开发版本，持续集成 |
| **候选态** | `1.6.0-rc.2` | `release/1.6.0` | 已冻结功能，只允许修复和验证 |
| **正式态** | `v1.6.0` | `tag` | 线上可部署版本 |
| **热修复目标态** | `1.6.1` | `hotfix/1.6.1` | 从线上 tag 派生的修复目标版本 |

**版本升级规则：**

| 变更性质 | 版本变化 | 典型场景 |
|----------|---------|---------|
| **Major** | `X+1.0.0` | 破坏性变更、协议不兼容 |
| **Minor** | `X.Y+1.0` | 新功能、向后兼容的能力扩展 |
| **Patch** | `X.Y.Z+1` | 缺陷修复、小优化、配置/文档修正 |

**核心原则：**

- 正式版本只以 `vX.Y.Z` 形式出现
- `main` 维护“下一版本开发态”，`release/*` 维护“当前候选态”
- `hotfix/*` 的目标版本必须大于当前线上 tag
- 预发布标识用于规范设计；若工具暂未完全支持，以分支名和流程约束为准，正式发布仍只认 `tag`

### 1.5 核心工作流

#### 1.5.1 Worktree 管理与开发模式

**Worktree 策略：**

- 按需手工创建，不预初始化
- worktree 长期保留，不随任务完成而删除
- 每个 worktree 对应一个同名长期分支
- 一个 worktree 同一时间只承载一个任务
- 合并完成后仅在工作区干净时允许 reset 到最新 `main`

```bash
# 创建新的 worktree (在 .claude/worktrees 目录下)
git worktree add -b worktree-001 .claude/worktrees/worktree-001 main

# 查看当前 worktree 列表
git worktree list
```

**Worktree 状态管理：**

| 状态 | 说明 | 识别方式 |
|------|------|----------|
| **空闲 (Idle)** | 与 `main` 同步，无进行中任务 | 工作区干净，当前分支为 `worktree-NNN` |
| **占用 (Busy)** | 正在开发任务 | 当前位于 `feature/*`，或 `worktree-NNN` 有未合并提交 |
| **落后 (Behind)** | 基线落后于 `main` | `git fetch` 后显示 behind |

**双模式开发策略：**

| 模式 | 适用场景 | 分支策略 | 版本影响 |
|------|---------|---------|---------|
| **快捷模式** | 小修复、文档、配置、微调 | 直接在 `worktree-NNN` 开发并 PR 到 `main` | 通常为 `PATCH`，若实际引入新能力则按 `MINOR` |
| **Feature 模式** | 新功能、大改动、较高风险任务 | 从 `worktree-NNN` 创建 `feature/*`，经 PR 合并到 `main` | 由变更语义决定，通常为 `MINOR` 或 `MAJOR` |

**快捷模式流程：**

```text
空闲 worktree
  -> [可选] sns-workflow sync
  -> 直接开发
  -> sns-workflow commit-push-pr
  -> 合并到 main
  -> worktree reset 到最新 main
```

**Feature 模式流程：**

```text
空闲 worktree
  -> sns-workflow feature
  -> 创建 feature/*
  -> 开发
  -> sns-workflow commit-push-pr
  -> feature/* 合并到 main
  -> 删除 feature/*
  -> 回到 worktree 基线
```

**安全约束：**

- reset 前必须确认无未提交变更
- 若 worktree 有未推送提交，禁止自动 reset
- `sync` 只同步基线，不改变版本决策
- 快捷模式是开发路径优化，不是“绕过 release 直接上线”

#### 1.5.2 场景与版本演进矩阵

| 场景 | 起点 | 主要操作 | 版本演进 | 发布方式 | 回流规则 |
|------|------|---------|---------|---------|---------|
| **空闲 worktree 直接快速开发** | `worktree-NNN` | `sync` 后直接开发并 PR 到 `main` | 按变更语义决定，通常为下一 `PATCH` | 不直接发布 | 合并后 reset 到最新 `main` |
| **从 worktree 进行 feature 开发** | `worktree-NNN` | 创建 `feature/*` 并合并到 `main` | 按变更语义决定，通常为下一 `MINOR` | 不直接发布 | 删除 `feature/*`，回到 `worktree-NNN` |
| **main 主线快速修改** | `main` 的空闲 worktree | 快捷模式完成小改动 | `x.y.z-dev.N -> x.y.(z+1)-dev.1` 或进入下一 `MINOR` | 不直接发布 | 等待后续 release |
| **创建 release** | `main` | 切 `release/x.y.z` | `main` 保持下一开发态；`release` 进入 `x.y.z-rc.1` | 否 | `release` 修复完成后回流 `main` |
| **release 演进** | `release/x.y.z` | 测试、修复、验证 | `rc.1 -> rc.2 -> ... -> x.y.z` | 仅正式发布时打 tag | 每次 release 修复都应合回 `main` |
| **正式发布到线上** | `release/x.y.z` | `publish` 打 `vX.Y.Z` tag | `x.y.z -> vX.Y.Z` | 线上按 tag 部署 | 发布完成后 `release -> main` |
| **线上 hotfix** | `tag vX.Y.Z` | 切 `hotfix/x.y.(z+1)` 并修复 | `vX.Y.Z -> vX.Y.(Z+1)` | 在 `hotfix/*` 上打新 tag | 必须回流 `main`；若有活动 release 也必须同步 |

#### 1.5.3 Release 发布工作流

**目标：** 将 `main` 上已经具备发布条件的一组变更冻结、验证并打正式 `tag`。

```text
main (1.6.0-dev.N)
  -> release/1.6.0 (1.6.0-rc.1)
  -> 1.6.0-rc.2
  -> 1.6.0
  -> tag v1.6.0
  -> release/1.6.0 回流 main
  -> main 进入下一开发态
```

**标准步骤：**

```bash
# 1. 从 main 创建 release 分支
sns-workflow release 1.6.0
# git checkout -b release/1.6.0 main

# 2. 在 release 分支进行测试与修复
# 版本演进: 1.6.0-rc.1 -> 1.6.0-rc.2 -> 1.6.0

# 3. 正式发布，创建线上 tag
sns-workflow publish 1.6.0
# git checkout release/1.6.0
# git tag -a v1.6.0 -m "Release v1.6.0"
# git push origin release/1.6.0 v1.6.0

# 4. 回流主线
git checkout main
git merge release/1.6.0
```

**Release 规则：**

- `release/*` 上禁止新增功能
- `release/*` 上只允许修复、验证、配置调整和发布准备
- 常规上线只能从 `release/*` 打正式 tag
- 发布完成后，`main` 必须进入下一开发版本

#### 1.5.4 Hotfix 修复工作流

**Hotfix 策略:**
- 从空闲 worktree 执行修复
- 从正式 `tag` 派生 hotfix 分支
- 在 `hotfix/*` 上完成修复并打新 tag
- 发布后必须回流 `main`
- 若存在活动中的 `release/*`，必须同步该修复

```text
tag v1.6.0
  -> hotfix/1.6.1
  -> 修复并验证
  -> tag v1.6.1
  -> hotfix/1.6.1 回流 main
  -> 如有活动 release，再回流 release/*
```

**标准步骤：**

```bash
# 1. 选择空闲 worktree
cd .claude/worktrees/worktree-003
sns-workflow sync

# 2. 从线上 tag 派生 hotfix 分支
git checkout -b hotfix/1.6.1 v1.6.0

# 3. 修复问题
# 修改代码...

# 4. 发布 hotfix
sns-workflow commit-push-pr
# 自动检测 hotfix/*
# 自动推送 hotfix/1.6.1
# 自动创建并打 tag v1.6.1

# 5. 回流主线
git checkout main
git merge hotfix/1.6.1

# 6. 如存在活动 release，继续同步
git checkout release/1.7.0
git merge hotfix/1.6.1
```

#### 1.5.5 回流与同步规则

**回流优先级：**

1. 线上 hotfix 发布后，优先回流 `main`
2. 若存在活动中的 `release/*`，再同步到对应 `release/*`
3. `release/*` 上的修复必须择机回流 `main`
4. worktree 合并完成后，只回到自己的基线，不直接参与发布

**冲突处理原则：**

- 当 `main` 与线上同时演进时，先保留 hotfix，再将修复合入 `main`
- 若 `main` 上已有新功能提交，hotfix 回流时禁止覆盖主线变更
- 若 release 期间出现线上 hotfix，应先完成 hotfix 发布，再同步到 release
- 所有同步动作都必须保留正式 tag 作为版本锚点

#### 1.5.6 命令行为规范

为保证规则可自动化实现，命令行为必须同时定义“允许在哪个上下文执行”“执行后版本如何变化”“执行后的分支收尾动作”。

| 命令 | 允许上下文 | 核心动作 | 版本变化 | 收尾动作 |
|------|-----------|---------|---------|---------|
| `sns-workflow sync` | `worktree-NNN` | 同步最新 `main` 到 worktree 基线 | 无 | 保持在当前 worktree 分支 |
| `sns-workflow feature` | 空闲 `worktree-NNN` | 创建 `feature/<name>` | 无立即版本变化 | 切换到新建 `feature/*` |
| `sns-workflow commit-push-pr` | `worktree-NNN` | 将快捷模式改动 PR 到 `main` | 合并后按语义进入下一 `PATCH` 或 `MINOR` | merge 后 reset worktree 到最新 `main` |
| `sns-workflow commit-push-pr` | `feature/*` | 将 feature PR 到 `main` | 合并后按语义进入下一 `MINOR`/`MAJOR`，修复型 feature 仍可为 `PATCH` | 删除 `feature/*`，回到所属 `worktree-NNN` |
| `sns-workflow release <x.y.z>` | `main` | 创建 `release/x.y.z` 并冻结发布候选 | `release` 进入 `x.y.z-rc.1` | `main` 继续下一开发态 |
| `sns-workflow publish <x.y.z>` | `release/x.y.z` | 校验后打 `vX.Y.Z` tag | `x.y.z -> vX.Y.Z` | 发布后将 `release/*` 回流 `main` |
| `sns-workflow commit-push-pr` | `hotfix/x.y.z` | 推送 hotfix、发布新 tag、触发回流 | `vX.Y.Z -> vX.Y.(Z+1)` | 回流 `main`，必要时同步活动 release |

**上下文约束：**

- `sync` 不能在 `feature/*`、`release/*`、`hotfix/*` 上改变版本语义
- `feature` 只能从空闲 `worktree-NNN` 创建，不得从 `main`、`release/*`、`hotfix/*` 创建
- `release` 只能从 `main` 创建，禁止从 `feature/*` 直接创建
- `publish` 只能在匹配的 `release/x.y.z` 上执行
- `hotfix/*` 只能从正式 `tag` 派生，禁止从 `main` 或 `release/*` 派生

**版本决策约束：**

- 命令不直接决定版本级别，版本级别由变更语义决定
- `worktree-NNN` 与 `feature/*` 只是开发路径，不是版本类别
- 对 `main` 的小修复可以走快捷模式，但形成正式发布仍必须经过 `release/*`
- 对线上版本的修复必须走 `hotfix/*`，不能用“main 已修复”替代 hotfix

#### 1.5.7 版本号模拟演练

以下演练用于验证规则是否闭环、命令行为是否可落地实施。

**演练 1：空闲 worktree 快速修复主线小问题**

```text
初始状态:
  线上 tag: v1.5.0
  main: 1.5.1-dev.1
  worktree-001: 空闲

操作:
  1. 在 worktree-001 执行 sns-workflow sync
  2. 直接修改代码
  3. 执行 sns-workflow commit-push-pr

预期结果:
  - PR: worktree-001 -> main
  - main: 1.5.1-dev.1 -> 1.5.2-dev.1
  - worktree-001 reset 到最新 main
  - 不产生正式 tag
```

**演练 2：从 worktree 创建 feature 开发新功能**

```text
初始状态:
  线上 tag: v1.5.0
  main: 1.5.2-dev.1
  worktree-002: 空闲

操作:
  1. 在 worktree-002 执行 sns-workflow feature
  2. 创建 feature/payment
  3. 开发完成后执行 sns-workflow commit-push-pr

预期结果:
  - PR: feature/payment -> main
  - main: 1.5.2-dev.1 -> 1.6.0-dev.1
  - feature/payment 删除
  - worktree-002 回到空闲基线
```

**演练 3：从 main 创建 release 并完成候选演进**

```text
初始状态:
  线上 tag: v1.5.0
  main: 1.6.0-dev.1

操作:
  1. 执行 sns-workflow release 1.6.0
  2. release/1.6.0 上修复测试问题
  3. 候选版本演进: 1.6.0-rc.1 -> 1.6.0-rc.2 -> 1.6.0
  4. 执行 sns-workflow publish 1.6.0

预期结果:
  - 新增 release/1.6.0
  - 创建 tag v1.6.0
  - release/1.6.0 回流 main
  - main 进入下一开发态
```

**演练 4：线上 hotfix，主线同时继续开发**

```text
初始状态:
  线上 tag: v1.6.0
  main: 1.6.1-dev.1
  worktree-003: 空闲

操作:
  1. 在 worktree-003 从 v1.6.0 创建 hotfix/1.6.1
  2. 修复线上 bug
  3. 执行 sns-workflow commit-push-pr
  4. 将 hotfix/1.6.1 回流 main

预期结果:
  - 创建 tag v1.6.1
  - main 保留原有开发提交，同时包含 hotfix 修复
  - 不覆盖 main 上已有功能开发
```

**演练 5：存在活动 release 时发生线上 hotfix**

```text
初始状态:
  线上 tag: v1.6.0
  main: 1.7.0-dev.1
  release/1.7.0: 1.7.0-rc.2

操作:
  1. 从 v1.6.0 创建 hotfix/1.6.1
  2. 发布 tag v1.6.1
  3. hotfix/1.6.1 -> main
  4. hotfix/1.6.1 -> release/1.7.0

预期结果:
  - 线上立即修复到 v1.6.1
  - main 不丢失 hotfix
  - release/1.7.0 在后续发布中包含该修复
```

**演练 6：应被阻止的非法操作**

```text
非法操作 A:
  在 feature/payment 上执行 publish 1.6.0
结果:
  拒绝执行，因为 publish 只能在 release/1.6.0 上运行

非法操作 B:
  从 main 创建 hotfix/1.6.1
结果:
  拒绝执行，因为 hotfix 必须从正式 tag 派生

非法操作 C:
  worktree 存在未推送提交时自动 reset
结果:
  拒绝执行，因为会造成潜在工作丢失
```

**落地判定标准：**

- 每次演练都能明确起点分支、命令、目标版本、回流目标
- 任一时刻都能唯一确定“当前线上真实版本”
- 任一修复都不会在后续 release 中丢失
- 任一 worktree 在回收前都能通过 clean/behind/busy 状态检查

#### 1.5.8 验收清单

以下清单用于验收 `sns-workflow` 的实现是否符合当前分支模型、版本规则和自动化约束。

**一、分支与上下文验收**

- `sync` 仅允许在 `worktree-NNN` 上执行
- `feature` 仅允许从空闲 `worktree-NNN` 创建
- `release <x.y.z>` 仅允许在 `main` 上执行
- `publish <x.y.z>` 仅允许在匹配的 `release/x.y.z` 上执行
- `hotfix/x.y.z` 只能从正式 `tag` 派生
- `commit-push-pr` 必须能识别 `worktree-NNN`、`feature/*`、`hotfix/*` 三类上下文

**二、版本语义验收**

- 版本升级按变更语义决定，而不是按分支名机械决定
- `main` 始终表示下一开发版本，如 `x.y.z-dev.N`
- `release/*` 始终表示候选版本，如 `x.y.z-rc.N`
- 正式发布后必须生成唯一 `tag vX.Y.Z`
- `hotfix/*` 的目标版本必须严格大于当前线上版本

**三、流程闭环验收**

- worktree 快捷模式合并后能回到最新 `main`
- feature 模式合并后能删除 `feature/*` 并回到 worktree 基线
- 常规发布必须经历 `main -> release/* -> tag`
- 线上修复必须经历 `tag -> hotfix/* -> tag`
- hotfix 发布后必须回流 `main`
- 若存在活动中的 `release/*`，hotfix 也必须同步到该 release

**四、安全约束验收**

- 工作区不干净时禁止执行会破坏状态的自动化命令
- 存在未推送提交时禁止自动 reset worktree
- 非法上下文中的命令必须明确报错并停止
- 已存在的正式 tag 不可覆盖
- 不允许从 `main` 直接修复线上版本并替代 hotfix

**五、可观察性验收**

- 每个命令都能输出当前分支、目标分支和版本决策
- 每个失败场景都能输出明确的阻止原因
- 每个成功场景都能输出下一步建议
- 发布类命令必须输出最终生成的 tag

#### 1.5.9 测试用例设计原则

为避免测试只覆盖“快乐路径”，测试设计必须同时覆盖正向、负向、边界和回流场景。

- 单元测试: 校验分支识别、版本计算、命令参数校验、非法上下文拦截
- 集成测试: 校验本地 git 操作、分支切换、tag 创建、回流逻辑
- 端到端测试: 校验一条完整业务路径是否从开发走到发布闭环
- 回归测试: 校验 hotfix、release 演进、worktree reset 等高风险路径不会退化
- 破坏性测试: 校验脏工作区、重复 tag、错误分支、版本倒退等场景被正确拒绝

### 1.6 工作流技能分类

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
