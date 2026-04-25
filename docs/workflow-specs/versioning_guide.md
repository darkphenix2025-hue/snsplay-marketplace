# 版本管理规范（Versioning & Git Workflow）

## 1. 目标

本规范用于统一项目的版本管理、分支策略与发布流程，确保：

- 版本清晰、可追溯
- 支持多 worktree 并行开发
- 支持安全发布与快速回滚
- 支持线上热修复（hotfix）
- 支持 release 演进与修复回流
- 降低团队协作成本

---

## 2. 版本号规范

采用 **Semantic Versioning（语义化版本）**：

```text
MAJOR.MINOR.PATCH[-PRERELEASE]
```

### 2.1 版本定义

| 类型 | 示例 | 说明 |
|------|------|------|
| 正式版本 | `v1.4.2` | 线上稳定版本，也是唯一真实发布版本 |
| 开发版本 | `1.5.0-dev.3` | `main` 主线开发态 |
| 候选版本 | `1.5.0-rc.2` | `release/1.5.0` 上的发布候选态 |
| 热修复目标版本 | `1.5.1` | `hotfix/1.5.1` 的目标修复版本 |

预发布版本排序（优先级由低到高）：

```text
dev < rc < 正式版本
```

> **注意**：当前 `version.sh` 仅支持正式版本 `vX.Y.Z` 的校验和计算。`dev/rc` 版本先作为规范层定义，落地实现时需同步更新 `sns_validate_version` 和 `sns_bump_version`。

### 2.2 版本变更规则

| 变更类型 | 示例 | 版本变化 |
|---------|------|---------|
| Breaking Change | API 不兼容 | MAJOR+1, MINOR→0, PATCH→0 |
| 新功能 | 新模块、向后兼容能力扩展 | MINOR+1, PATCH→0 |
| Bug 修复 | 缺陷修复、小优化、配置修正 | PATCH+1 |

### 2.3 强制约束

- 正式 Tag 必须为 `vX.Y.Z`
- `main` 上维护的是下一开发版本，如 `1.6.0-dev.3`
- `release/x.y.z` 上维护的是候选版本，如 `1.6.0-rc.2`
- `hotfix/x.y.z` 的目标版本必须大于当前线上 Tag
- 禁止修改已有 Tag
- 禁止使用非标准版本号
- 正式版本号必须递增

---

## 3. 分支与版本模型

### 3.1 分支类型

```text
main
worktree-*
feature/*
release/*
hotfix/*
tag(vX.Y.Z)
```

### 3.2 分支职责

| 类型 | 来源 | 用途 | 版本语义 |
|------|------|------|---------|
| `main` | 默认主线 | 下一版本开发主线 | `x.y.z-dev.N` |
| `worktree-*` | `main` | 并行开发容器 | 不单独承载版本语义 |
| `feature/*` | `worktree-*` | 新功能、大改动开发 | 由变更性质决定，通常进入下一 `MINOR` |
| `release/x.y.z` | `main` | 发布冻结、测试、发布准备 | `x.y.z-rc.N` |
| `hotfix/x.y.z` | 正式 Tag | 线上问题紧急修复 | `x.y.z` |
| `tag` | `release/*` 或 `hotfix/*` | 正式发布到线上 | `vX.Y.Z` |

### 3.3 核心原则

- `tag` 是唯一真实线上版本
- `main` 是未来版本，不直接代表线上版本
- 常规发布必须通过 `release/*`
- 线上修复必须通过 `hotfix/*`
- `worktree` 是开发容器，不是发布通道
- 版本升级由变更语义决定，不由分支名称决定

---

## 4. 版本演进决策矩阵

定义“什么场景触发什么操作、什么版本变化、如何回流”：

