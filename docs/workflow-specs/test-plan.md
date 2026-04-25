# 工作流技能测试计划

> **基于**: `workflow-development-spec.md` + `versioning_guide.md`
> **创建日期**: 2026-04-25
> **最后更新**: 2026-04-25

---

## 测试目标

本计划用于验证以下能力是否可落地实施：

- 命令在正确分支上下文中执行，在错误上下文中被阻止
- 版本号演进符合 `main -> release -> tag` 与 `tag -> hotfix -> tag` 规则
- worktree 快捷模式、feature 模式、release 演进、hotfix 回流形成闭环
- 自动化操作不会造成 worktree 数据丢失或版本混乱

---

## 测试环境准备

### 基础仓库准备

```bash
git checkout main
git pull origin main
git tag -a v1.5.0 -m "baseline tag"
git push origin v1.5.0
```

### Worktree 准备

```bash
git worktree add -b worktree-001 .claude/worktrees/worktree-001 main
git worktree add -b worktree-002 .claude/worktrees/worktree-002 main
git worktree add -b worktree-003 .claude/worktrees/worktree-003 main
```

### 测试前置约定

- 默认存在远端 `origin`
- 需要 PR 的用例要求可用的 Git 平台 CLI 或对应 mock
- 正式 tag 只允许使用 `vX.Y.Z`
- 所有用例执行前应记录当前分支、当前最新 tag、`git status`、`git branch -vv`

---

## 一、验收清单

### A. 分支上下文验收

- `sync` 仅允许在 `worktree-*` 上执行
- `feature` 仅允许从空闲 `worktree-*` 创建
- `release <x.y.z>` 仅允许在 `main` 执行
- `publish <x.y.z>` 仅允许在 `release/x.y.z` 执行
- `commit-push-pr` 能正确识别 `worktree-*`、`feature/*`、`hotfix/*`
- `hotfix/*` 必须从正式 tag 派生

### B. 版本规则验收

- `main` 保持开发态版本，如 `x.y.z-dev.N`
- `release/*` 保持候选态版本，如 `x.y.z-rc.N`
- `publish` 成功后生成唯一 `tag vX.Y.Z`
- `hotfix/*` 发布后生成更高 patch 版本的 tag
- 版本升级由变更语义决定，不由分支名称机械决定

### C. 流程闭环验收

- 快捷模式合并后 worktree reset 到最新 `main`
- Feature 模式合并后删除 `feature/*` 并回到 worktree 基线
- 常规发布完整经历 `main -> release/* -> tag -> main`
- 线上修复完整经历 `tag -> hotfix/* -> tag -> main`
- 若存在活动 `release/*`，hotfix 必须继续同步到该 release

### D. 安全约束验收

- 工作区不干净时阻止危险命令
- 存在未推送提交时阻止自动 reset
- 非法上下文下的命令必须明确报错
- 已存在 tag 不可覆盖
- 不允许使用 `main` 修复替代 hotfix 发布

### E. 可观察性验收

- 成功输出包含当前分支、目标分支、目标版本
- 失败输出包含明确阻止原因
- 发布类命令输出最终 tag
- 回流类操作输出回流目标和结果

---

## 二、单元测试用例

### 2.1 分支识别与上下文校验

### TC-UNIT-BR-01: 识别 `worktree-*` 分支
**输入:** `worktree-001`
**期望:** 识别为 worktree 上下文

### TC-UNIT-BR-02: 识别 `feature/*` 分支
**输入:** `feature/payment`
**期望:** 识别为 feature 上下文

### TC-UNIT-BR-03: 识别 `release/*` 分支
**输入:** `release/1.6.0`
**期望:** 识别为 release 上下文

### TC-UNIT-BR-04: 识别 `hotfix/*` 分支
**输入:** `hotfix/1.6.1`
**期望:** 识别为 hotfix 上下文

### TC-UNIT-BR-05: 拒绝未知分支类型
**输入:** `experimental/foo`
**期望:** 返回“不支持的分支类型”

### 2.2 版本计算与比较

### TC-UNIT-VER-01: patch 递增
**输入:** `1.5.1`
**期望:** 输出 `1.5.2`

### TC-UNIT-VER-02: minor 递增
**输入:** `1.5.2`
**期望:** 输出 `1.6.0`

### TC-UNIT-VER-03: major 递增
**输入:** `1.6.0`
**期望:** 输出 `2.0.0`

### TC-UNIT-VER-04: hotfix 目标版本必须大于线上版本
**输入:** 当前 tag `v1.6.0`，目标 hotfix `1.6.0`
**期望:** 校验失败

### TC-UNIT-VER-05: tag 格式校验
**输入:** `1.6.0`
**期望:** 校验失败，必须为 `v1.6.0`

