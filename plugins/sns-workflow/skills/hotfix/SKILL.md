---
name: sns-workflow:hotfix
description: Hotfix 模式入口命令 —— 从线上正式 Tag 派生 hotfix 分支进行紧急修复。仅可在空闲 worktree 分支上使用。支持可选参数指定目标版本号。
user-invocable: true
allowed-tools: Bash
---

# Hotfix 模式入口命令

从线上正式 Tag 派生 hotfix 分支进行紧急修复。hotfix 完成后通过 `/sns-workflow:commit-push-pr` 发布，系统将自动打新 Tag 并回流 main。

**参数**: `[目标版本]` — 可选，指定 hotfix 目标版本（如 `v1.6.1`）。省略时自动从最新 tag 计算 patch+1。

---

## 步骤 1: 验证环境与上下文

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/shell"
source "$SHELL_DIR/version.sh"
source "$SHELL_DIR/context.sh"

current_branch=$(git branch --show-current)
branch_type=$(sns_branch_type)

# 必须在 worktree 分支上
if [[ "$branch_type" != "worktree" ]]; then
  echo "错误: hotfix 命令仅在 worktree 分支上使用 (当前: $current_branch, 类型: $branch_type)"
  echo "请先切换到空闲的 worktree 分支"
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

## 步骤 2: 确定基线 Tag

```bash
latest_tag=$(sns_latest_tag)

if [[ -z "$latest_tag" ]]; then
  echo "错误: 无线上 tag，无法派生 hotfix"
  echo "hotfix 必须从正式 Tag 创建"
  exit 1
fi

echo "线上版本: $latest_tag"
```

---

## 步骤 3: 计算并校验目标版本

```bash
target_version="${1:-}"

if [[ -z "$target_version" ]]; then
  # 自动计算: 最新 tag patch+1
  target_version=$(sns_bump_version "$latest_tag" patch)
  if [[ -z "$target_version" ]]; then
    echo "错误: 无法从 $latest_tag 计算目标版本"
    exit 1
  fi
  echo "自动计算目标版本: $target_version (从 $latest_tag patch+1)"
else
  # 校验格式
  if ! sns_validate_version "$target_version"; then
    echo "错误: 版本号格式必须为 v<major>.<minor>.<patch> (如 v1.6.1)"
    exit 1
  fi

  # 校验目标版本 > 线上版本
  if ! sns_version_gt "$target_version" "$latest_tag"; then
    echo "错误: 目标版本 $target_version 必须大于线上版本 $latest_tag"
    echo "hotfix 目标版本必须严格递增"
    exit 1
  fi

  echo "指定目标版本: $target_version"
fi

# 校验目标 tag 尚不存在
if sns_tag_exists "$target_version"; then
  echo "错误: tag $target_version 已存在"
  echo "hotfix 目标版本必须是一个新版本"
  exit 1
fi

# 分支名: hotfix/x.y.z (去掉 v 前缀)
branch_version=$(echo "$target_version" | sed 's/^v//')
hotfix_branch="hotfix/$branch_version"
```

---

## 步骤 4: 校验无重名分支

```bash
if git show-ref --verify --quiet "refs/heads/$hotfix_branch" 2>/dev/null; then
  echo "错误: 本地分支 $hotfix_branch 已存在"
  echo "如需重新开始，请先删除旧分支: git branch -D $hotfix_branch"
  exit 1
fi

if git show-ref --verify --quiet "refs/remotes/origin/$hotfix_branch" 2>/dev/null; then
  echo "错误: 远端分支 $hotfix_branch 已存在"
  exit 1
fi
```

---

## 步骤 5: 自动 Sync

```bash
echo "同步 worktree 到最新 main..."
git fetch origin main

ahead=$(sns_ahead_count)
behind=$(sns_behind_count)

if [[ "$behind" -gt 0 ]]; then
  if [[ "$ahead" -gt 0 ]]; then
    echo "当前分支有 $ahead 个未合并提交且落后 origin/main $behind 个提交"
    echo "尝试 rebase..."
    if ! git rebase origin/main; then
      echo "错误: rebase 失败 (冲突)，请先解决冲突"
      echo "可执行: git rebase --abort 放弃"
      exit 1
    fi
  else
    git reset --hard origin/main
  fi
  echo "同步完成"
else
  echo "已是最新"
fi
```

---

## 步骤 6: 从 Tag 创建 hotfix 分支

```bash
echo "从 $latest_tag 创建 $hotfix_branch..."
git checkout -b "$hotfix_branch" "$latest_tag"

echo ""
echo "=== Hotfix 分支已创建 ==="
echo "基线 Tag: $latest_tag"
echo "目标版本: $target_version"
echo "当前分支: $hotfix_branch"
echo ""
echo "接下来:"
echo "  1. 修复代码（开发阶段不手动 commit）"
echo "  2. 完成后执行: /sns-workflow:commit-push-pr"
echo "  3. 系统将自动: 打 tag $target_version → 回流 main"
echo "     如有活动 release/*，也会同步修复"
```
