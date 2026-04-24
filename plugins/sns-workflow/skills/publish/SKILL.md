---
name: sns-workflow:publish
description: 发布到生产线 —— 基于 release 分支打 tag，或从 main 快速发布。
user-invocable: true
allowed-tools: Bash
---

# 发布到生产线技能

从 release 分支打 tag 完成上线；若无 release 版本，则从 main 快速发布（patch+1）。

---

## 步骤 1: 验证环境

```bash
current_branch=$(git branch --show-current)

if [[ "$current_branch" != "main" ]]; then
  echo "错误: publish 命令仅在 main 分支上使用 (当前: $current_branch)"
  exit 1
fi
```

---

## 步骤 2: 检测 release 版本

```bash
release_branch=$(git branch --list 'release/*' | sed 's/^[* ]* //' | tail -1)

if [[ -n "$release_branch" ]]; then
  version=$(echo "$release_branch" | sed 's/^release\///')

  if ! sns_validate_version "$version" 2>/dev/null; then
    echo "错误: release 分支版本号格式无效: $version"
    exit 1
  fi

  echo "检测到 release 分支: $release_branch"
  echo "发布版本: $version"

  if git tag -l "$version" | grep -q "$version"; then
    echo "错误: tag $version 已存在，请勿重复发布"
    exit 1
  fi
fi
```

---

## 步骤 3: 计算版本号（无 release 时）

```bash
if [[ -z "$version" ]]; then
  source .sns-workflow/scripts/version.sh

  latest_tag=$(sns_latest_tag)
  version=$(sns_bump_version "$latest_tag" minor)
  echo "无 release 版本，自动计算: $latest_tag → $version"

  if ! sns_validate_version "$version"; then
    echo "错误: 版本号格式必须为 v<major>.<minor>.<patch>"
    exit 1
  fi

  if git tag -l "$version" | grep -q "$version"; then
    echo "错误: tag $version 已存在，请勿重复发布"
    exit 1
  fi
fi
```

---

## 步骤 4: 打 tag

```bash
git fetch origin

if [[ -n "$release_branch" ]]; then
  # 基于 release 分支打 tag
  git checkout "$release_branch"
  git pull origin "$release_branch" 2>/dev/null || true
  git tag -a "$version" -m "Release $version"
  echo "已在 $release_branch 上打 tag: $version"

  echo "合并到 main..."
  git checkout main
  git merge "$release_branch" --no-edit
  echo "已合并到 main"
else
  # 从 main 快速发布
  git tag -a "$version" -m "Release $version"
  echo "已在 main 上打 tag: $version"
fi
```

---

## 步骤 5: 推送

```bash
git push origin "$version"
git push origin main 2>/dev/null || true

echo ""
echo "=== 发布完成 ==="
echo "版本: $version"
echo "tag: 已推送到远端"
```
