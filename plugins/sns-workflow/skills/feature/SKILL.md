---
name: sns-workflow:feature
description: Feature 模式入口命令 —— 自动 sync 到最新 main 并创建 feature 分支。仅可在 worktree-NNN 分支上使用。
user-invocable: true
allowed-tools: Bash
---

# Feature 模式入口命令

在 worktree 上自动 sync（可选）并创建 feature 分支，进入 Feature 开发模式。

---

## 步骤 1: 验证工作分支

```bash
current_branch=$(git branch --show-current)
if [[ ! "$current_branch" =~ ^worktree- ]]; then
  echo "错误: feature 命令仅在 worktree 分支上使用 (当前: $current_branch)"
  exit 1
fi
```

---

## 步骤 2: 验证 feature 名称

```bash
# 从参数读取 feature 名称
feature_name="${1:-}"
if [[ -z "$feature_name" ]]; then
  echo "用法: sns-workflow feature <feature-name>"
  echo "示例: sns-workflow feature user-auth"
  exit 1
fi

# 验证名称格式: 只允许小写字母、数字、连字符
if [[ ! "$feature_name" =~ ^[a-z0-9-]+$ ]]; then
  echo "错误: feature 名称只允许小写字母、数字、连字符"
  exit 1
fi

# 检查分支是否已存在 (本地 + 远端)
if git rev-parse --verify "feature/$feature_name" &> /dev/null; then
  echo "错误: feature/$feature_name 本地分支已存在"
  exit 1
fi
if git ls-remote origin "refs/heads/feature/$feature_name" | grep -q .; then
  echo "错误: feature/$feature_name 远端分支已存在"
  exit 1
fi
```

---

## 步骤 3: 自动 Sync

```bash
echo "同步到最新 main..."
git fetch origin main
git rebase origin/main || {
  echo "错误: sync 失败 (rebase 冲突)，请先解决冲突"
  echo "可执行: git rebase --abort 放弃同步"
  exit 1
}
echo "同步完成"
```

---

## 步骤 4: 创建 feature 分支

```bash
git checkout -b "feature/$feature_name"
echo "已创建并切换到 feature/$feature_name"
echo ""
echo "接下来:"
echo "  1. 修改代码（开发阶段不手动 commit）"
echo "  2. 完成后执行: sns-workflow commit-push-pr"
```