| 场景 | 起点 | 操作方式 | 版本演进 | 发布方式 | 回流规则 |
|------|------|---------|---------|---------|---------|
| 空闲 worktree 快速开发 | `worktree-*` | 直接开发并 PR 到 `main` | 通常进入下一 `PATCH`，若是新能力则进入下一 `MINOR` | 不直接发布 | 合并后 reset 到最新 `main` |
| worktree 上 feature 开发 | `worktree-*` | 创建 `feature/*` 并 PR 到 `main` | 按变更语义决定，通常为下一 `MINOR` | 不直接发布 | 删除 `feature/*`，回到 worktree 基线 |
| main 主线快速修改 | `main` 的空闲 worktree | 快捷模式完成小修复 | `x.y.z-dev.N -> x.y.(z+1)-dev.1` 或进入下一 `MINOR` | 不直接发布 | 等待后续 release |
| 创建 release | `main` | 切 `release/x.y.z` | `main` 保持下一开发态，`release` 进入 `x.y.z-rc.1` | 不发布 | release 修复完成后回流 `main` |
| release 演进 | `release/x.y.z` | 测试、修复、验证 | `rc.1 -> rc.2 -> ... -> x.y.z` | 仅正式发布时打 Tag | release 修复必须择机回流 `main` |
| 正式发布到线上 | `release/x.y.z` | `publish` 打 Tag | `x.y.z -> vX.Y.Z` | 线上按 Tag 部署 | `release/* -> main` |
| 线上 hotfix | `tag vX.Y.Z` | 切 `hotfix/x.y.(z+1)` 并修复 | `vX.Y.Z -> vX.Y.(Z+1)` | 在 `hotfix/*` 上打新 Tag | 必须回流 `main`；如有活动 release，也必须同步 |

### 4.1 版本演变示例

```text
v1.5.0                ← 当前线上版本
main: 1.5.1-dev.1     ← 主线继续开发

worktree-001 快速修复小问题
→ 合并到 main
main: 1.5.2-dev.1

worktree-002 创建 feature/payment
→ 合并到 main
main: 1.6.0-dev.1

从 main 切 release/1.6.0
release/1.6.0: 1.6.0-rc.1
release/1.6.0: 1.6.0-rc.2
release/1.6.0: 1.6.0
tag: v1.6.0

发布后 main 进入下一开发态
main: 1.6.1-dev.1

线上发现紧急问题
v1.6.0 → hotfix/1.6.1
tag: v1.6.1
hotfix/1.6.1 → main
如存在 release/1.7.0，再同步 hotfix/1.6.1 → release/1.7.0
```

---

## 5. 常规发布流程（Release）

### 5.1 开发阶段

```text
main (1.6.0-dev.N)
  ├── worktree-001 直接快速开发
  ├── worktree-002 -> feature/A
  └── worktree-003 -> feature/B
```

### 5.2 创建发布分支

```bash
git checkout -b release/1.6.0 main
```

此时：

```text
main            保持下一开发态
release/1.6.0   进入 1.6.0-rc.1
```

### 5.3 发布准备与 release 演进

版本演进：

```text
1.6.0-rc.1 -> 1.6.0-rc.2 -> 1.6.0
```

规则：

- `release/*` 上禁止新增功能
- 只允许修复、验证、配置调整、文档修订和发布准备
- release 上的实质修复必须回流 `main`

### 5.4 正式发布

```bash
git checkout release/1.6.0
git tag v1.6.0
git push origin release/1.6.0 v1.6.0
```

### 5.5 回流主线

```bash
git checkout main
git merge release/1.6.0
```

发布完成后，`main` 必须进入下一开发版本。

---

## 6. 线上 Hotfix 流程

### 6.1 创建 hotfix 分支

hotfix 必须从正式 Tag 创建：

```bash
git checkout -b hotfix/1.6.1 v1.6.0
```

### 6.2 修复并发布

```bash
git checkout hotfix/1.6.1
git tag v1.6.1
git push origin hotfix/1.6.1 v1.6.1
```

### 6.3 回流（必须执行）

先回流 `main`：

```bash
git checkout main
git merge hotfix/1.6.1
```

如存在活动中的 `release/*`，继续同步：

```bash
git checkout release/1.7.0
git merge hotfix/1.6.1
```

### 6.4 关键原则

- hotfix 必须从正式 Tag 创建
- hotfix 发布后必须回流 `main`
- 若存在活动中的 `release/*`，也必须同步修复
- 禁止从 `main` 直接修线上问题
- hotfix 的目标版本必须严格递增

---

## 7. 并行开发（Worktree 规范）

### 7.1 Worktree 模型

`sns-workflow` 使用 worktree 实现并行开发，每个任务一个独立工作目录：

```text
repo/
├── .sns-workflow/
├── main/                      ← 主仓库（main 分支）
├── .claude/worktrees/
│   ├── worktree-001/          ← 空闲或快捷模式任务
│   ├── worktree-002/          ← feature 任务
│   └── worktree-003/          ← feature 或 hotfix 任务
```

### 7.2 双模式开发

