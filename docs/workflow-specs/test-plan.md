# 工作流技能测试计划

> **基于**: 规范文档 (workflow-development-spec.md) + 开发计划 (skill-development-plan.md)
> **创建日期**: 2026-04-25

---

## 测试环境准备

需要创建 worktree 环境：

```bash
git worktree add -b worktree-001 .claude/worktrees/worktree-001 main
git worktree add -b worktree-002 .claude/worktrees/worktree-002 main
git worktree add -b worktree-003 .claude/worktrees/worktree-003 main
```

---

## 一、sync 技能测试

### TC-SYNC-01: 正常同步 (worktree 分支)
**步骤:**
1. `cd .claude/worktrees/worktree-001`
2. 在 main 分支上新增一个 commit 并 push
3. `sns-workflow sync`
**期望:**
- git fetch + rebase origin/main 成功
- `git log --oneline -3` 显示基于最新 main

### TC-SYNC-02: 在非 worktree 分支上执行报错
**步骤:**
1. `git checkout main`
2. `sns-workflow sync`
**期望:**
- 输出错误信息并 exit 1

### TC-SYNC-03: 脏状态阻止同步
**步骤:**
1. `cd .claude/worktrees/worktree-001`
2. 修改一个文件但不提交
3. `sns-workflow sync`
**期望:**
- 输出错误信息 + git status --short
- exit 1

### TC-SYNC-04: rebase 冲突
**步骤:**
1. `cd .claude/worktrees/worktree-001`
2. 在 worktree-001 和 main 上修改同一文件同一行
3. Push main 的更改
4. `sns-workflow sync`
**期望:**
- 输出 "同步冲突: rebase 遇到冲突"
- 提供 git rebase --continue / --abort 选项
- exit 1

---

## 二、commit-push-pr 技能测试

### TC-CPP-01: worktree 分支完整流程
**步骤:**
1. `cd .claude/worktrees/worktree-001`
2. 修改一个文件
3. `sns-workflow commit-push-pr`
**期望:**
- 自动 git add + commit
- 自动 push
- gh pr create --base main
- gh pr merge --squash (无 --delete-branch)
- git reset --hard origin/main
- 最终在 worktree-001 分支且与最新 main 同步

### TC-CPP-02: feature 分支完整流程
**步骤:**
1. `cd .claude/worktrees/worktree-002`
2. `sns-workflow feature test-feature`
3. 修改一个文件
4. `sns-workflow commit-push-pr`
**期望:**
- 自动 commit + push
- gh pr create --base main
- gh pr merge --squash --delete-branch
- 自动切回 worktree-002
- feature/test-feature 分支已删除

### TC-CPP-03: hotfix 分支完整流程
**前置:** 需要一个 v1.0.0 tag
**步骤:**
1. `cd .claude/worktrees/worktree-003`
2. `sns-workflow sync`
3. `git checkout -b hotfix/v1.0.1 v1.0.0`
4. 修改一个文件
5. `sns-workflow commit-push-pr`
**期望:**
- 自动 commit + push
- gh pr create --base product
- gh pr merge --squash --delete-branch
- 在 product 上打 tag v1.0.1
- 创建 product→main 同步 PR
- 输出完成信息

### TC-CPP-04: 无更改时静默退出
**步骤:**
1. `cd .claude/worktrees/worktree-001`
2. 确保工作目录干净
3. `sns-workflow commit-push-pr`
**期望:**
- 输出 "没有需要提交的更改"
- exit 0

### TC-CPP-05: gh CLI 未安装
**步骤:**
1. 临时移除 gh 命令
2. `cd .claude/worktrees/worktree-001`
3. `sns-workflow commit-push-pr`
**期望:**
- 输出 "错误: gh CLI 未安装或未认证"
- exit 1

### TC-CPP-06: 不支持的分支类型
**步骤:**
1. `git checkout -b experimental`
2. 修改一个文件
3. `sns-workflow commit-push-pr`
**期望:**
- 输出 "错误: 不支持的分支类型"
- 列出支持的分支类型
- exit 1

### TC-CPP-07: push 失败
**步骤:**
1. `cd .claude/worktrees/worktree-001`
2. 修改一个文件
3. 断开网络或配置错误远端
4. `sns-workflow commit-push-pr`
**期望:**
- 输出 "Push 失败，请检查远程权限"
- exit 1

---

## 三、feature 技能测试

### TC-FEAT-01: 正常创建 feature 分支
**步骤:**
1. `cd .claude/worktrees/worktree-001`
2. `sns-workflow feature test-feature`
**期望:**
- 自动 sync (git fetch + rebase origin/main)
- 创建并切换到 feature/test-feature
- 输出后续指引

### TC-FEAT-02: 在非 worktree 分支上执行报错
**步骤:**
1. `git checkout main`
2. `sns-workflow feature test-feature`
**期望:**
- 输出错误信息并 exit 1

### TC-FEAT-03: feature 名称格式验证
**步骤:**
1. `cd .claude/worktrees/worktree-001`
2. `sns-workflow feature Invalid_Name`
**期望:**
- 输出错误信息
- exit 1

