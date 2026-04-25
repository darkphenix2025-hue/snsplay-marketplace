---
name: sns-workflow:sync
description: 分支同步命令 —— 将 worktree 分支同步到最新 origin/main，智能判断 rebase 或 reset。仅可在 worktree-NNN 分支上使用。
user-invocable: true
allowed-tools: Bash
---

# 分支同步技能

将当前 worktree 分支同步到最新的 origin/main。根据 ahead/behind 状态智能选择 reset 或 rebase 策略。

---

## 步骤 1: 验证环境与上下文

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/context.sh"

current_branch=$(git branch --show-current)
branch_type=$(sns_branch_type)

if [[ "$branch_type" != "worktree" ]]; then
  echo "错误: sync 仅在 worktree 分支上使用 (当前: $current_branch, 类型: $branch_type)"
  exit 1
fi
```

---

## 步骤 2: 检查工作区状态

```bash
if ! sns_workdir_clean; then
  echo "错误: 工作目录有未提交的更改，请先处理后再同步"
  git status --short
  exit 1
fi
```

---

## 步骤 3: Fetch 并检测 ahead/behind

```bash
git fetch origin main

ahead=$(sns_ahead_count)
behind=$(sns_behind_count)

echo "=== 同步状态 ==="
echo "当前分支: $current_branch"
echo "领先 origin/main: $ahead 个提交"
echo "落后 origin/main: $behind 个提交"
```

---

## 步骤 4: 执行同步

```bash
if [[ "$behind" -eq 0 ]]; then
  echo "已是最新，无需同步"
elif [[ "$ahead" -eq 0 ]]; then
  # 无本地提交，直接 fast-forward
  echo "无本地提交，fast-forward 到 origin/main..."
  git reset --hard origin/main
  echo "同步完成 (fast-forward)"
else
  # 有本地提交且落后，需要 rebase
  echo "有 $ahead 个本地提交且落后 $behind 个提交，执行 rebase..."
  if git rebase origin/main; then
    echo "同步完成 (rebase)"
  else
    echo ""
    echo "同步冲突: rebase 遇到冲突，无法自动合并"
    echo ""
    echo "选项:"
    echo "  1. 手动解决冲突后: git rebase --continue"
    echo "  2. 放弃同步:      git rebase --abort"
    exit 1
  fi
fi
```

---

## 步骤 5: 同步结果

```bash
echo ""
echo "=== 同步结果 ==="
echo "当前分支: $(git branch --show-current)"
echo "最新 3 个提交:"
git log --oneline -3
```