### 2.3 命令参数与上下文阻止

### TC-UNIT-CMD-01: `sync` 在 `main` 上执行
**步骤:** 当前分支 `main` 执行 `sns-workflow sync`
**期望:** 拒绝执行并报错

### TC-UNIT-CMD-02: `feature` 在 busy worktree 上执行
**步骤:** 当前 `worktree-001` 已有未合并提交，再执行 `sns-workflow feature`
**期望:** 拒绝执行并报错

### TC-UNIT-CMD-03: `release` 在 `feature/*` 上执行
**步骤:** 当前分支 `feature/payment`，执行 `sns-workflow release 1.6.0`
**期望:** 拒绝执行并报错

### TC-UNIT-CMD-04: `publish` 在错误 release 分支上执行
**步骤:** 当前分支 `release/1.6.0`，执行 `sns-workflow publish 1.7.0`
**期望:** 拒绝执行并报错

---

## 三、集成测试用例

## 3.1 sync

### TC-SYNC-01: worktree 正常同步
**步骤:** 1. `cd .claude/worktrees/worktree-001` 2. 在 `main` 新增 commit 并 push 3. 执行 `sns-workflow sync`
**期望:** worktree 基线同步到最新 `main`

### TC-SYNC-02: 脏工作区阻止同步
**步骤:** 1. 修改 worktree 文件不提交 2. 执行 `sns-workflow sync`
**期望:** 输出脏状态并停止

### TC-SYNC-03: rebase 冲突处理
**步骤:** 1. 在 worktree 和 main 修改同一行 2. 执行 `sns-workflow sync`
**期望:** 输出冲突提示并停止，不隐式覆盖代码

## 3.2 feature

### TC-FEAT-01: 从空闲 worktree 创建 feature
**步骤:** 1. `cd .claude/worktrees/worktree-002` 2. 执行 `sns-workflow feature payment`
**期望:** 创建 `feature/payment` 并切换过去

### TC-FEAT-02: 非 worktree 上拒绝创建 feature
**步骤:** 1. `git checkout main` 2. 执行 `sns-workflow feature payment`
**期望:** 拒绝执行

### TC-FEAT-03: 名称非法
**步骤:** 在 worktree 执行 `sns-workflow feature Invalid_Name`
**期望:** 拒绝执行并提示命名规范

## 3.3 commit-push-pr

### TC-CPP-01: 快捷模式合并到 main
**步骤:** 1. 在 `worktree-001` 修改文件 2. 执行 `sns-workflow commit-push-pr`
**期望:** 合并到 `main`，随后 reset worktree 到最新 `main`

### TC-CPP-02: Feature 模式合并到 main
**步骤:** 1. 在 `feature/payment` 修改文件 2. 执行 `sns-workflow commit-push-pr`
**期望:** PR 合并到 `main`，删除 `feature/payment`，回到 `worktree-002`

### TC-CPP-03: Hotfix 分支发布并触发回流
**前置:** 已从 `v1.6.0` 派生 `hotfix/1.6.1`
**步骤:** 1. 修改文件 2. 执行 `sns-workflow commit-push-pr`
**期望:** 生成 `v1.6.1`，并触发回流 `main`

### TC-CPP-04: 无变更时退出
**步骤:** 在干净 worktree 执行 `sns-workflow commit-push-pr`
**期望:** 输出“没有需要提交的更改”

### TC-CPP-05: 未知分支类型拒绝执行
**步骤:** 切到 `experimental/foo` 并执行 `sns-workflow commit-push-pr`
**期望:** 拒绝执行

## 3.4 release

### TC-REL-01: 从 main 创建 release
**步骤:** 1. `git checkout main` 2. 执行 `sns-workflow release 1.6.0`
**期望:** 创建 `release/1.6.0` 并进入候选态

### TC-REL-02: release 版本不能小于等于线上版本
**前置:** 当前线上 tag 为 `v1.6.0`
**步骤:** 在 `main` 执行 `sns-workflow release 1.6.0`
**期望:** 拒绝执行

### TC-REL-03: 非 main 分支拒绝创建 release
**步骤:** 在 `worktree-001` 执行 `sns-workflow release 1.6.0`
**期望:** 拒绝执行

## 3.5 publish

### TC-PUB-01: 在匹配 release 分支上发布
**步骤:** 1. `git checkout release/1.6.0` 2. 执行 `sns-workflow publish 1.6.0`
**期望:** 创建并推送 `v1.6.0`

### TC-PUB-02: 在非 release 分支上发布
**步骤:** 1. `git checkout main` 2. 执行 `sns-workflow publish 1.6.0`
**期望:** 拒绝执行

### TC-PUB-03: 重复 tag
**前置:** `v1.6.0` 已存在
**步骤:** 在 `release/1.6.0` 再次执行 `sns-workflow publish 1.6.0`
**期望:** 拒绝执行

