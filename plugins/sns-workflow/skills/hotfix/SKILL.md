---
name: sns-workflow:hotfix
description: Hotfix 模式入口命令 —— 自动 sync + 从 tag 创建 hotfix 分支。仅可在 worktree-NNN 分支上使用。
user-invocable: true
allowed-tools: Bash
---

# Hotfix 模式入口命令

从 tag 创建 hotfix 分支并进入修复流程。

---

## 步骤 1: 验证工作分支

```bash
current_branch=$(git branch --show-current)
if [[ ! "$current_branch" =~ ^worktree- ]]; then
  echo "错误: hotfix 命令仅在 worktree 分支上使用 (当前: $current_branch)"
  exit 1
fi
```

---

## 步骤 2: 版本参数处理

```bash
source .sns-workflow/scripts/version.sh

version="${1:-}"
if [[ -z "$version" ]]; then
  latest_tag=$(sns_latest_tag)
  version=$(sns_bump_version "$latest_tag" patch)
  echo "自动计算版本号: $latest_tag → $version"
fi

if ! sns_validate_version "$version"; then
  echo "错误: 版本号格式必须为 v<major>.<minor>.<patch>"
  exit 1
fi
```

---

## 步骤 3: 验证 tag 存在

```bash
base_tag=$(git tag -l "$version" 2>/dev/null)
if [[ -z "$base_tag" ]]; then
  echo "错误: tag $version 不存在"
  echo "用法: sns-workflow hotfix <existing-tag>"
  echo "可用 tags:"
  git tag -l | head -10
  exit 1
fi
```

---

## 步骤 4: 自动 Sync

```bash
echo "同步到最新 main..."
git fetch origin main
if git rebase origin/main; then
  echo "同步完成"
else
  echo "错误: sync 失败 (rebase 冲突)，请先解决冲突"
  echo "可执行: git rebase --abort 放弃同步"
  exit 1
fi
```

---

## 步骤 5: 创建 hotfix 分支

```bash
git checkout -b "hotfix/$version" "$base_tag"
echo "已创建并切换到 hotfix/$version"
echo ""
echo "接下来:"
echo "  1. 修复代码（开发阶段不手动 commit）"
echo "  2. 完成后执行: sns-workflow commit-push-pr"
```
