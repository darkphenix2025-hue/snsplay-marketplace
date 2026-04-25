---
name: sns-workflow:status
description: 项目状态报告 —— 显示当前项目版本、分支、worktree 和 CI 状态。
user-invocable: true
allowed-tools: Bash
---

# 项目状态报告

汇总展示当前仓库的版本、分支、worktree 和整体运行状态。

---

## 步骤 1: 基本信息

```bash
current_branch=$(git branch --show-current)
remote_url=$(git remote get-url origin 2>/dev/null || echo "无远端")
commit_count=$(git rev-list --count HEAD 2>/dev/null || echo "0")
latest_commit=$(git log --oneline -1)

echo "=== 基本信息 ==="
echo "仓库: $(basename "$(git rev-parse --show-toplevel)")"
echo "远端: $remote_url"
echo "提交数: $commit_count"
echo "最新提交: $latest_commit"
```

---

## 步骤 2: 版本状态

```bash
source .sns-workflow/scripts/version.sh 2>/dev/null || echo "警告: version.sh 不存在，跳过版本信息"

echo ""
echo "=== 版本状态 ==="

all_tags=$(git tag -l --sort=-version:refname)
latest_tag=$(echo "$all_tags" | head -1)
tag_count=$(echo "$all_tags" | grep -c . 2>/dev/null || echo "0")

if [[ -z "$latest_tag" ]]; then
  echo "当前版本: 无 tag（未发布）"
else
  echo "当前版本: $latest_tag"
  echo "总版本数: $tag_count"

  # 显示最近 5 个版本
  echo ""
  echo "最近版本:"
  echo "$all_tags" | head -5 | while read tag; do
    tag_date=$(git log -1 --format="%ai" "$tag" 2>/dev/null || echo "未知")
    tag_msg=$(git tag -l --format="%(contents:subject)" "$tag" 2>/dev/null || echo "")
    echo "  $tag ($tag_date) $tag_msg"
  done
fi

# 当前距最新版本的提交数
if [[ -n "$latest_tag" ]]; then
  ahead=$(git rev-list --count "$latest_tag"..HEAD 2>/dev/null || echo "0")
  if [[ "$ahead" -gt 0 ]]; then
    echo ""
    echo "⬆ 领先 $latest_tag 共 $ahead 个提交"
  else
    echo ""
    echo "已是最新 tagged 版本"
  fi
fi
```

---

## 步骤 3: 工作目录状态

```bash
echo ""
echo "=== 工作目录状态 ==="

if [[ -n $(git status --porcelain) ]]; then
  changed=$(git status --short | grep -c "^[MA?]" || true)
  untracked=$(git status --short | grep -c "^??" || true)
  echo "状态: 有未提交更改"
  echo "  已更改: $changed"
  echo "  未跟踪: $untracked"
else
  echo "状态: 干净"
fi
```

---

## 步骤 4: 分支状态

```bash
echo ""
echo "=== 分支状态 ==="

echo "当前分支: $current_branch"
echo ""

# 本地分支
local_branches=$(git branch --format='%(refname:short)')
local_count=$(echo "$local_branches" | grep -c . || echo "0")
echo "本地分支: $local_count"

# 列出活跃工作分支（不含 main）
echo "$local_branches" | grep -v "^main$" | while read branch; do
  marker=""
  [[ "$branch" == "$current_branch" ]] && marker=" ← 当前"
  branch_age=$(git log -1 --format="%cr" "$branch" 2>/dev/null || echo "")
  echo "  $branch ($branch_age)$marker"
done

# 远端分支
echo ""
remote_branches=$(git branch -r --format='%(refname:short)' 2>/dev/null | grep -v HEAD)
if [[ -n "$remote_branches" ]]; then
  remote_count=$(echo "$remote_branches" | grep -c . || echo "0")
  echo "远端分支: $remote_count"
  echo "$remote_branches" | grep -v "^origin/main$" | while read branch; do
    branch_age=$(git log -1 --format="%cr" "$branch" 2>/dev/null || echo "")
    echo "  $branch ($branch_age)"
  done
fi
```

---

## 步骤 5: Worktree 状态

```bash
echo ""
echo "=== Worktree 状态 ==="

worktree_list=$(git worktree list 2>/dev/null)

if [[ -z "$worktree_list" ]]; then
  echo "无活跃 worktree"
else
  worktree_count=$(echo "$worktree_list" | grep -c . || echo "0")
  echo "活跃 worktree: $worktree_count"
  echo ""

  while IFS= read -r line; do
    wt_path=$(echo "$line" | awk '{print $1}')
    wt_branch=$(echo "$line" | awk '{print $2}')
    wt_hash=$(echo "$line" | awk '{print $3}')

    # 检查工作目录状态
    wt_dirty=""
    if cd "$wt_path" 2>/dev/null && [[ -n $(git status --porcelain 2>/dev/null) ]]; then
      wt_dirty=" 📝 有未提交更改"
    fi
    cd - > /dev/null 2>&1

    echo "  $wt_hash | $wt_branch | $wt_path$wt_dirty"
  done <<< "$worktree_list"
fi
```

---

## 步骤 6: 最近活动

```bash
echo ""
echo "=== 最近活动 ==="

echo "最近 5 个提交:"
git log --oneline --format="%h %C(auto)%d%Creset %s (%cr)" -20 | head -5

# 统计今日提交数
today_count=$(git log --since="00:00" --oneline 2>/dev/null | wc -l | tr -d ' ')
echo ""
echo "今日提交: $today_count"
```
