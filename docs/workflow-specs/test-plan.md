# 工作流技能测试计划

> **基于**: 规范文档 (workflow-development-spec.md) + 开发计划 (skill-development-plan.md)
> **创建日期**: 2026-04-25
> **最后更新**: 2026-04-25

---

## 测试环境准备

```bash
git worktree add -b worktree-001 .claude/worktrees/worktree-001 main
git worktree add -b worktree-002 .claude/worktrees/worktree-002 main
git worktree add -b worktree-003 .claude/worktrees/worktree-003 main
```

---

## 一、sync 技能测试

### TC-SYNC-01: 正常同步 (worktree 分支)
**步骤:** 1. `cd .claude/worktrees/worktree-001` 2. 在 main 新增 commit 并 push 3. `sns-workflow sync`
**期望:** git fetch + rebase origin/main 成功，`git log --oneline -3` 显示基于最新 main

### TC-SYNC-02: 非 worktree 分支报错
**步骤:** 1. `git checkout main` 2. `sns-workflow sync`
**期望:** 输出错误信息并 exit 1

### TC-SYNC-03: 脏状态阻止同步
**步骤:** 1. `cd .claude/worktrees/worktree-001` 2. 修改文件不提交 3. `sns-workflow sync`
**期望:** 输出错误信息 + git status --short，exit 1

### TC-SYNC-04: rebase 冲突
**步骤:** 1. `cd .claude/worktrees/worktree-001` 2. 修改同一文件同一行 3. Push main 更改 4. `sns-workflow sync`
**期望:** 输出冲突提示 + 提供 continue/abort 选项，exit 1

---

## 二、commit-push-pr 技能测试

### TC-CPP-01: worktree 分支完整流程
**步骤:** 1. `cd .claude/worktrees/worktree-001` 2. 修改文件 3. `sns-workflow commit-push-pr`
**期望:** 自动 commit + push + PR to main + merge --squash (无 --delete-branch) + hard reset origin/main

### TC-CPP-02: feature 分支完整流程
**步骤:** 1. `cd .claude/worktrees/worktree-002` 2. `sns-workflow feature test-feature` 3. 修改文件 4. `sns-workflow commit-push-pr`
**期望:** 自动 commit + push + PR to main + merge --squash --delete-branch + 切回 worktree-002

### TC-CPP-03: hotfix 分支完整流程
**前置:** v1.0.0 tag 存在
**步骤:** 1. `cd .claude/worktrees/worktree-003` 2. `sns-workflow hotfix v1.0.1` 3. 修改文件 4. `sns-workflow commit-push-pr`
**期望:** 自动 commit + push + PR to main + merge --squash --delete-branch + 在 main 打 tag v1.0.1 + 推送 tag

### TC-CPP-04: 无更改静默退出
**步骤:** 1. `cd .claude/worktrees/worktree-001` 2. 确保目录干净 3. `sns-workflow commit-push-pr`
**期望:** 输出"没有需要提交的更改"，exit 0

### TC-CPP-05: 不支持的分支类型
**步骤:** 1. `git checkout -b experimental` 2. 修改文件 3. `sns-workflow commit-push-pr`
**期望:** 输出"错误: 不支持的分支类型" + 列出支持类型，exit 1

### TC-CPP-06: push 失败
**步骤:** 1. `cd .claude/worktrees/worktree-001` 2. 修改文件 3. 配置错误远端 4. `sns-workflow commit-push-pr`
**期望:** 输出"Push 失败"，exit 1

---

## 三、feature 技能测试

### TC-FEAT-01: 正常创建 feature 分支
**步骤:** 1. `cd .claude/worktrees/worktree-001` 2. `sns-workflow feature test-feature`
**期望:** 自动 sync + 创建 feature/test-feature + 输出后续指引

### TC-FEAT-02: 非 worktree 分支报错
**步骤:** 1. `git checkout main` 2. `sns-workflow feature test-feature`
**期望:** 输出错误信息并 exit 1

### TC-FEAT-03: feature 名称格式验证
**步骤:** 1. `cd .claude/worktrees/worktree-001` 2. `sns-workflow feature Invalid_Name`
**期望:** 输出错误信息，exit 1

### TC-FEAT-04: feature 名称为空
**步骤:** 1. `cd .claude/worktrees/worktree-001` 2. `sns-workflow feature`
**期望:** 输出用法提示，exit 1

### TC-FEAT-05: 本地分支已存在
**步骤:** 1. `cd .claude/worktrees/worktree-001` 2. `sns-workflow feature test-feature` 3. 再次执行
**期望:** 输出"本地分支已存在"，exit 1

### TC-FEAT-06: sync 失败时不创建分支
**步骤:** 1. 制造 rebase 冲突 2. `sns-workflow feature test-feature`
**期望:** sync 失败退出，未创建分支

### TC-FEAT-07: 远端分支已存在
**步骤:** 1. push feature/remote-only 到远端 2. 在另一个 worktree 执行 `sns-workflow feature remote-only`
**期望:** 输出"远端分支已存在"，exit 1

---

## 四、hotfix 技能测试

### TC-HOTFIX-01: 正常创建 hotfix 分支
**前置:** v1.0.0 tag 存在
**步骤:** 1. `cd .claude/worktrees/worktree-001` 2. `sns-workflow hotfix v1.0.1`
**期望:** 自动 sync + 创建 hotfix/v1.0.1（从 v1.0.0 tag）+ 输出后续指引

### TC-HOTFIX-02: 自动版本计算
**前置:** v1.0.0 tag 存在
**步骤:** 1. `cd .claude/worktrees/worktree-001` 2. `sns-workflow hotfix`
**期望:** 输出"自动计算版本号: v1.0.0 → v1.0.1"，创建 hotfix/v1.0.1