#### 快捷模式

- 适用：小修复、文档、配置、微调
- 方式：直接在 `worktree-*` 上开发并 PR 到 `main`
- 版本：通常进入下一 `PATCH`，若本质上是新能力则进入下一 `MINOR`

流程：

```text
空闲 worktree
  -> [可选] sync
  -> 直接开发
  -> commit-push-pr
  -> 合并到 main
  -> reset 到最新 main
```

#### Feature 模式

- 适用：新功能、大改动、高风险任务
- 方式：从 `worktree-*` 创建 `feature/*`
- 版本：由变更性质决定，通常进入下一 `MINOR`

流程：

```text
空闲 worktree
  -> feature
  -> 创建 feature/*
  -> 开发
  -> commit-push-pr
  -> 合并到 main
  -> 删除 feature/*
  -> 回到 worktree 基线
```

### 7.3 生命周期与安全规则

```text
创建 -> 空闲 -> 开发 -> 合并 -> 清理 -> 回到空闲
```

- 一个任务一个 worktree
- worktree 是持久化容器，不随意删除
- 通过 `/sns-workflow:sync` 同步到最新 `main`
- reset 前必须确认工作区干净
- 若存在未推送提交，禁止自动 reset
- worktree 合并完成后不直接参与发布

---

## 8. Tag 策略

### 8.1 唯一合法格式

```text
vX.Y.Z
```

### 8.2 允许的来源

Tag 只能对应：

- `release/*` 完成点
- `hotfix/*` 完成点

### 8.3 禁止行为

- 在 `main`、`worktree-*`、`feature/*` 上打正式 Tag
- 使用 Tag 标记测试版本或候选版本
- 覆盖已有 Tag
- 修改已发布版本对应的 Tag

---

## 9. 命令行为规则

为保证规则可以直接落地到 `sns-workflow` 命令实现，需要明确每个命令在不同分支上下文中的允许行为、版本效果和阻止条件。

### 9.1 命令与上下文矩阵

| 命令 | 允许上下文 | 主要行为 | 版本效果 | 必须阻止的情况 |
|------|-----------|---------|---------|--------------|
| `/sns-workflow:sync` | `worktree-*` | 同步最新 `main` 到 worktree 基线 | 无 | 当前不在 worktree、存在未处理冲突 |
| `/sns-workflow:feature` | 空闲 `worktree-*` | 创建 `feature/*` 并切换过去 | 无立即版本变化 | 当前 worktree 忙碌、工作区不干净 |
| `/sns-workflow:commit-push-pr` | `worktree-*` | 快捷模式改动合并到 `main` | 合并后按语义进入下一 `PATCH` 或 `MINOR` | 有未推送提交却尝试自动 reset |
| `/sns-workflow:commit-push-pr` | `feature/*` | Feature 合并到 `main` | 合并后按语义进入下一 `MINOR`/`MAJOR`，修复型 feature 可为 `PATCH` | 基线不明确、目标不是 `main` |
| `/sns-workflow:release <x.y.z>` | `main` | 创建 `release/x.y.z` 并进入候选态 | `release` 进入 `x.y.z-rc.1` | 当前不在 `main`、目标版本小于等于线上版本 |
| `/sns-workflow:publish <x.y.z>` | `release/x.y.z` | 校验后打 `vX.Y.Z` Tag | `x.y.z -> vX.Y.Z` | 当前不在匹配的 `release/*`、版本不一致、工作区不干净 |
| `/sns-workflow:commit-push-pr` | `hotfix/x.y.z` | 发布 hotfix、打新 Tag、触发回流 | `vX.Y.Z -> vX.Y.(Z+1)` | hotfix 不是从正式 Tag 派生、目标版本不递增 |

### 9.2 命令设计约束

- 命令不能仅通过分支名机械决定版本级别，必须结合变更语义
- `sync` 只同步代码，不改变版本
- `feature` 只负责创建开发隔离，不负责 bump 版本
- `release` 负责进入候选态，不直接形成正式版本
- `publish` 负责生成正式 Tag，不负责引入新功能
- `hotfix` 流程必须以线上正式 Tag 为起点，不能从 `main` 补做

---

## 10. 版本号操作模拟演练

以下模拟用于验证规则在实际操作中的可执行性。

### 10.1 演练一：空闲 worktree 快速修复主线问题

