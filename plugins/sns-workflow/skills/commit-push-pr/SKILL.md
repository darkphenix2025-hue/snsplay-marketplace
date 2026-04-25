---
name: sns-workflow:commit-push-pr
description: 统一提交+推送+PR+合并+清理 —— 自动检测分支类型，执行对应的完整流程。main/release 直接提交，worktree/feature/hotfix 走 PR 流程。
user-invocable: true
allowed-tools: Bash
---

# 统一提交+推送+PR+合并+清理

自动检测当前分支类型，执行对应的 commit → push → PR → merge → 清理流程。

**五路路由矩阵**:

| 分支类型 | 动作 | 版本效果 |
|---------|------|---------|
| `main` | commit + push（直接提交） | 不产生 tag |
| `release/x.y.z` | commit + push（rc 迭代修复） | 不产生 tag，由 `/sns-workflow:publish` 打正式 tag |
| `worktree-NNN` | commit → PR → merge → reset | 不产生 tag |
| `feature/*` | commit → PR → merge → 删除分支 → 回 worktree | 不产生 tag |
| `hotfix/x.y.z` | commit → PR → merge → 打 tag → 回流 | 生成新 tag vX.Y.Z |

**不支持 unknown 分支**。

---

## 步骤 0: 自愈安装（scripts 缺失时自动补全）

```bash
# 检测依赖脚本是否存在，缺失则从插件模板自动安装
# 解决循环依赖: commit-push-pr 需要 scripts → setup 安装 scripts → setup 要求干净工作区
if [[ ! -f ".sns-workflow/scripts/version.sh" ]] || [[ ! -f ".sns-workflow/scripts/context.sh" ]]; then
  PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
  # fallback: 从当前技能文件路径推导插件根目录
  if [[ -z "$PLUGIN_ROOT" ]] && [[ -f "plugins/sns-workflow/templates/scripts/version.sh" ]]; then
    PLUGIN_ROOT="plugins/sns-workflow"
  fi
  if [[ -n "$PLUGIN_ROOT" ]] && [[ -d "$PLUGIN_ROOT/templates/scripts" ]]; then
    echo "检测到依赖脚本缺失，自动从模板安装..."
    mkdir -p .sns-workflow/scripts
    cp "$PLUGIN_ROOT/templates/scripts/version.sh" .sns-workflow/scripts/version.sh
    cp "$PLUGIN_ROOT/templates/scripts/context.sh" .sns-workflow/scripts/context.sh
    chmod +x .sns-workflow/scripts/*.sh
    echo "已自愈安装: .sns-workflow/scripts/"
  else
    echo "错误: 依赖脚本缺失且无法自动安装"
    echo "请先执行 /sns-workflow:setup"
    exit 1
  fi
fi
```

---

## 步骤 1: 检测环境与上下文

```bash
source .sns-workflow/scripts/version.sh
source .sns-workflow/scripts/context.sh

current_branch=$(git branch --show-current)
branch_type=$(sns_branch_type)

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
if [[ -z $(git diff --cached --stat) ]]; then
  echo "没有需要提交的更改"
  exit 0
fi

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
```

---

## 步骤 3: Push

```bash
git push -u origin "$current_branch" 2>&1 || {
  echo "Push 失败，请检查远端权限"
  exit 1
}
echo "已推送到远端: $current_branch"
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
    echo ""
    echo "=== release 路径: rc 迭代修复 ==="

    rel_version=$(echo "$current_branch" | sed 's/^release\///')
    echo "release/$rel_version 修复已提交并推送"
    echo "候选版本迭代中（rc.1 → rc.2 → ...）"
    echo ""
    echo "测试通过后执行: /sns-workflow:publish"
    echo "系统将: 打正式 tag vX.Y.Z → 回流 main"
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

    gh pr merge --squash --delete-branch 2>&1 || {
      echo "PR 合并失败"
      exit 1
    }
    echo "合并完成"

    # 获取合并后的最新 main
    git fetch origin main

    # 打 tag（在合并后的 main 上）
    if sns_tag_exists "$target_tag"; then
      echo "警告: tag $target_tag 已存在，跳过打 tag"
    else
      git tag -a "$target_tag" -m "Hotfix release $target_tag"
      git push origin "$target_tag"
      echo "已创建并推送 tag: $target_tag"
    fi

    # 回流 main（PR 已合并，确保本地同步）
    git checkout main 2>/dev/null || true
    git pull origin main
    echo "main 已同步"

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
```
