---
name: sns-workflow:commit-push-pr
description: 统一提交+推送+PR+合并+清理 —— 自动检测分支类型，执行对应的完整流程。main 直接提交，release 自动打预发布 tag，worktree/feature/hotfix 走 PR 流程。支持 --rc 参数切换 beta→rc 阶段，--backflow 参数回流 main。
user-invocable: true
allowed-tools: Bash
---

# 统一提交+推送+PR+合并+清理

自动检测当前分支类型，执行对应的 commit → push → PR → merge → 清理流程。

**五路路由矩阵**:

| 分支类型 | 动作 | 版本效果 |
|---------|------|---------|
| `main` | commit + push（直接提交） | 不产生 tag |
| `release/x.y.z` | commit + push + 自动打预发布 tag | 生成 `vX.Y.Z-beta` → `beta.2` → ... → `rc.1` → ... |
| `worktree-NNN` | commit → PR → merge → reset | 不产生 tag |
| `feature/*` | commit → PR → merge → 删除分支 → 回 worktree | 不产生 tag |
| `hotfix/x.y.z` | commit → PR → merge → 打 tag → 回流 | 生成正式 tag vX.Y.Z |

**`--rc` 参数**: 在 release 分支上使用时，将 beta 阶段切换到 rc 阶段（如 `v1.5.0-beta.3` → `v1.5.0-rc.1`）。

**`--backflow` 参数**: 在 release 分支上使用时，提交后将 release 合并回 main 并切到 main，保留 release 分支。不产生预发布 tag。

**不支持 unknown 分支**。

---

## 步骤 1: 检测环境与上下文

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/version.sh"
source "$SHELL_DIR/context.sh"

current_branch=$(git branch --show-current)
branch_type=$(sns_branch_type)

# 解析 --rc / --backflow 参数（仅 release 路径生效）
SHIFT_TO_RC=false
BACKFLOW=false
for arg in "$@"; do
  [[ "$arg" == "--rc" ]] && SHIFT_TO_RC=true
  [[ "$arg" == "--backflow" ]] && BACKFLOW=true
done

echo "当前分支: $current_branch (类型: $branch_type)"

# main 分支: 仅 commit + push，不走 PR/tag
# worktree / feature / hotfix: 完整 PR 流程

# 不支持 unknown 分支
if [[ "$branch_type" == "unknown" ]]; then
  echo "错误: 不支持的分支类型: $current_branch"
  echo "支持的分支: main, release/*, worktree-NNN, feature/*, hotfix/*"
  exit 1
fi

# 检查 gh CLI（main/release 路径不需要 PR，跳过检查）
if [[ "$branch_type" != "main" ]] && [[ "$branch_type" != "release" ]]; then
  if ! command -v gh &> /dev/null; then
    echo "错误: gh CLI 未安装"
    exit 1
  fi
  gh auth status 2>&1 >/dev/null || { echo "错误: gh 未认证，请先执行 gh auth login"; exit 1; }
fi
```

---

## 步骤 2: 自动 Commit

```bash
git add -A
HAS_CHANGES=true
if [[ -z $(git diff --cached --stat) ]]; then
  HAS_CHANGES=false
  # 仅 release + --rc 允许无变更打 tag（阶段推进 beta → rc）
  # 其他路径无变更则退出
  if [[ "$branch_type" == "release" ]] && $SHIFT_TO_RC; then
    echo "无代码变更，跳过 commit（仅阶段推进 beta → rc）"
  else
    echo "没有需要提交的更改"
    exit 0
  fi
fi

if $HAS_CHANGES; then
  # 根据分支类型生成 commit message
  case "$branch_type" in
    main)
      commit_msg="chore: update"
      ;;
    release)
      rel_version=$(echo "$current_branch" | sed 's/^release\///')
      commit_msg="fix($rel_version): rc update"
      ;;
    worktree)
      commit_msg="chore: $current_branch update"
      ;;
    feature)
      feat_name=$(echo "$current_branch" | sed 's/^feature\///')
      commit_msg="feat($feat_name): update"
      ;;
    hotfix)
      hf_version=$(echo "$current_branch" | sed 's/^hotfix\///')
      commit_msg="hotfix($hf_version): fix"
      ;;
  esac

  git commit -m "$commit_msg"
  echo "已提交: $commit_msg"
fi
```

---

## 步骤 3: Push

```bash
if $HAS_CHANGES; then
  git push -u origin "$current_branch" 2>&1 || {
    echo "Push 失败，请检查远端权限"
    exit 1
  }
  echo "已推送到远端: $current_branch"
