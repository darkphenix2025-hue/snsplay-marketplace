---
name: sns-workflow:release
description: 发布工作流入口 —— 从 main 切出 release 分支进入候选态。仅可在 main 分支上使用。参数: [版本号]，省略时自动计算 minor+1。
user-invocable: true
allowed-tools: Bash
---

# 发布工作流入口命令

从 main 创建 `release/x.y.z` 分支，进入发布候选态。release 分支上只允许修复、验证和发布准备，禁止新增功能。测试通过后通过 `/sns-workflow:publish` 正式发布。

**参数**: `[版本号]` — 可选，如 `v1.6.0`。省略时从最新 tag 自动计算 minor+1。

---

## 步骤 1: 验证环境与上下文

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/version.sh"
source "$SHELL_DIR/context.sh"
source "$SHELL_DIR/skill-logger.sh"
sns_skill_start "release" "$*"

current_branch=$(git branch --show-current)
branch_type=$(sns_branch_type)

# 必须在 main 分支上
if [[ "$branch_type" != "main" ]]; then
  echo "错误: release 命令仅在 main 分支上使用 (当前: $current_branch, 类型: $branch_type)"
  exit 1
fi

# 工作区必须干净
if ! sns_workdir_clean; then
  echo "错误: 工作区有未提交的更改，请先处理"
  git status --short
  exit 1
fi

git fetch origin main
```

---

## 步骤 2: 检查是否存在同名 release 分支

```bash
active_releases=$(sns_active_release_branches)

if [[ -n "$active_releases" ]]; then
  echo "警告: 已存在活动 release 分支:"
  echo "$active_releases" | while read rb; do
    echo "  $rb"
  done
  echo ""
  echo "建议: 先完成当前 release 流程（publish），再创建新的 release"
  exit 1
fi
```

---

## 步骤 3: 计算并校验目标版本

```bash
version="${1:-}"
latest_tag=$(sns_latest_tag)

if [[ -z "$version" ]]; then
  # 自动计算: 最新 tag minor+1
  version=$(sns_bump_version "$latest_tag" minor)
  if [[ -z "$version" ]]; then
    echo "错误: 无法从 ${latest_tag:-无tag} 计算目标版本"
    exit 1
  fi
  echo "自动计算版本号: ${latest_tag:-无} → $version (minor+1)"
else
  # 校验格式
  if ! sns_validate_version "$version"; then
    echo "错误: 版本号格式必须为 v<major>.<minor>.<patch> (如 v1.6.0)"
    exit 1
  fi

  # 校验目标版本 > 线上版本
  if [[ -n "$latest_tag" ]] && ! sns_version_gt "$version" "$latest_tag"; then
    echo "错误: 目标版本 $version 必须大于当前线上版本 ${latest_tag:-无}"
    exit 1
  fi

  echo "指定版本: $version"
fi

# 分支名: release/x.y.z (去掉 v 前缀)
branch_version=$(echo "$version" | sed 's/^v//')
release_branch="release/$branch_version"
```

---

## 步骤 4: 校验无重名分支

```bash
if git show-ref --verify --quiet "refs/heads/$release_branch" 2>/dev/null; then
  echo "错误: 本地分支 $release_branch 已存在"
  exit 1
fi

if git show-ref --verify --quiet "refs/remotes/origin/$release_branch" 2>/dev/null; then
  echo "错误: 远端分支 $release_branch 已存在"
  exit 1
fi
```

---

## 步骤 5: 创建 release 分支

```bash
git checkout -b "$release_branch"

echo ""
echo "=== Release 分支已创建 ==="
echo "分支: $release_branch"
echo "线上版本: ${latest_tag:-无}"
echo "候选版本: $version"
echo "基于: $(git log --oneline -1)"
echo ""
echo "接下来:"
echo "  1. /sns-workflow:commit-push-pr       → 自动打 $version-beta"
echo "  2. /sns-workflow:commit-push-pr       → 迭代 $version-beta.2 ..."
echo "  3. /sns-workflow:commit-push-pr --rc  → 进入 RC 阶段 $version-rc.1"
echo "  4. /sns-workflow:publish              → 正式发布 $version + 回流 main"

sns_skill_end "success"
```
