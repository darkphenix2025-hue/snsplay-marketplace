---
name: sns-workflow:commit-push-pr
description: 统一提交+推送+PR+合并+清理 —— 自动检测分支类型执行不同处理逻辑。
user-invocable: true
allowed-tools: Bash
---

# 统一提交+推送+PR+合并+清理

自动检测当前分支类型，执行对应的 commit → push → PR → merge → 清理流程。

**分支类型处理矩阵**:

| 分支类型 | PR 目标 | merge 后动作 |
|---------|---------|-------------|
| `main` | - | 直接 push，无 PR/merge |
| `worktree-NNN` | main | hard reset 到最新 origin/main |
| `feature/*` | main | 删除 feature 分支 → 回到 worktree-NNN |
| `hotfix/*` | product | 打 tag + 创建 product→main 同步 PR |

---

## 步骤 1: 检测环境

```bash
current_branch=$(git branch --show-current)

# 检查 gh CLI 可用性
if ! command -v gh &> /dev/null; then
  echo "错误: gh CLI 未安装或未认证"
  exit 1
fi
gh auth status 2>&1 || { echo "错误: gh 未认证，请先执行 gh auth login"; exit 1; }
```

---

## 步骤 2: 自动 Commit

```bash
git add -A
if [[ -z $(git diff --cached --stat) ]]; then
  echo "没有需要提交的更改"
  exit 0
fi

commit_msg="chore: auto commit from $current_branch"
git commit -m "$commit_msg"
echo "已提交: $commit_msg"
```

---

## 步骤 3: Push + 分支类型路由

```bash
git push -u origin "$current_branch" 2>&1 || {
  echo "Push 失败，请检查远程权限"
  exit 1
}
echo "已推送到远端: $current_branch"
```

---

## 步骤 4: 根据分支类型执行 PR + Merge + 清理

```bash
case "$current_branch" in
  main)
    # 直接在 main 上提交（快速修改场景）
    echo "检测到 main 分支，直接 push..."
    git push origin main 2>&1 || {
      echo "Push 失败，请检查远端权限"
      exit 1
    }
    echo "完成: 已推送到 origin/main"
    ;;

  worktree-*)
    # worktree 是持久化容器，不删除远端分支
    echo "检测到 worktree 分支，创建 PR 到 main..."
    pr_url=$(gh pr create --base main --head "$current_branch" \
      --title "chore: $current_branch → main" \
      --body "Auto-generated PR from worktree branch $current_branch")

    echo "PR 已创建: $pr_url"
    gh pr merge --squash

    echo "合并完成，hard reset 到最新 main..."
    git fetch origin main
    git reset --hard origin/main
    echo "完成: worktree 已同步到最新 main"
    ;;

  feature/*)
    # 从当前 worktree 路径提取编号（最可靠）
    worktree_num=$(pwd | grep -oP 'worktree-\K\d+')
    if [[ -z "$worktree_num" ]]; then
      worktree_num=$(git branch --show-current | grep -oP 'worktree-\K\d-' || echo "")
      if [[ -z "$worktree_num" ]]; then
        echo "错误: 无法确定 worktree 编号，请手动切回 worktree"
        exit 1
      fi
    fi

    echo "检测到 feature 分支，创建 PR 到 main..."
    gh pr create --base main --head "$current_branch" \
      --title "feat: $current_branch → main" \
      --body "Feature branch PR from $current_branch"

    gh pr merge --squash --delete-branch

    echo "合并完成，删除 feature 分支并回到 worktree..."
    git checkout "worktree-$worktree_num" 2>/dev/null || echo "警告: 无法自动切回 worktree，请手动切换"
    echo "完成: feature 分支已合并并清理"
    ;;

  hotfix/*)
    # 从分支名提取版本号 (hotfix/v1.0.1 → v1.0.1)
    version=$(echo "$current_branch" | grep -oP 'v\d+\.\d+\.\d+')
    if [[ -z "$version" ]]; then
      echo "错误: hotfix 分支名必须包含版本号 (格式: hotfix/v1.0.1)"
      exit 1
    fi

    echo "检测到 hotfix 分支，创建 PR 到 main..."
    gh pr create --base main --head "$current_branch" \
      --title "hotfix: $version → main" \
      --body "Hotfix PR for version $version"

    gh pr merge --squash --delete-branch

    echo "合并完成，在 main 上打 tag..."
    # 拉取最新 main 并打 tag
    git fetch origin main
    git reset --hard origin/main
    if git tag -l "$version" | grep -q "$version"; then
      echo "警告: tag $version 已存在，跳过打 tag"
    else
      git tag -a "$version" -m "Hotfix release $version"
      git push origin "$version"
      echo "已打 tag: $version"
    fi

    echo "完成: hotfix $version 已合并到 main"
    ;;

  *)
    echo "错误: 不支持的分支类型: $current_branch"
    echo "支持的分支: worktree-NNN, feature/*, hotfix/*"
    exit 1
    ;;
esac
```

---

## 步骤 5: 最终检查

```bash
echo ""
echo "=== commit-push-pr 完成 ==="
echo "当前分支: $(git branch --show-current)"
echo "最新提交: $(git log --oneline -1)"
```
