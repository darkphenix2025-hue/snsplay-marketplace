---
name: sns-workflow:merge-pr
description: PR 合并命令 —— 在 main 分支上检查所有待合并 PR，按顺序 squash 合并，关闭对应分支。
user-invocable: true
allowed-tools: Bash
---

# PR 合并技能

在 main 分支上检查所有待合并 PR，按顺序 squash 合并，合并后关闭对应的远端和本地分支。

---

## 步骤 1: 验证环境与上下文

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/version.sh"
source "$SHELL_DIR/context.sh"

current_branch=$(git branch --show-current)
branch_type=$(sns_branch_type)

if [[ "$branch_type" != "main" ]]; then
  echo "错误: merge-pr 仅在 main 分支上执行 (当前: $current_branch, 类型: $branch_type)"
  echo "请先切换到 main: git checkout main"
  exit 1
fi

if ! command -v gh &> /dev/null; then
  echo "错误: gh CLI 未安装"
  exit 1
fi
gh auth status 2>&1 >/dev/null || { echo "错误: gh 未认证，请先执行 gh auth login"; exit 1; }
```

---

## 步骤 2: 获取待合并 PR 列表

```bash
pr_list=$(gh pr list --base main --state open --json number,title,headRefName 2>&1)

if echo "$pr_list" | grep -q "^\[]$"; then
  echo "没有待合并的 PR"
  exit 0
fi

pr_count=$(echo "$pr_list" | jq 'length')

if [[ "$pr_count" -eq 0 ]]; then
  echo "没有待合并的 PR"
  exit 0
fi

echo "=== 待合并 PR ($pr_count 个) ==="
echo "$pr_list" | jq -r '.[] | "  #\(.number) \(.title) (\(.headRefName))"'
echo ""
```

---

## 步骤 3: 逐个合并 PR

```bash
merged=0
failed=0
failed_list=""
worktree_branches=""

for row in $(echo "$pr_list" | jq -c '.[]'); do
  pr_number=$(echo "$row" | jq -r '.number')
  pr_title=$(echo "$row" | jq -r '.title')
  pr_branch=$(echo "$row" | jq -r '.headRefName')

  echo "--- 合并 PR #$pr_number: $pr_title ---"

  # worktree 分支: 只合并不删分支，后续 reset
  if [[ "$pr_branch" =~ ^worktree- ]]; then
    if gh pr merge "$pr_number" --squash 2>&1; then
      echo "  已合并: #$pr_number ($pr_branch)"
      merged=$((merged + 1))
      worktree_branches="$worktree_branches $pr_branch"
    else
      echo "  合并失败: #$pr_number"
      failed=$((failed + 1))
      failed_list="$failed_list  #$pr_number $pr_title ($pr_branch)\n"
    fi
  else
    # feature/hotfix 等分支: 合并，手动删远端分支（避免 --delete-branch 因 worktree 占用而失败）
    if gh pr merge "$pr_number" --squash 2>&1; then
      git push origin --delete "$pr_branch" 2>/dev/null || true
      echo "  已合并: #$pr_number ($pr_branch)"
      merged=$((merged + 1))
    else
      echo "  合并失败: #$pr_number"
      failed=$((failed + 1))
      failed_list="$failed_list  #$pr_number $pr_title ($pr_branch)\n"
    fi
  fi
  echo ""
done
```

---

## 步骤 4: 同步本地 main 并清理分支

```bash
git pull origin main

# 清理已合并的本地 feature/hotfix 分支
cleaned=""
for branch in $(git branch --merged main --format='%(refname:short)' | grep -E '^(feature/|hotfix/)'); do
  if [[ "$branch" == "$current_branch" ]]; then
    continue
  fi

  # 检查该分支是否被 worktree 占用
  wt_line=$(git worktree list 2>/dev/null | grep "\\[$branch\\]")
  if [[ -n "$wt_line" ]]; then
    wt_path=$(echo "$wt_line" | awk '{print $1}')
    if [[ -n "$wt_path" ]]; then
      dir_name=$(basename "$wt_path")
      wt_num=$(echo "$dir_name" | grep -oP '[0-9]+')
      if [[ -n "$wt_num" ]]; then
        wt_branch="worktree-$wt_num"
        git -C "$wt_path" fetch origin main
        git -C "$wt_path" checkout -B "$wt_branch" origin/main 2>/dev/null
      fi
    fi
  fi

  git branch -d "$branch" 2>/dev/null && {
    cleaned="$cleaned  $branch\n"
  }
done

# Reset worktree 分支到最新 main（保留分支，不删除）
reset=""
for wt_branch in $worktree_branches; do
  # 查找 worktree 对应的工作目录
  wt_path=$(git worktree list --format='%(worktree) %(refname:short)' 2>/dev/null | awk -v b="$wt_branch" '$2 == b {print $1}')
  if [[ -n "$wt_path" ]]; then
    # 在 worktree 目录中执行 reset
    if git -C "$wt_path" diff --quiet 2>/dev/null && \
       git -C "$wt_path" diff --cached --quiet 2>/dev/null; then
      git -C "$wt_path" fetch origin main
      git -C "$wt_path" reset --hard origin/main
      reset="$reset  $wt_branch\n"
    else
      echo "  跳过 $wt_branch: 工作区有未提交更改"
    fi
  else
    # 本地分支存在但无 worktree 目录，直接 reset 本地分支
    if git show-ref --verify --quiet "refs/heads/$wt_branch"; then
      git update-ref "refs/heads/$wt_branch" origin/main
      reset="$reset  $wt_branch (ref updated)\n"
    fi
  fi
done
```

---

## 步骤 5: 输出汇总

```bash
echo ""
echo "=== merge-pr 完成 ==="
echo "已合并: $merged 个 PR"
if [[ "$failed" -gt 0 ]]; then
  echo "失败: $failed 个 PR:"
  echo -e "$failed_list"
fi
echo "当前分支: $(git branch --show-current)"
echo "最新提交: $(git log --oneline -1)"

if [[ -n "$cleaned" ]]; then
  echo ""
  echo "已清理本地分支:"
  echo -e "$cleaned"
fi

if [[ -n "$reset" ]]; then
  echo ""
  echo "已重置 worktree 分支:"
  echo -e "$reset"
fi
```