### TC-FEAT-04: feature 名称为空
**步骤:**
1. `cd .claude/worktrees/worktree-001`
2. `sns-workflow feature`
**期望:**
- 输出用法提示
- exit 1

### TC-FEAT-05: 分支已存在 (本地)
**步骤:**
1. `cd .claude/worktrees/worktree-001`
2. 先执行 `sns-workflow feature test-feature`
3. 再执行 `sns-workflow feature test-feature`
**期望:**
- 输出 "本地分支已存在"
- exit 1

### TC-FEAT-06: sync 失败时不创建分支
**步骤:**
1. `cd .claude/worktrees/worktree-001`
2. 在 worktree-001 和 main 上修改同一文件同一行
3. Push main 的更改
4. `sns-workflow feature test-feature`
**期望:**
- sync 失败退出
- 未创建 feature/test-feature 分支

### TC-FEAT-07: 远端分支已存在
**步骤:**
1. 先创建 feature/remote-only 并 push 到远端
2. 在另一个 worktree 上执行 `sns-workflow feature remote-only`
**期望:**
- 输出 "远端分支已存在"
- exit 1

---

## 四、release 技能测试

### TC-REL-01: 正常创建 release 分支
**步骤:**
1. `git checkout main`
2. `sns-workflow release v1.1.0`
**期望:**
- 创建 release/v1.1.0 分支
- 基于最新 main

### TC-REL-02: 在非 main 分支上执行报错
**步骤:**
1. `cd .claude/worktrees/worktree-001`
2. `sns-workflow release v1.1.0`
**期望:**
- 输出错误信息并 exit 1

### TC-REL-03: 版本号格式验证
**步骤:**
1. `git checkout main`
2. `sns-workflow release 1.1.0` (缺少 v 前缀)
**期望:**
- 输出错误信息
- exit 1

### TC-REL-04: 版本号为空
**步骤:**
1. `git checkout main`
2. `sns-workflow release`
**期望:**
- 输出用法提示
- exit 1

---

## 五、publish 技能测试

### TC-PUB-01: 正常发布
**前置:** release/v1.1.0 已合并到 main，无 v1.1.0 tag
**步骤:**
1. `git checkout main`
2. `sns-workflow publish v1.1.0`
**期望:**
- 打 tag v1.1.0 并 push
- 切换到 product 分支并 merge main
- 切回 main
- 输出完成信息

### TC-PUB-02: tag 已存在
**前置:** v1.0.0 tag 已存在
**步骤:**
1. `git checkout main`
2. `sns-workflow publish v1.0.0`
**期望:**
- 输出错误信息
- exit 1

### TC-PUB-03: 在非 main 分支上执行报错
**步骤:**
1. `cd .claude/worktrees/worktree-001`
2. `sns-workflow publish v1.1.0`
**期望:**
- 输出错误信息并 exit 1

### TC-PUB-04: 版本号格式验证
**步骤:**
1. `git checkout main`
2. `sns-workflow publish v1.1` (缺少 patch)
**期望:**
- 输出错误信息
- exit 1

---

## 六、端到端测试

### TC-E2E-01: 快捷模式完整流程
**步骤:**
1. `git worktree add -b worktree-010 .claude/worktrees/worktree-010 main`
2. `cd .claude/worktrees/worktree-010`
3. `sns-workflow sync` (可选)
4. 修改一个文件
5. `sns-workflow commit-push-pr`
6. 验证: `git branch --show-current` 应为 worktree-010
7. 验证: `git log --oneline -1` 应与 origin/main 同步
**期望:** 所有步骤成功

### TC-E2E-02: Feature 模式完整流程
**步骤:**
1. `git worktree add -b worktree-011 .claude/worktrees/worktree-011 main`
2. `cd .claude/worktrees/worktree-011`
3. `sns-workflow feature my-new-feature`
4. 修改一个文件
5. `sns-workflow commit-push-pr`
6. 验证: `git branch --show-current` 应为 worktree-011
7. 验证: `git branch | grep my-new-feature` 应为空
**期望:** 所有步骤成功

### TC-E2E-03: Hotfix 完整流程
**前置:** product 分支存在，v1.0.0 tag 存在
**步骤:**
1. `cd .claude/worktrees/worktree-012`
2. `sns-workflow sync`
3. `git checkout -b hotfix/v1.0.2 v1.0.0`
4. 修改一个文件
5. `sns-workflow commit-push-pr`
6. 验证: PR 已合并到 product
7. 验证: tag v1.0.2 已创建
8. 验证: product→main 同步 PR 已创建
**期望:** 所有步骤成功

### TC-E2E-04: Release + Publish 完整流程
**步骤:**
1. `git checkout main`
2. `sns-workflow release v2.0.0`
3. (测试完成)
4. `git checkout main`
5. `sns-workflow publish v2.0.0`
6. 验证: tag v2.0.0 存在
7. 验证: product 分支包含 main 的更改
**期望:** 所有步骤成功
