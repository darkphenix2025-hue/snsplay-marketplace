---
name: sns-workflow:sync
description: 分支同步命令 —— 将 worktree 分支同步到最新 origin/main，智能判断 rebase 或 reset。仅可在 worktree-NNN 分支上使用。
user-invocable: true
allowed-tools: Bash
---

# 分支同步技能

将当前 worktree 分支同步到最新的 origin/main。根据 ahead/behind 状态智能选择 reset 或 rebase 策略。

**核心安全原则**: 绝不丢弃 worktree 上尚未合并到 main 的新 commit。

---

## 步骤 1: 验证环境与上下文

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/context.sh"
source "$SHELL_DIR/skill-logger.sh"
sns_skill_start "sync" "$*"

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
  # 有本地提交且落后 — 需要智能处理
  # 用 git cherry 识别哪些 commit 是"幽灵 commit"（内容已在 main 中但 hash 不同）
  # git cherry 输出: + 表示新 commit，- 表示等价于 main 中已有 commit（幽灵 commit）

  cherry_output=$(git cherry origin/main HEAD)
  ghost_count=$(echo "$cherry_output" | grep -c "^-" || echo "0")
  real_new_count=$(echo "$cherry_output" | grep -c "^+" || echo "0")

  echo "提交分析:"
  echo "  幽灵 commit（内容已在 main 中）: $ghost_count 个"
  echo "  真正的新 commit: $real_new_count 个"

  if [[ "$real_new_count" -eq 0 ]]; then
    # 所有领先 commit 都是幽灵 commit，直接 reset
    echo "所有领先 commit 均为幽灵 commit（已被 squash merge 到 main），直接 reset..."
    git reset --hard origin/main
    # force push 清理远程分支上的幽灵 commit
    git push --force origin "$current_branch" 2>/dev/null || \
      echo "  警告: force push 失败（可能无远程追踪或权限不足）"
    echo "同步完成 (reset + force push，清理了 $ghost_count 个幽灵 commit)"
  elif [[ "$ghost_count" -eq 0 ]]; then
    # 没有幽灵 commit，都是真正的新 commit，安全 rebase
    echo "有 $real_new_count 个新 commit 且无幽灵 commit，执行 rebase..."
    if git rebase origin/main; then
      echo "同步完成 (rebase)"
    else
      echo ""
      echo "同步冲突: rebase 遇到冲突，无法自动合并"
      # 安全网: abort rebase，保护所有 commit
      git rebase --abort
      echo ""
      echo "选项:"
      echo "  1. 手动解决冲突后: git rebase origin/main"
      echo "  2. 强制同步到 main: 将丢失 $real_new_count 个新 commit（请先确认这些 commit 已有备份）"
      exit 1
    fi
  else
    # 混合情况: 有幽灵 commit + 有新 commit
    # 安全策略: reset 到 main + cherry-pick 真正的新 commit
    echo "混合情况（$ghost_count 个幽灵 + $real_new_count 个新 commit），执行 reset + cherry-pick..."

    # 提取真正新 commit 的 hash（git cherry 输出中 + 开头的行）
    new_commits=$(echo "$cherry_output" | grep "^+" | sed 's/^+ //' )

    # 安全网: 保存新 commit hash 以防 cherry-pick 失败
    backup_file=".snsplay/task/sync-backup-commits-$(date +%s).txt"
    mkdir -p .snsplay/task
    echo "$new_commits" > "$backup_file"
    echo "  安全备份: $backup_file（包含 $real_new_count 个新 commit hash）"

    # reset 到 main
    git reset --hard origin/main

    # 逐个 cherry-pick 真正的新 commit
    pick_failed=0
    picked_count=0
    for commit_hash in $new_commits; do
      if git cherry-pick "$commit_hash" 2>&1; then
        picked_count=$((picked_count + 1))
      else
        echo "  cherry-pick 失败: $commit_hash"
        git cherry-pick --abort 2>/dev/null
        pick_failed=$((pick_failed + 1))
      fi
    done

    # force push 清理远程分支
    git push --force origin "$current_branch" 2>/dev/null || \
      echo "  警告: force push 失败"

    if [[ "$pick_failed" -eq 0 ]]; then
      echo "同步完成 (reset + cherry-pick $picked_count 个新 commit + 清理 $ghost_count 个幽灵 commit)"
    else
      echo "同步完成 (部分成功: cherry-pick $picked_count/$real_new_count 个新 commit)"
      echo "  失败的 commit hash 保存在: $backup_file"
      echo "  可手动 cherry-pick: git cherry-pick <hash>"
    fi
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

# 验证同步后状态
final_ahead=$(sns_ahead_count)
final_behind=$(sns_behind_count)
echo "领先 origin/main: $final_ahead 个提交"
echo "落后 origin/main: $final_behind 个提交"

sns_skill_end "success"
```