### TC-HOTFIX-03: 非 worktree 分支报错
**步骤:** 1. `git checkout main` 2. `sns-workflow hotfix v1.0.1`
**期望:** 输出错误信息并 exit 1

### TC-HOTFIX-04: tag 不存在
**步骤:** 1. `cd .claude/worktrees/worktree-001` 2. `sns-workflow hotfix v9.9.9`
**期望:** 输出"tag 不存在"，exit 1

### TC-HOTFIX-05: 版本号格式验证
**步骤:** 1. `cd .claude/worktrees/worktree-001` 2. `sns-workflow hotfix 1.0.1`
**期望:** 输出错误信息，exit 1

### TC-HOTFIX-06: sync 失败时不创建分支
**步骤:** 1. 制造 rebase 冲突 2. `sns-workflow hotfix v1.0.1`
**期望:** sync 失败退出，未创建分支

---

## 五、release 技能测试

### TC-REL-01: 正常创建 release 分支
**步骤:** 1. `git checkout main` 2. `sns-workflow release v1.1.0`
**期望:** 创建 release/v1.1.0，基于最新 main

### TC-REL-02: 自动版本计算
**前置:** v1.0.0 tag 存在
**步骤:** 1. `git checkout main` 2. `sns-workflow release`
**期望:** 输出"自动计算版本号: v1.0.0 → v1.1.0"（递增 minor），创建 release/v1.1.0

### TC-REL-03: 迭代模式（自动递增 patch）
**前置:** 在 release/v1.1.0 分支上
**步骤:** 1. `sns-workflow release`
**期望:** 输出"迭代版本: v1.1.0 → v1.1.1"，分支更新为 release/v1.1.1

### TC-REL-04: 迭代模式（指定新版本）
**前置:** 在 release/v1.1.0 分支上
**步骤:** 1. `sns-workflow release v1.2.0`
**期望:** 分支更新为 release/v1.2.0

### TC-REL-05: 非 main 分支报错
**步骤:** 1. `cd .claude/worktrees/worktree-001` 2. `sns-workflow release v1.1.0`
**期望:** 输出错误信息并 exit 1

### TC-REL-06: 版本号格式验证
**步骤:** 1. `git checkout main` 2. `sns-workflow release 1.1.0`
**期望:** 输出错误信息，exit 1

---

## 六、publish 技能测试

### TC-PUB-01: 正常发布（无 product 分支）
**步骤:** 1. `git checkout main` 2. `sns-workflow publish v1.1.0`
**期望:** 打 tag v1.1.0 + push tag，输出"远端无 product 分支，跳过合并"

### TC-PUB-02: 自动版本计算
**前置:** v1.0.0 tag 存在
**步骤:** 1. `git checkout main` 2. `sns-workflow publish`
**期望:** 输出"自动计算版本号: v1.0.0 → v1.0.1"，打 tag v1.0.1

### TC-PUB-03: tag 已存在
**前置:** v1.0.0 tag 存在
**步骤:** 1. `git checkout main` 2. `sns-workflow publish v1.0.0`
**期望:** 输出"tag 已存在"，exit 1

### TC-PUB-04: 非 main 分支报错
**步骤:** 1. `cd .claude/worktrees/worktree-001` 2. `sns-workflow publish v1.1.0`
**期望:** 输出错误信息并 exit 1

### TC-PUB-05: 版本号格式验证
**步骤:** 1. `git checkout main` 2. `sns-workflow publish v1.1`
**期望:** 输出错误信息，exit 1

---

## 七、端到端测试

### TC-E2E-01: 快捷模式完整流程
**步骤:**
1. `git worktree add -b worktree-010 .claude/worktrees/worktree-010 main`
2. `cd .claude/worktrees/worktree-010`
3. `sns-workflow sync` (可选)
4. 修改文件
5. `sns-workflow commit-push-pr`
6. 验证: `git branch --show-current` 为 worktree-010 且与 origin/main 同步

### TC-E2E-02: Feature 模式完整流程
**步骤:**
1. `git worktree add -b worktree-011 .claude/worktrees/worktree-011 main`
2. `cd .claude/worktrees/worktree-011`
3. `sns-workflow feature my-new-feature`
4. 修改文件
5. `sns-workflow commit-push-pr`
6. 验证: 切回 worktree-011，feature/my-new-feature 已删除

### TC-E2E-03: Hotfix 完整流程
**前置:** v1.0.0 tag 存在
**步骤:**
1. `cd .claude/worktrees/worktree-012`
2. `sns-workflow hotfix v1.0.1`
3. 修改文件
4. `sns-workflow commit-push-pr`
5. 验证: PR 已合并到 main，tag v1.0.1 已创建并推送

### TC-E2E-04: Release 完整流程
**步骤:**
1. `git checkout main`
2. `sns-workflow release v1.1.0`
3. 修改文件（测试/修补）
4. `sns-workflow commit-push-pr`
5. 验证: PR 已合并到 main，release/v1.1.0 分支已删除

### TC-E2E-05: Publish 完整流程
**步骤:**
1. `git checkout main`
2. `sns-workflow publish`
3. 验证: 自动计算版本号并打 tag，tag 已推送到远端

---

## 测试统计

| 类别 | 用例数 | 类型 |
|------|--------|------|
| sync | 4 | 单元测试 |
| commit-push-pr | 6 | 集成 (需 gh CLI) |
| feature | 7 | 集成 |
| hotfix | 6 | 集成 |
| release | 6 | 混合 (2 单元 + 4 集成) |
| publish | 5 | 混合 (2 单元 + 3 集成) |
| E2E | 5 | 端到端 (需 gh CLI) |
| **总计** | **39** | |
