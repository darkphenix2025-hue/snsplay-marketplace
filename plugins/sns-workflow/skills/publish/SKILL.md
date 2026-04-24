---
name: sns-workflow:publish
description: 发布到生产线 —— 从 main 打 tag。可选合并到 product 分支。
user-invocable: true
allowed-tools: Bash
---

# 发布到生产线技能

从 main 打 tag 并推送到远端。如果 product 分支存在则自动合并。

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

## 步骤 2: 计算版本号

```bash
version="${1:-}"

if [[ -z "$version" ]]; then
  # 自动计算: 取最新 tag + 1 patch
  latest_tag=$(git tag -l --sort=-version:refname | head -1)
  if [[ -z "$latest_tag" ]]; then
    version="v0.0.0"
  else
    # 提取版本组件
    major=$(echo "$latest_tag" | sed 's/^v//' | cut -d. -f1)
    minor=$(echo "$latest_tag" | sed 's/^v//' | cut -d. -f2)
    patch=$(echo "$latest_tag" | sed 's/^v//' | cut -d. -f3)
    new_patch=$((patch + 1))
    version="v${major}.${minor}.${new_patch}"
  fi
  echo "自动计算版本号: $latest_tag → $version"
fi

if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "错误: 版本号格式必须为 v<major>.<minor>.<patch>"
  exit 1
fi
```

---

## 步骤 3: 检查 tag 冲突

```bash
if git tag -l "$version" | grep -q "$version"; then
  echo "错误: tag $version 已存在，请勿重复发布"
  exit 1
fi
```

---

## 步骤 4: 打 tag

```bash
git tag -a "$version" -m "Release $version"
git push origin "$version"
echo "已打 tag: $version"
```

---

## 步骤 5: 合并到 product（可选）

```bash
if git branch -r | grep -q "origin/product"; then
  git checkout product
  git pull origin product
  git merge main --no-edit
  git push origin product
  echo "已合并到 product 分支"
else
  echo "远端无 product 分支，跳过合并"
fi
```

---

## 步骤 6: 回到 main

```bash
git checkout main
echo ""
echo "=== 发布完成 ==="
echo "版本: $version"
echo "tag: 已推送到远端"
```
