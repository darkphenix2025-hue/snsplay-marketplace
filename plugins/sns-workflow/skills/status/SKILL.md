---
name: sns-workflow:status
description: 项目状态报告 —— 显示当前项目版本、分支、worktree 状态和活动 release。
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
source .sns-workflow/scripts/context.sh 2>/dev/null || echo "警告: context.sh 不存在，跳过上下文信息"

echo ""
echo "=== 版本状态 ==="

all_tags=$(git tag -l --sort=-version:refname)
latest_tag=$(echo "$all_tags" | head -1)
tag_count=$(echo "$all_tags" | grep -c . 2>/dev/null || echo "0")

if [[ -z "$latest_tag" ]]; then
  echo "线上版本: 无 tag（未发布）"
else
  echo "线上版本: $latest_tag"
  echo "总版本数: $tag_count"

  echo ""
  echo "最近版本:"
  echo "$all_tags" | head -5 | while read tag; do
    tag_date=$(git log -1 --format="%ai" "$tag" 2>/dev/null || echo "未知")
    tag_msg=$(git tag -l --format="%(contents:subject)" "$tag" 2>/dev/null || echo "")
    echo "  $tag ($tag_date) $tag_msg"
  done
fi

if [[ -n "$latest_tag" ]]; then
  ahead=$(git rev-list --count "$latest_tag"..HEAD 2>/dev/null || echo "0")
  if [[ "$ahead" -gt 0 ]]; then
    echo ""
    echo "⬆ 领先 $latest_tag 共 $ahead 个提交（未发布）"
  else
    echo ""
    echo "已是最新 tagged 版本"
  fi
fi
```

---

## 步骤 3: 活动 Release 分支

```bash
echo ""
echo "=== 活动 Release ==="

release_branches=$(sns_active_release_branches 2>/dev/null)

if [[ -z "$release_branches" ]]; then
  echo "无活动 release 分支"
else
  echo "$release_branches" | while read rb; do
    rb_version=$(echo "$rb" | sed 's/^release\///')
    rb_date=$(git log -1 --format="%cr" "$rb" 2>/dev/null || echo "")
    rb_ahead=$(git rev-list --count "origin/main..$rb" 2>/dev/null || echo "0")
    echo "  $rb (候选: $rb_version, $rb_date, 领先 main $rb_ahead 提交)"
  done
fi
```

---

## 步骤 4: 工作目录状态

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

## 步骤 5: 分支状态

```bash
echo ""
echo "=== 分支状态 ==="

branch_type=$(sns_branch_type 2>/dev/null || echo "unknown")
echo "当前分支: $current_branch ($branch_type)"
echo ""

local_branches=$(git branch --format='%(refname:short)')
local_count=$(echo "$local_branches" | grep -c . || echo "0")
echo "本地分支: $local_count"

other_branches=$(echo "$local_branches" | grep -v "^main$")
if [[ -n "$other_branches" ]]; then
  echo "$other_branches" | while read branch; do
    marker=""
    [[ "$branch" == "$current_branch" ]] && marker=" ← 当前"
    branch_age=$(git log -1 --format="%cr" "$branch" 2>/dev/null || echo "")
    echo "  $branch ($branch_age)$marker"
  done
else
  echo "  (仅 main)"
fi

echo ""
remote_branches=$(git branch -r --format='%(refname:short)' 2>/dev/null | grep -v HEAD)
if [[ -n "$remote_branches" ]]; then
  remote_count=$(echo "$remote_branches" | grep -c . || echo "0")
  echo "远端分支: $remote_count"
  echo "$remote_branches" | grep -v "^origin/main$" | while read branch; do
    branch_age=$(git log -1 --format="%cr" "$branch" 2>/dev/null || echo "")
    echo "  $branch ($branch_age)"
  done
else
  echo "远端分支: 0 (仅 origin/main)"
fi
```

---

## 步骤 6: Worktree 状态

```bash
echo ""
echo "=== Worktree 状态 ==="

worktree_list=$(git worktree list --porcelain 2>/dev/null)

if [[ -z "$worktree_list" ]]; then
  echo "无活跃 worktree"
else
  # 解析 worktree 列表
  git worktree list 2>/dev/null | tail -n +1 | while IFS= read -r line; do
    wt_path=$(echo "$line" | awk '{print $1}')
    wt_branch=$(echo "$line" | awk '{print $2}')
    wt_hash=$(echo "$line" | awk '{print $3}')

    # 判断状态
    wt_status="unknown"
    if [[ "$wt_branch" == "[main]" ]]; then
      wt_status="main"
    elif [[ "$wt_branch" =~ ^\[worktree- ]]; then
      if cd "$wt_path" 2>/dev/null; then
        if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
          wt_status="dirty"
        elif [[ $(sns_ahead_count 2>/dev/null || echo "0") -gt 0 ]]; then
          wt_status="busy"
        elif [[ $(sns_behind_count 2>/dev/null || echo "0") -gt 0 ]]; then
          wt_status="behind"
        else
          wt_status="idle"
        fi
        cd - > /dev/null 2>&1
      fi
    elif [[ "$wt_branch" =~ ^\[feature/ ]]; then
      wt_status="feature"
    elif [[ "$wt_branch" =~ ^\[hotfix/ ]]; then
      wt_status="hotfix"
    elif [[ "$wt_branch" =~ ^\[release/ ]]; then
      wt_status="release"
    fi

    echo "  $wt_hash | $wt_branch | $wt_status | $wt_path"
  done
fi
```

---

## 步骤 7: 最近活动

```bash
echo ""
echo "=== 最近活动 ==="

echo "最近 5 个提交:"
git log --oneline --format="%h %C(auto)%d%Creset %s (%cr)" -20 | head -5

today_count=$(git log --since="00:00" --oneline 2>/dev/null | wc -l | tr -d ' ')
echo ""
echo "今日提交: $today_count"
```
