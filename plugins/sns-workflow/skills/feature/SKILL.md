---
name: sns-workflow:feature
description: Feature 模式入口命令 —— 自动 sync 到最新 main 并创建 feature 分支。仅可在空闲 worktree-NNN 分支上使用。参数: <feature-name>。
user-invocable: true
allowed-tools: Bash
---

# Feature 模式入口命令

在空闲 worktree 上同步到最新 main 并创建 feature 分支，进入 Feature 开发模式。feature 完成后通过 `/sns-workflow:commit-push-pr` 提交。

**参数**: `<feature-name>` — 必填，feature 名称（如 `user-auth`、`payment`）。

---

## 步骤 1: 验证环境与上下文

```bash
source .sns-workflow/scripts/version.sh
source .sns-workflow/scripts/context.sh

current_branch=$(git branch --show-current)
branch_type=$(sns_branch_type)

# 必须在 worktree 分支上
if [[ "$branch_type" != "worktree" ]]; then
  echo "错误: feature 命令仅在 worktree 分支上使用 (当前: $current_branch, 类型: $branch_type)"
  exit 1
fi

# 工作区必须干净
if ! sns_workdir_clean; then
  echo "错误: 工作区有未提交的更改，请先处理"
  git status --short
  exit 1
fi
```

---

## 步骤 2: 验证 feature 名称

```bash
feature_name="${1:-}"
if [[ -z "$feature_name" ]]; then
  echo "用法: /sns-workflow:feature <feature-name>"
  echo "示例: /sns-workflow:feature user-auth"
  exit 1
fi

# 名称格式: 只允许小写字母、数字、连字符
if [[ ! "$feature_name" =~ ^[a-z0-9-]+$ ]]; then
  echo "错误: feature 名称只允许小写字母、数字、连字符 (如 user-auth)"
  exit 1
fi

target_branch="feature/$feature_name"
```

---

## 步骤 3: 校验无重名分支

```bash
if git show-ref --verify --quiet "refs/heads/$target_branch" 2>/dev/null; then
  echo "错误: 本地分支 $target_branch 已存在"
  exit 1
fi

if git ls-remote origin "refs/heads/$target_branch" 2>/dev/null | grep -q .; then
  echo "错误: 远端分支 $target_branch 已存在"
  exit 1
fi
```

---

## 步骤 4: 自动 Sync

```bash
echo "同步到最新 main..."
git fetch origin main

ahead=$(sns_ahead_count)
behind=$(sns_behind_count)

if [[ "$behind" -gt 0 ]]; then
  if [[ "$ahead" -eq 0 ]]; then
    git reset --hard origin/main
  else
    if ! git rebase origin/main; then
      echo "错误: sync 失败 (rebase 冲突)，请先解决冲突"
      echo "可执行: git rebase --abort 放弃同步"
      exit 1
    fi
  fi
  echo "同步完成"
else
  echo "已是最新"
fi
```

---

## 步骤 5: 创建 feature 分支

```bash
git checkout -b "$target_branch"

echo ""
echo "=== Feature 分支已创建 ==="
echo "所属 worktree: $current_branch"
echo "feature 分支: $target_branch"
echo "线上版本: $(sns_latest_tag)"
echo ""
echo "接下来:"
echo "  1. 修改代码（开发阶段不手动 commit）"
echo "  2. 完成后执行: /sns-workflow:commit-push-pr"
echo "  3. 系统将自动: PR 合并到 main → 删除 feature → 回到 $current_branch"
```