---

## 四、场景测试用例

### TC-SCN-01: 快捷模式版本演进
**初始状态:** `v1.5.0`，`main = 1.5.1-dev.1`
**步骤:** `worktree-001` 直接修复并合并
**期望:** `main -> 1.5.2-dev.1`

### TC-SCN-02: Feature 模式版本演进
**初始状态:** `v1.5.0`，`main = 1.5.2-dev.1`
**步骤:** `feature/payment` 合并
**期望:** `main -> 1.6.0-dev.1`

### TC-SCN-03: release 候选演进
**初始状态:** `main = 1.6.0-dev.1`
**步骤:** 创建 `release/1.6.0`，推进 `rc.1 -> rc.2 -> 1.6.0`
**期望:** `publish` 后生成 `v1.6.0`

### TC-SCN-04: hotfix 与主线并行
**初始状态:** `v1.6.0`，`main = 1.6.1-dev.1`
**步骤:** 从 `v1.6.0` 创建 `hotfix/1.6.1` 并发布
**期望:** 生成 `v1.6.1`，再回流 `main`

### TC-SCN-05: 活动 release 存在时的 hotfix
**初始状态:** `v1.6.0`，`main = 1.7.0-dev.1`，`release/1.7.0 = 1.7.0-rc.2`
**步骤:** 发布 `hotfix/1.6.1` 并同步 `main` 与 `release/1.7.0`
**期望:** 线上、主线、活动 release 三者都包含修复

---

## 五、负向测试用例

### TC-NEG-01: 用 main 修线上修复替代 hotfix
**步骤:** 直接在 `main` 修复线上问题并尝试发布
**期望:** 被流程规则判定为非法

### TC-NEG-02: 脏 worktree 自动 reset
**步骤:** worktree 存在未提交变更后触发自动 reset
**期望:** 被阻止

### TC-NEG-03: 从 feature 直接创建 release
**步骤:** 在 `feature/payment` 执行 `sns-workflow release 1.6.0`
**期望:** 被阻止

### TC-NEG-04: 从 main 创建 hotfix
**步骤:** 在 `main` 直接创建 `hotfix/1.6.1`
**期望:** 被阻止

### TC-NEG-05: 发布版本回退
**前置:** 当前线上版本为 `v1.6.0`
**步骤:** 尝试发布 `v1.5.9`
**期望:** 被阻止

---

## 六、端到端测试

### TC-E2E-01: 快捷模式完整路径
**步骤:**
1. 创建 `worktree-010`
2. 执行 `sns-workflow sync`
3. 直接修改代码
4. 执行 `sns-workflow commit-push-pr`
5. 验证 worktree 已回到最新 `main`

### TC-E2E-02: Feature 模式完整路径
**步骤:**
1. 创建 `worktree-011`
2. 执行 `sns-workflow feature payment`
3. 修改代码
4. 执行 `sns-workflow commit-push-pr`
5. 验证 feature 已删除且 worktree 已回收

### TC-E2E-03: Release 完整路径
**步骤:**
1. 在 `main` 执行 `sns-workflow release 1.6.0`
2. 在 `release/1.6.0` 做修复
3. 执行 `sns-workflow publish 1.6.0`
4. 回流 `main`
5. 验证 `v1.6.0` 已生成

### TC-E2E-04: Hotfix 完整路径
**步骤:**
1. 从 `v1.6.0` 创建 `hotfix/1.6.1`
2. 修复问题
3. 执行 `sns-workflow commit-push-pr`
4. 回流 `main`
5. 验证 `v1.6.1` 已生成

### TC-E2E-05: Hotfix 与活动 release 并行完整路径
**步骤:**
1. `main` 存在 `release/1.7.0`
2. 发布 `hotfix/1.6.1`
3. 回流 `main`
4. 同步到 `release/1.7.0`
5. 验证后续 `v1.7.0` 含该修复

---

## 七、测试统计

| 类别 | 用例数 | 类型 |
|------|--------|------|
| 验收清单 | 25 | 规范验收 |
| 单元测试 | 14 | 单元 |
| 集成测试 | 17 | 集成 |
| 场景测试 | 5 | 场景 |
| 负向测试 | 5 | 负向 |
| 端到端测试 | 5 | E2E |
| **总计** | **71** | |

---

## 八、执行建议

- 优先实现分支识别、版本校验、非法上下文阻止的单元测试
- 再实现 `sync`、`feature`、`release`、`publish`、`commit-push-pr` 的集成测试
- 最后补齐 release/hotfix 并行场景的 E2E 测试
- 若 Git 平台 CLI 不稳定，优先 mock PR 创建与合并步骤，仅保留本地 git 与版本验证为真实执行
