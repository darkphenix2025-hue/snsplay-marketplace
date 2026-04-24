---
name: sns-workflow:sync
description: 分支同步命令 —— 将 worktree 分支 rebase 到最新 origin/main。仅可在 worktree-NNN 分支上使用。
user-invocable: true
allowed-tools: Bash
---

# 分支同步技能

将当前 worktree 分支同步到最新的 origin/main（fetch + rebase）。

---

## 步骤 1: 验证工作分支

```bash
current_branch=$(git branch --show-current)
if [[ ! "$current_branch" =~ ^worktree- ]]; then
  echo "错误: sync 仅在 worktree 分支上使用 (当前: $current_branch)"
  exit 1
fi
```

---

## 步骤 2: 检查脏状态

```bash
if [[ -n $(git status --porcelain) ]]; then
  echo "错误: 工作目录有未提交的更改，请先处理后再同步"
  git status --short
  exit 1
fi
```

---

## 步骤 3: Fetch + Rebase（含冲突处理）

```bash
git fetch origin main
echo "已 fetch origin/main，开始 rebase..."
if git rebase origin/main; then
  echo "同步完成。当前基于:"
  git log --oneline -3
else
  echo "同步冲突: rebase 遇到冲突"
  echo "选项:"
  echo "  1. 手动解决冲突后: git rebase --continue"
  echo "  2. 放弃同步:      git rebase --abort"
  exit 1
fi
```
