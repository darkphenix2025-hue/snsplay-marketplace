# SNS-Workflow 技能开发计划

> **基于**: 《工作流技能开发规范》(docs/workflow-specs/workflow-development-spec.md)
> **创建日期**: 2026-04-25
> **最后更新**: 2026-04-25

---

## 一、现状概览

### 1.1 已有实现 (11 个技能)

| 技能 | 规范章节 | 实现路径 | 状态 |
|------|---------|---------|------|
| sns-workflow:requirements | 3.1 | `plugins/sns-workflow/skills/requirements/` | ✅ 已有 |
| sns-workflow:plan | 3.1 | `plugins/sns-workflow/skills/plan/` | ✅ 已有 |
| sns-workflow:review | 3.3 | `plugins/sns-workflow/skills/review/` | ✅ 已有 |
| sns-workflow:implement | 3.1 | `plugins/sns-workflow/skills/implement/` | ✅ 已有 |
| sns-workflow:rca | 3.2 | `plugins/sns-workflow/skills/rca/` | ✅ 已有 |
| sns-workflow:bug-fix | 3.2 | `plugins/sns-workflow/skills/bug-fix/` | ✅ 已有 |
| sns-workflow:feature-implement | 1.5.2 | `plugins/sns-workflow/skills/feature-implement/` | ✅ 已有 |
| sns-workflow:dev-config | 4 | `plugins/sns-workflow/skills/dev-config/` | ✅ 已有 |
| sns-workflow:once | Level 4 | `plugins/sns-workflow/skills/once/` | ✅ 已有 |
| sns-workflow:create-prompt | Level 4 | `plugins/sns-workflow/skills/create-prompt/` | ✅ 已有 |
| sns-workflow:chatroom | Level 1 | `plugins/sns-workflow/skills/chatroom/` | ✅ 已有 |

### 1.2 待开发 (5 个核心技能)

| 技能 | 规范章节 | 类型 | 优先级 |
|------|---------|------|--------|
| sns-workflow:sync | 1.5.1 | 工具技能 | P0 |
| sns-workflow:commit-push-pr | 1.5.2 | 编排技能 | P0 |
| sns-workflow:feature (独立分支创建) | 1.5.2 | 编排技能 | P0 |
| sns-workflow:release | 1.5.3 | 编排技能 | P2 |
| sns-workflow:publish | 1.5.3 | 编排技能 | P2 |

### 1.3 已有但需重构的技能

| 技能 | 问题 | 修改内容 |
|------|------|---------|
| sns-workflow:feature-implement | 与 sync + feature 新流程不兼容 | 调整为只负责 feature 内部实现 |
| sns-workflow:bug-fix | 与 hotfix 新流程不兼容 | 调整为与 commit-push-pr 配合 |

---

## 二、开发计划

### Phase 1: 核心基础设施 (P0)

#### 1.1 sns-workflow:sync

**目标**: 独立的分支同步命令，为快捷模式和 Feature 模式提供可选的 main 代码同步

**依赖**: 无

**实现步骤**:

| 步骤 | 内容 | 文件 |
|------|------|------|
| 1 | 创建 `skills/sync/SKILL.md` | SKILL.md 定义 |
| 2 | 实现同步逻辑: git fetch + rebase origin/main | sync.sh |
| 3 | 检测 worktree 状态，验证当前分支为 worktree-NNN | 验证逻辑 |
| 4 | 处理冲突场景: rebase 冲突时提示用户 | 错误处理 |
| 5 | 测试: 快速模式 sync、Feature 模式 sync、冲突场景 | 集成测试 |

**关键逻辑**:

```bash
# 步骤 1: 验证当前在 worktree 分支
current_branch=$(git branch --show-current)
if [[ ! "$current_branch" =~ ^worktree- ]]; then
  echo "错误: sync 仅在 worktree 分支上使用"
  exit 1
fi

# 步骤 2: Fetch 最新代码
git fetch origin main

# 步骤 3: Rebase 到最新 main
git rebase origin/main

# 步骤 4: 处理冲突 (如果有)
if rebase 失败; then
  echo "同步冲突，请手动解决或执行: git rebase --abort"
  exit 1
fi
```

**验收标准**:
- [ ] 在 worktree 分支上执行 `sns-workflow sync` 能成功同步 main
- [ ] 在非 worktree 分支上执行报错退出
- [ ] rebase 冲突时提供明确提示信息
- [ ] 同步后 `git log --oneline -5` 显示基于最新 main

---

#### 1.2 sns-workflow:commit-push-pr

**目标**: 统一提交+推送+PR+合并+清理，自动检测分支类型执行不同处理

