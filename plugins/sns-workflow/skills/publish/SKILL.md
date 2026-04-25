---
name: sns-workflow:publish
description: 发布到生产线 —— 仅在匹配的 release 分支上打正式 Tag 并回流 main。不支持从 main 快速发布。
user-invocable: true
allowed-tools: Bash
---

# 发布到生产线

在匹配的 `release/x.y.z` 分支上打正式 Tag `vX.Y.Z`，发布后自动回流 main。

**不支持从 main 直接发布** — 常规发布必须经过 `main → release/* → tag` 完整链路。

---

## 步骤 1: 验证环境与上下文

```bash
source .sns-workflow/scripts/version.sh
source .sns-workflow/scripts/context.sh

current_branch=$(git branch --show-current)
branch_type=$(sns_branch_type)

# 必须在 release 分支上
if [[ "$branch_type" != "release" ]]; then
  echo "错误: publish 命令仅在 release/* 分支上使用 (当前: $current_branch, 类型: $branch_type)"
  echo "常规发布流程: /sns-workflow:release → 测试 → /sns-workflow:publish"
  exit 1
fi

# 工作区必须干净
if ! sns_workdir_clean; then
  echo "错误: 工作区有未提交的更改，请先处理"
  git status --short
  exit 1
fi
```

---

## 步骤 2: 提取并校验版本号

```bash
# 从分支名提取版本号 (release/1.6.0 → v1.6.0)
branch_version=$(echo "$current_branch" | sed 's/^release\///')
target_tag="v$branch_version"

# 校验版本号格式
if ! sns_validate_version "$target_tag"; then
  echo "错误: release 分支名版本号格式不正确: $branch_version"
  echo "期望格式: release/x.y.z (如 release/1.6.0)"
  exit 1
fi

# 如果传了参数，校验参数与分支名匹配
if [[ -n "${1:-}" ]]; then
  param_tag="$1"
  # 补全 v 前缀
  [[ "$param_tag" != v* ]] && param_tag="v$param_tag"

  if [[ "$param_tag" != "$target_tag" ]]; then
    echo "错误: 参数版本 $param_tag 与当前分支 $current_branch 不匹配"
    echo "当前分支对应版本: $target_tag"
    exit 1
  fi
fi

echo "发布版本: $target_tag"
echo "当前分支: $current_branch"
```

---

## 步骤 3: 校验 Tag 不存在

```bash
latest_tag=$(sns_latest_tag)

if sns_tag_exists "$target_tag"; then
  echo "错误: tag $target_tag 已存在，无法重复发布"
  echo "当前线上版本: $latest_tag"
  exit 1
fi

# 校验目标版本 > 线上版本
if [[ -n "$latest_tag" ]] && ! sns_version_gt "$target_tag" "$latest_tag"; then
  echo "错误: 目标版本 $target_tag 不大于当前线上版本 $latest_tag"
  echo "发布版本必须严格递增"
  exit 1
fi

echo "线上版本: ${latest_tag:-无}"
echo "目标版本: $target_tag (验证通过)"

# 检测预发布 tag 历史（信息提示，不阻塞）
latest_pre=$(sns_latest_prerelease_tag "$target_tag")
if [[ -n "$latest_pre" ]]; then
  echo ""
  echo "已检测到预发布 tag: $latest_pre"
  echo "发布将基于当前 release 分支 HEAD 打正式 tag"
fi
```

---

## 步骤 4: 推送 release 分支并打 Tag

```bash
# 确保 release 分支已推送到远端
git push -u origin "$current_branch" 2>/dev/null || true

# 打正式 Tag
git tag -a "$target_tag" -m "Release $target_tag"
echo "已打 tag: $target_tag"

# 推送 tag
git push origin "$target_tag"
echo "已推送 tag: $target_tag"
```

---

## 步骤 5: 回流 main

```bash
echo "回流 main..."

# 切到 main 并合并 release
git checkout main
git pull origin main
git merge "$current_branch" --no-edit
git push origin main

echo "release 已回流 main"
```

---

## 步骤 6: 发布结果

```bash
echo ""
echo "=== 发布完成 ==="
echo "线上版本: $target_tag"
echo "release 分支: $current_branch (已回流 main)"
echo "当前分支: $(git branch --show-current)"
echo "最新提交: $(git log --oneline -1)"
echo ""
echo "下一步:"
echo "  - main 已进入下一开发态"
echo "  - 可删除 release 分支: git branch -d $current_branch"
```
