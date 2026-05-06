---
name: sns-workflow:merge-pr
description: PR 合并命令 —— 在 main 分支上检查所有待合并 PR，CI 状态检查 + flaky 测试自动重试，按顺序 squash 合并。worktree 分支只 reset 不删除，feature/hotfix 分支合并后清理。
user-invocable: true
allowed-tools: Bash
---

# PR 合并技能

在 main 分支上检查所有待合并 PR，按顺序 squash 合并。

**分支处理规则**:
- `worktree-*` 分支: 只合并不删除，合并后 reset 到 origin/main
- `feature/*` / `hotfix/*` 分支: 合并后删除远端和本地分支

**跨环境安全**: 当宿主机无法看到 Docker 中的 worktree 目录时，保留 worktree 分支不删除，待 Docker 环境中再次执行时完成 reset。

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
skipped=0
failed_list=""

for row in $(echo "$pr_list" | jq -c '.[]'); do
  pr_number=$(echo "$row" | jq -r '.number')
  pr_title=$(echo "$row" | jq -r '.title')
  pr_branch=$(echo "$row" | jq -r '.headRefName')

  echo "--- 合并 PR #$pr_number: $pr_title ---"

  # 重新验证 PR 状态（可能在此期间被手动合并/关闭）
  pr_state=$(gh pr view "$pr_number" --json state,isMergeable,mergeable,mergedAt 2>/dev/null | jq -r '.state')
  if [[ "$pr_state" != "OPEN" ]]; then
    echo "  跳过: PR 已关闭或已合并 (状态: $pr_state)"
    skipped=$((skipped + 1))
    echo ""
    continue
  fi

  # 检查可合并性
  is_mergeable=$(gh pr view "$pr_number" --json mergeable,state 2>/dev/null | jq -r '.mergeable // "UNKNOWN"')
  if [[ "$is_mergeable" == "CONFLICTING" ]]; then
    echo "  跳过: PR 存在合并冲突，请手动解决"
    failed=$((failed + 1))
    failed_list="$failed_list  #$pr_number $pr_title ($pr_branch) — 合并冲突\n"
    echo ""
    continue
  fi

  # 检查 CI 状态（PR 合并前置条件）
  ci_state=$(gh pr checks "$pr_number" --json state 2>/dev/null | jq -r '.[].state // empty' | sort | uniq -c | sort -rn | head -1)
  pending_count=$(gh pr checks "$pr_number" --json state 2>/dev/null | jq '[.[] | select(.state == "PENDING" or .state == "IN_PROGRESS" or .state == "WAITING")] | length')
  fail_count=$(gh pr checks "$pr_number" --json state 2>/dev/null | jq '[.[] | select(.state == "FAILURE" or .state == "ERROR")] | length')

  if [[ "$pending_count" -gt 0 ]] 2>/dev/null; then
    echo "  等待 CI 完成... ($pending_count 项仍在运行)"
    for attempt in 1 2 3 4 5; do
      sleep 5
      pending_count=$(gh pr checks "$pr_number" --json state 2>/dev/null | jq '[.[] | select(.state == "PENDING" or .state == "IN_PROGRESS" or .state == "WAITING")] | length')
      if [[ "$pending_count" -eq 0 ]] 2>/dev/null; then
        echo "  CI 完成"
        break
      fi
    done
  fi

  if [[ "$fail_count" -gt 0 ]] 2>/dev/null; then
    echo "  CI 失败 ($fail_count 项)，尝试 flaky 测试重试..."

    # 获取失败检查的名称，判断是否为 flaky（测试类）
    failing_checks=$(gh pr checks "$pr_number" --json name,state 2>/dev/null | jq -r '.[] | select(.state == "FAILURE" or .state == "ERROR") | .name')

    # 区分：CI 配置错误 vs flaky 测试
    # 配置错误（lint、build、type-check）不重试；仅对 test/ci 类重试
    should_retry=true
    for check in $failing_checks; do
      case "$check" in
        *lint*|*build*|*type*|*compile*) should_retry=false ;;
        *test*|*ci*|*e2e*) should_retry=true ;;
        *) should_retry=true ;;  # 未知类型默认尝试重试
      esac
      if ! $should_retry; then break; fi
    done

    if $should_retry; then
      retry_success=false
      for retry in 1 2 3; do
        echo "  重试第 $retry 次..."
        # 通过重新触发检查（关闭再打开 PR 的 check_suite）
        gh api repos/:owner/:repo/check-suites --request-method POST --input /dev/null 2>/dev/null || true
        gh pr checks "$pr_number" --reun "$retry" || true  # 触发 rerun 失败检查
        sleep 10
        fail_count=$(gh pr checks "$pr_number" --json state 2>/dev/null | jq '[.[] | select(.state == "FAILURE" or .state == "ERROR")] | length')
        if [[ "$fail_count" -eq 0 ]] 2>/dev/null; then
          echo "  重试成功 ($retry 次)"
          retry_success=true
          break
        fi
      done

      if ! $retry_success; then
        echo "  CI 重试失败，跳过 PR #$pr_number（3 次重试后仍失败）"
        failed=$((failed + 1))
        failed_list="$failed_list  #$pr_number $pr_title ($pr_branch) — CI 失败（重试 3 次）\n"
        echo ""
        continue
      fi
    else
      echo "  CI 失败为配置类错误（lint/build），不重试，跳过 PR #$pr_number"
      failed=$((failed + 1))
      failed_list="$failed_list  #$pr_number $pr_title ($pr_branch) — CI 配置错误\n"
      echo ""
      continue
    fi
  fi

  if [[ "$pr_branch" =~ ^worktree- ]]; then
    # worktree 分支: 只合并不删除，记录待 reset
    if gh pr merge "$pr_number" --squash --yes 2>&1; then
      echo "  已合并: #$pr_number ($pr_branch)"
      merged=$((merged + 1))
      worktree_branches="$worktree_branches $pr_branch"
    else
      echo "  合并失败: #$pr_number"
      failed=$((failed + 1))
      failed_list="$failed_list  #$pr_number $pr_title ($pr_branch)\n"
    fi
  else
    # feature/hotfix 等分支: 合并 + 删除远端分支
    # 不使用 --delete-branch，手动删远端（避免 worktree 占用导致本地删除失败）
    if gh pr merge "$pr_number" --squash --yes 2>&1; then
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