**依赖**: 无

**实现步骤**:

| 步骤 | 内容 | 文件 |
|------|------|------|
| 1 | 创建 `skills/commit-push-pr/SKILL.md` | SKILL.md 定义 |
| 2 | 实现分支类型检测: worktree-NNN / feature/* / hotfix/* | 检测逻辑 |
| 3 | 实现 commit 逻辑: git add -A + 自动提交 | commit.sh |
| 4 | 实现 push + PR 创建: gh pr create | push.sh |
| 5 | 实现 merge 逻辑: gh pr merge --squash | merge.sh |
| 6 | 实现清理逻辑: 各分支类型后处理 | cleanup.sh |
| 7 | 测试: 三种分支类型的完整流程 | 集成测试 |

**分支类型处理矩阵**:

| 分支类型 | PR 目标 | merge 后动作 |
|---------|---------|-------------|
| `worktree-NNN` | main | `git fetch origin main && git reset --hard origin/main` |
| `feature/*` | main | 删除 feature 分支 + `git checkout worktree-NNN` |
| `hotfix/*` | product | 打新 tag + 自动创建 product→main 同步 PR |

**关键逻辑**:

```bash
# 步骤 1: 检测当前分支类型
current_branch=$(git branch --show-current)

# 步骤 2: 自动 commit (开发阶段无手动 commit)
git add -A
if [[ $(git diff --cached --stat) ]]; then
  commit_msg="chore: auto commit from $current_branch"
  git commit -m "$commit_msg"
fi

# 步骤 3: Push + 创建 PR
case "$current_branch" in
  worktree-*)
    gh pr create --base main --head "$current_branch"
    gh pr merge --squash --delete-branch
    # 清理: hard reset 到最新 main
    git fetch origin main
    git reset --hard origin/main
    ;;
  feature/*)
    gh pr create --base main --head "$current_branch"
    gh pr merge --squash --delete-branch
    # 清理: 回到 worktree 分支
    git checkout worktree-NNN  # 从 feature 名称推导 worktree 编号
    ;;
  hotfix/*)
    gh pr create --base product --head "$current_branch"
    gh pr merge --squash --delete-branch
    # 清理: 打新 tag + 同步到 main
    new_tag=$(extract_version "$current_branch")
    gh api repos/{owner}/{repo}/git/refs -m "ref: refs/tags/$new_tag"
    # 创建 product→main 同步 PR
    gh pr create --base main --head product
    ;;
esac
```

**验收标准**:
- [ ] worktree 分支: commit + PR + merge + hard reset 完整执行
- [ ] feature 分支: commit + PR + merge + 删除分支 + 回到 worktree
- [ ] hotfix 分支: commit + PR to product + 打 tag + 同步 to main
- [ ] 所有场景下 PR 描述自动生成
- [ ] merge 失败时不执行清理步骤

---

#### 1.3 sns-workflow:feature (独立命令)

**目标**: Feature 模式的入口命令，自动 sync + 创建 feature 分支

**依赖**: sns-workflow:sync (步骤 2 调用)

**实现步骤**:

| 步骤 | 内容 | 文件 |
|------|------|------|
| 1 | 创建 `skills/feature/SKILL.md` | SKILL.md 定义 |
| 2 | 实现 feature 名称输入和验证 | 验证逻辑 |
| 3 | 实现自动 sync: 调用 sync 技能 | 集成 sync |
| 4 | 创建 feature/* 分支: git checkout -b | 分支创建 |
| 5 | 测试: 正常流程、sync 冲突、分支名验证 | 集成测试 |

**关键逻辑**:

```bash
# 步骤 1: 验证当前在 worktree 分支
current_branch=$(git branch --show-current)
if [[ ! "$current_branch" =~ ^worktree- ]]; then
  echo "错误: feature 命令仅在 worktree 分支上使用"
  exit 1
fi

# 步骤 2: 提示输入 feature 名称
read -p "输入 feature 名称: " feature_name
# 验证名称格式: 只允许小写字母、数字、连字符
if [[ ! "$feature_name" =~ ^[a-z0-9-]+$ ]]; then
  echo "错误: feature 名称只允许小写字母、数字、连字符"
  exit 1
fi

# 步骤 3: 自动 sync (可选，但 feature 模式默认执行)
git fetch origin main
git rebase origin/main

# 步骤 4: 创建 feature 分支
git checkout -b "feature/$feature_name"
echo "已创建并切换到 feature/$feature_name"
```

**验收标准**:
- [ ] 自动 sync 到最新 main
- [ ] 创建 feature/* 分支并从 worktree 分支派生
- [ ] feature 名称格式验证
- [ ] sync 失败时不创建 feature 分支

---

### Phase 2: 重构已有技能 (P1)

#### 2.1 sns-workflow:feature-implement 重构

**问题**: 当前实现可能与新的 sync + feature 流程不兼容

**修改内容**:
- 移除独立的 sync 逻辑（已由 sns-workflow:feature 处理）
- 移除独立的 commit 逻辑（已由 sns-workflow:commit-push-pr 处理）
- 聚焦于 feature 分支内的 TDD 实现循环

#### 2.2 sns-workflow:bug-fix 重构

**问题**: 当前实现可能与新的 hotfix 流程不兼容

**修改内容**:
- 与 sns-workflow:commit-push-pr 集成
- 移除独立的 PR 创建逻辑
- 聚焦于 hotfix 分支内的修复逻辑

---

### Phase 3: 发布工作流 (P2)

#### 3.1 sns-workflow:release

**目标**: 从 main 切出 release 分支

**关键逻辑**:
```bash
sns-workflow release v1.0.0
# git checkout -b release/v1.0.0 main
```

#### 3.2 sns-workflow:publish

**目标**: 发布到生产线 (product 分支)

**关键逻辑**:
```bash
sns-workflow publish v1.0.0
# git checkout main && git tag -a v1.0.0
# git checkout product && git merge main
# git push origin product --tags
```

---

## 三、依赖关系与执行顺序

```
Phase 1 (P0)                    Phase 2 (P1)              Phase 3 (P2)
┌──────────────────────┐
│  sns-workflow:sync   │────────┐
└──────────────────────┘        │
                                │     ┌──────────────────────┐
┌──────────────────────┐        ├────►│ feature-implement    │
│ sns-workflow:feature │────────┤     │    重构              │
└──────────────────────┘        │     └──────────────────────┘
                                │
┌────────────────────────────┐  │     ┌──────────────────────┐
│ sns-workflow:commit-push-pr│──┘     │    bug-fix           │
└────────────────────────────┘        │    重构              │
                                      └──────────────────────┘
                                                 │
                                                 ▼
                                      ┌──────────────────────┐
                                      │ sns-workflow:release │
                                      │ sns-workflow:publish │
                                      └──────────────────────┘
```

---

## 四、验收标准汇总

### Phase 1 完成标准
- [ ] 三种分支类型 (worktree/feature/hotfix) 的 commit-push-pr 流程完整测试通过
- [ ] sync 命令在 worktree 分支上可正常工作
- [ ] feature 命令可正确创建 feature 分支
- [ ] 快捷模式: 进入 worktree → [可选sync] → 开发 → commit-push-pr 端到端测试通过
- [ ] Feature 模式: 进入 worktree → feature → 开发 → commit-push-pr 端到端测试通过

### Phase 2 完成标准
- [ ] feature-implement 技能与新流程兼容
- [ ] bug-fix 技能与 hotfix 流程兼容

### Phase 3 完成标准
- [ ] release 和 publish 流程可正常工作
- [ ] product 分支和 tag 管理符合规范

---

## 五、风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| gh CLI 未安装或未认证 | 所有涉及 PR 的操作失败 | 在 commit-push-pr 入口检查 gh 可用性 |
| sync rebase 冲突 | 用户可能需要手动解决 | 提供清晰的错误提示和解决建议 |
| feature 名称冲突 | 分支已存在时 checkout 失败 | 创建前检查分支是否存在 |
| hotfix tag 冲突 | 重复 tag 导致失败 | 打 tag 前验证 tag 不存在 |
| merge 冲突 (hotfix product) | PR merge 失败 | 自动回退并提供手动合并指导 |

---

## 六、资源估算

| Phase | 技能 | 预计工时 | 复杂度 |
|-------|------|---------|--------|
| Phase 1 | sync | 2h | 低 |
| Phase 1 | commit-push-pr | 8h | 高 (三种分支类型) |
| Phase 1 | feature | 2h | 低 |
| Phase 2 | feature-implement 重构 | 4h | 中 |
| Phase 2 | bug-fix 重构 | 3h | 中 |
| Phase 3 | release | 2h | 低 |
| Phase 3 | publish | 2h | 低 |
| **合计** | | **23h** | |

---

## 七、实施建议

1. **先完成 Phase 1 的 commit-push-pr** — 这是整个工作流的核心枢纽
2. **端到端测试每个流程** — 使用真实的 worktree 环境测试三种模式
3. **文档同步更新** — 每个技能开发完成后更新规范文档中的实现状态
4. **渐进式发布** — 先在内部 worktree 测试，确认稳定后再推广