fi
```

---

## 步骤 4: 根据分支类型执行 PR + Merge + 清理

```bash
case "$branch_type" in

  main)
    echo ""
    echo "=== main 路径: 直接提交，无需 PR ==="

    # main 已在步骤 2 commit，步骤 3 push，此处无需额外操作
    echo "已直接推送到 main"
    ;;

  release)
    if $BACKFLOW; then
      echo ""
      echo "=== release 路径: commit + 回流 main ==="

      # 回流 main：合并 release 到 main，切到 main，保留 release 分支
      git checkout main
      git pull origin main
      git merge "$current_branch" --no-edit
      git push origin main

      echo "已回流 main"
      echo "release 分支 $current_branch 已保留"
      echo ""
      echo "后续操作:"
      echo "  git checkout $current_branch        → 回到 release 继续"
      echo "  /sns-workflow:publish               → 正式发布（在 release 分支上执行）"
    else
      echo ""
      echo "=== release 路径: commit + 预发布 tag ==="

      # 从分支名提取正式版本号: release/1.5.0 → v1.5.0
      rel_version=$(echo "$current_branch" | sed 's/^release\///')
      base_tag="v$rel_version"

      # 校验分支名版本号是正式格式（不含 beta/rc）
      if sns_is_prerelease "$base_tag"; then
        echo "错误: release 分支名不应包含预发布后缀: $rel_version"
        echo "期望格式: release/x.y.z (如 release/1.5.0)"
        exit 1
      fi

      # 计算下一个预发布 tag
      if $SHIFT_TO_RC; then
        next_tag=$(sns_bump_prerelease "$base_tag" --rc) || {
          echo "错误: $next_tag"
          exit 1
        }
      else
        next_tag=$(sns_bump_prerelease "$base_tag")
      fi

      # 校验 tag 不重复
      if sns_tag_exists "$next_tag"; then
        echo "错误: tag $next_tag 已存在"
        exit 1
      fi

      # 打预发布 tag 并推送
      git tag -a "$next_tag" -m "Prerelease $next_tag"
      git push origin "$next_tag"
      echo "已创建预发布 tag: $next_tag"

      # 提示当前阶段和后续操作
      pre=$(sns_parse_version "$next_tag" prerelease)
      if [[ "$pre" =~ ^beta ]]; then
        echo "当前阶段: beta 测试"
        echo ""
        echo "后续操作:"
        echo "  /sns-workflow:commit-push-pr       → 下一个 beta 版本"
        echo "  /sns-workflow:commit-push-pr --rc   → 进入 rc 候选阶段"
        echo "  /sns-workflow:commit-push-pr --backflow → 回流 main"
      elif [[ "$pre" =~ ^rc ]]; then
        echo "当前阶段: rc 候选"
        echo ""
        echo "后续操作:"
        echo "  /sns-workflow:commit-push-pr       → 下一个 rc 版本"
        echo "  /sns-workflow:publish              → 正式发布 $base_tag"
        echo "  /sns-workflow:commit-push-pr --backflow → 回流 main"
      fi
    fi
    ;;

  worktree)
    echo ""
    echo "=== worktree 路径: PR → main → reset ==="

    pr_url=$(gh pr create --base main --head "$current_branch" \
      --title "chore: $current_branch → main" \
      --body "Auto-generated PR from worktree branch $current_branch" 2>&1) || {
      echo "PR 创建失败: $pr_url"
      exit 1
    }
    echo "PR 已创建: $pr_url"

    gh pr merge --squash 2>&1 || {
      echo "PR 合并失败"
      exit 1
    }
    echo "合并完成"

    # 安全校验: reset 前必须确认工作区干净
    git fetch origin main
    if ! sns_workdir_clean; then
      echo "警告: 合并后工作区不干净，跳过自动 reset"
      echo "请手动处理: git stash && git reset --hard origin/main && git stash pop"
    else
      git reset --hard origin/main
      echo "worktree 已 reset 到最新 main"
    fi
    ;;

  feature)
    echo ""
    echo "=== feature 路径: PR → main → 删除分支 → 回 worktree ==="

    # 确定所属 worktree（通过 git worktree list 查找）
    owning_worktree=""
    while IFS= read -r wt_line; do
      wt_path=$(echo "$wt_line" | awk '{print $1}')
      wt_branch=$(echo "$wt_line" | awk '{print $2}' | tr -d '[]')
      if [[ "$wt_branch" == "$current_branch" ]]; then
        # feature 分支所在的 worktree 路径
        owning_worktree=$(basename "$wt_path")
        break
      fi
    done < <(git worktree list 2>/dev/null | tail -n +1)

    # 备选方案: 从目录路径提取 worktree 编号
    if [[ -z "$owning_worktree" ]]; then
      wt_num=$(pwd | grep -oP 'worktree-\K\d+')
      if [[ -n "$wt_num" ]]; then
        owning_worktree="worktree-$wt_num"
      fi
    fi

    feat_name=$(echo "$current_branch" | sed 's/^feature\///')

    pr_url=$(gh pr create --base main --head "$current_branch" \
      --title "feat: $feat_name" \
      --body "Feature branch PR from $current_branch" 2>&1) || {
      echo "PR 创建失败: $pr_url"
      exit 1
    }
    echo "PR 已创建: $pr_url"

    gh pr merge --squash --delete-branch 2>&1 || {
      echo "PR 合并失败"
      exit 1
    }
    echo "合并完成"

    # 回到所属 worktree
    if [[ -n "$owning_worktree" ]]; then
      git checkout "$owning_worktree" 2>/dev/null || echo "警告: 无法切回 $owning_worktree，请手动切换"

      # 同步 worktree 到最新 main
      git fetch origin main
      if sns_workdir_clean; then
        git reset --hard origin/main
        echo "$owning_worktree 已同步到最新 main"
      else
        echo "警告: $owning_worktree 工作区不干净，跳过自动 reset"
      fi
    else
      echo "警告: 无法确定所属 worktree，请手动切回"
    fi

    echo "feature 分支 $current_branch 已合并并清理"
    ;;

  hotfix)
    echo ""
    echo "=== hotfix 路径: PR → main → 打 tag → 回流 ==="

    # 从分支名提取版本号 (hotfix/1.6.1 → v1.6.1)
    branch_version=$(echo "$current_branch" | sed 's/^hotfix\///')
    target_tag="v$branch_version"

    # 校验版本号格式
    if ! sns_validate_version "$target_tag"; then
      echo "错误: hotfix 分支名版本号格式不正确: $branch_version"
      echo "期望格式: hotfix/x.y.z (如 hotfix/1.6.1)"
      exit 1
    fi

    pr_url=$(gh pr create --base main --head "$current_branch" \
      --title "hotfix: $target_tag" \
      --body "Hotfix PR for version $target_tag" 2>&1) || {
      echo "PR 创建失败: $pr_url"
      exit 1
    }
    echo "PR 已创建: $pr_url"

    # 提取 PR 编号
    pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')
    repo_name=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null)

    # 合并 PR（优先用 --admin 绕过 worktree checkout 限制）
    if ! gh pr merge "$pr_number" --squash --delete-branch 2>&1; then
      echo "常规合并失败（可能因 worktree 限制），尝试 API 合并..."
      if ! gh api "repos/$repo_name/pulls/$pr_number/merge" -X PUT \
        -f merge_method=squash 2>&1; then
        echo "PR 合并失败"
        exit 1
      fi
      echo "API 合并成功"
      # 手动删除远端分支
      gh api "repos/$repo_name/git/refs/heads/$current_branch" -X DELETE 2>/dev/null || true
    fi
    echo "合并完成"

    # 获取合并后的最新 main
    git fetch origin main

    # 打 tag（基于 origin/main，不切换分支）
    if sns_tag_exists "$target_tag"; then
      echo "警告: tag $target_tag 已存在，跳过打 tag"
    else
      git tag -a "$target_tag" origin/main -m "Hotfix release $target_tag"
      git push origin "$target_tag"
      echo "已创建并推送 tag: $target_tag"
    fi

    # 检测是否有活动中的 release 分支需要同步
    active_releases=$(sns_active_release_branches)
    if [[ -n "$active_releases" ]]; then
      echo ""
      echo "检测到活动 release 分支:"
      echo "$active_releases" | while read rb; do
        echo "  $rb"
      done
      echo ""
      echo "重要: 以下 release 分支需要同步此 hotfix 修复:"
      echo "$active_releases" | while read rb; do
        echo "  git checkout $rb && git merge $target_tag"
      done
      echo ""
      echo "请手动执行上述命令完成 release 同步"
    fi

    # 回到所属 worktree（hotfix 通常从 worktree 创建）
    owning_worktree=""
    wt_num=$(pwd | grep -oP 'worktree-\K\d+')
    if [[ -n "$wt_num" ]]; then
      owning_worktree="worktree-$wt_num"
    fi

    # 删除本地 hotfix 分支（已合并）
    git checkout "$owning_worktree" 2>/dev/null || true
    git branch -D "$current_branch" 2>/dev/null || true

    # 同步 worktree 到最新 main
    git fetch origin main
    if sns_workdir_clean; then
      git reset --hard origin/main
      echo "$owning_worktree 已同步到最新 main"
    else
      echo "提示: 当前 worktree 有未提交更改，请手动 sync"
      echo "  /sns-workflow:sync"
    fi

    echo ""
    echo "hotfix $target_tag 已发布并回流 main"
    ;;

esac
```

---

## 步骤 5: 最终状态

```bash
echo ""
echo "=== commit-push-pr 完成 ==="
echo "分支类型: $branch_type"
echo "当前分支: $(git branch --show-current)"
echo "最新提交: $(git log --oneline -1)"

if [[ "$branch_type" == "hotfix" ]]; then
  echo "新 tag: $target_tag"
  echo ""
  echo "线上版本: $target_tag"
fi

if [[ "$branch_type" == "release" ]]; then
  echo "预发布 tag: $next_tag"
fi
```