# 重置所有已合并的 worktree 分支到 origin/main
# 跨环境安全: 如果 worktree 目录在当前环境不可见，保留分支不删除
reset=""
for wt_branch in $worktree_branches; do
  reset_done=false

  # 尝试方式1: 从分支名派生目录路径 (worktree-worker-001 → .claude/worktrees/worker-001)
  if [[ "$wt_branch" =~ ^worktree-(.+)$ ]]; then
    derived_path=".claude/worktrees/${BASH_REMATCH[1]}"
    if [[ -d "$derived_path" ]]; then
      if git -C "$derived_path" diff --quiet 2>/dev/null && \
         git -C "$derived_path" diff --cached --quiet 2>/dev/null; then
        git -C "$derived_path" fetch origin main
        git -C "$derived_path" reset --hard origin/main
        reset="$reset  $wt_branch\n"
        reset_done=true
      else
        echo "  跳过 $wt_branch: 工作区有未提交更改 ($derived_path)"
        reset_done=true
      fi
    fi
  fi

  # 尝试方式2: 从 git worktree list 查找路径
  if ! $reset_done; then
    wt_path=$(git worktree list 2>/dev/null | grep "\\[$wt_branch\\]" | awk '{print $1}')
    if [[ -n "$wt_path" ]] && [[ -d "$wt_path" ]]; then
      if git -C "$wt_path" diff --quiet 2>/dev/null && \
         git -C "$wt_path" diff --cached --quiet 2>/dev/null; then
        git -C "$wt_path" fetch origin main
        git -C "$wt_path" reset --hard origin/main
        reset="$reset  $wt_branch\n"
        reset_done=true
      else
        echo "  跳过 $wt_branch: 工作区有未提交更改 ($wt_path)"
        reset_done=true
      fi
    fi
  fi

  # 尝试方式3: worktree 目录不可见（宿主机 vs Docker 跨环境），直接更新本地分支 ref
  if ! $reset_done; then
    if git show-ref --verify --quiet "refs/heads/$wt_branch"; then
      git update-ref "refs/heads/$wt_branch" origin/main
      reset="$reset  $wt_branch (ref only)\n"
    else
      echo "  跳过 $wt_branch: 分支不存在且目录不可见，等待 Docker 环境中 sync"
    fi
  fi
done

# 清理已合并的本地 feature/hotfix 分支（不清理 worktree 分支）
cleaned=""
for branch in $(git branch --merged main --format='%(refname:short)' | grep -E '^(feature/|hotfix/)'); do
  if [[ "$branch" == "$current_branch" ]]; then
    continue
  fi
  git branch -d "$branch" 2>/dev/null && {
    cleaned="$cleaned  $branch\n"
  }
done
```

---

## 步骤 5: 输出汇总

```bash
echo ""
echo "=== merge-pr 完成 ==="
echo "已合并: $merged 个 PR"
if [[ "$skipped" -gt 0 ]]; then
  echo "已跳过: $skipped 个 PR（已关闭/已合并）"
fi
if [[ "$failed" -gt 0 ]]; then
  echo "失败: $failed 个 PR:"
  echo -e "$failed_list"
fi
echo "当前分支: $(git branch --show-current)"
echo "最新提交: $(git log --oneline -1)"

if [[ -n "$reset" ]]; then
  echo ""
  echo "已重置 worktree 分支:"
  echo -e "$reset"
fi

if [[ -n "$cleaned" ]]; then
  echo ""
  echo "已清理本地分支:"
  echo -e "$cleaned"
fi
```