```text
初始状态:
  线上版本: v1.5.0
  main: 1.5.1-dev.1
  worktree-001: 空闲

步骤:
  1. /sns-workflow:sync
  2. 在 worktree-001 直接修复代码
  3. /sns-workflow:commit-push-pr

预期:
  - 合并路径: worktree-001 -> main
  - main: 1.5.1-dev.1 -> 1.5.2-dev.1
  - worktree-001 reset 到最新 main
  - 不产生正式 Tag
```

### 10.2 演练二：从 worktree 创建 feature 开发新能力

```text
初始状态:
  线上版本: v1.5.0
  main: 1.5.2-dev.1
  worktree-002: 空闲

步骤:
  1. /sns-workflow:feature
  2. 创建 feature/payment
  3. 开发并提交
  4. /sns-workflow:commit-push-pr

预期:
  - 合并路径: feature/payment -> main
  - main: 1.5.2-dev.1 -> 1.6.0-dev.1
  - feature/payment 被删除
  - worktree-002 回到空闲基线
```

### 10.3 演练三：常规 release 发布

```text
初始状态:
  线上版本: v1.5.0
  main: 1.6.0-dev.1

步骤:
  1. /sns-workflow:release 1.6.0
  2. release/1.6.0 演进: 1.6.0-rc.1 -> 1.6.0-rc.2 -> 1.6.0
  3. /sns-workflow:publish 1.6.0
  4. release/1.6.0 -> main

预期:
  - 创建 Tag: v1.6.0
  - 线上版本: v1.6.0
  - main 回流后进入下一开发态
```

### 10.4 演练四：主线开发中发生线上 hotfix

```text
初始状态:
  线上版本: v1.6.0
  main: 1.6.1-dev.1

步骤:
  1. 从 v1.6.0 创建 hotfix/1.6.1
  2. 修复线上问题
  3. /sns-workflow:commit-push-pr
  4. hotfix/1.6.1 -> main

预期:
  - 创建 Tag: v1.6.1
  - main 既保留原开发提交，也包含 hotfix 修复
  - 不允许用 main 的修复替代 hotfix 发布
```

### 10.5 演练五：活动 release 存在时发生线上 hotfix

```text
初始状态:
  线上版本: v1.6.0
  main: 1.7.0-dev.1
  release/1.7.0: 1.7.0-rc.2

步骤:
  1. 从 v1.6.0 创建 hotfix/1.6.1
  2. 发布 v1.6.1
  3. hotfix/1.6.1 -> main
  4. hotfix/1.6.1 -> release/1.7.0

预期:
  - 线上修复立即生效
  - main 不丢失修复
  - 后续 v1.7.0 发布时天然包含该 hotfix
```

### 10.6 演练六：应被阻止的非法操作

```text
非法操作 A:
  在 feature/payment 上执行 /sns-workflow:publish 1.6.0
结果:
  必须拒绝，因为 publish 只能在 release/1.6.0 上运行

非法操作 B:
  从 main 创建 hotfix/1.6.1
结果:
  必须拒绝，因为 hotfix 必须从正式 Tag 派生

非法操作 C:
  worktree 存在未推送提交时自动 reset
结果:
  必须拒绝，避免工作丢失
```

### 10.7 演练通过标准

- 能唯一确定每一步的起点分支、目标分支和版本状态
- 能唯一确定当前线上真实版本
- 任一修复在 `main`、`release/*`、线上三处都不会丢失
- 任一自动化命令在非法上下文中都会被阻止

---

## 11. 强制工程规则

必须遵守：

1. 常规发布必须通过 `release/*`
2. 所有线上修复必须通过 `hotfix/*`
3. 禁止在 `main` 直接修复线上问题
4. 禁止跳过 Tag 发布
5. 禁止将 `feature/*` 直接作为发布来源
6. `release/*` 和 `hotfix/*` 的修复必须按规则回流
7. 版本升级按变更语义决定，不按分支名机械决定

---

## 12. 核心原则（必须理解）

- `main` 是未来版本
- `release/*` 是稳定化阶段
- `tag` 是唯一真实版本
- `hotfix/*` 是线上修复通道
- `worktree` 是并行开发容器
- `feature/*` 是功能开发隔离区

---

## 13. 目标总结

本规范确保：

- 每个线上版本可追溯
- 每次发布可回滚
- 多人并行开发不冲突
- 修复不会在后续发布中丢失
- release、hotfix、worktree 流程可自动化
