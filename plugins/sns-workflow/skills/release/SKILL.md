---
name: sns-workflow:release
description: 发布工作流入口 —— 从 main 切出 release 分支，支持小版本迭代。
user-invocable: true
allowed-tools: Bash
---

# 发布工作流技能

从 main 创建 release 分支，进行最终测试和修补。

---

## 步骤 1: 验证环境

```bash
current_branch=$(git branch --show-current)

# 验证 main 分支或 release 分支
if [[ "$current_branch" == "main" ]]; then
  mode="create"
elif [[ "$current_branch" =~ ^release/ ]]; then
  mode="iterate"
else
  echo "错误: release 命令仅在 main 或 release/* 分支上使用 (当前: $current_branch)"
  exit 1
fi

# 确保本地与远程同步
git fetch origin main
```

---

## 步骤 2: 版本参数处理

```bash
version="${1:-}"

if [[ "$mode" == "create" ]]; then
  # 创建模式: 需要版本号
  if [[ -z "$version" ]]; then
    # 自动计算: 取最新 tag + 1 minor
    latest_tag=$(git tag -l --sort=-version:refname | head -1)
    if [[ -z "$latest_tag" ]]; then
      version="v0.1.0"
    else
      major=$(echo "$latest_tag" | sed 's/^v//' | cut -d. -f1)
      minor=$(echo "$latest_tag" | sed 's/^v//' | cut -d. -f2)
      new_minor=$((minor + 1))
      version="v${major}.${new_minor}.0"
    fi
    echo "自动计算版本号: $latest_tag → $version"
  fi

  if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "错误: 版本号格式必须为 v<major>.<minor>.<patch>"
    exit 1
  fi

  git checkout -b "release/$version"
  echo "已创建 release/$version 分支"
else
  # 迭代模式: 自动递增 patch 版本
  version=$(echo "$current_branch" | sed 's/^release\///')
  if [[ -z "$version" ]]; then
    echo "错误: 无法从分支名提取版本号"
    exit 1
  fi

  if [[ -n "$1" ]]; then
    # 用户指定了新版本号
    version="$1"
    if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "错误: 版本号格式必须为 v<major>.<minor>.<patch>"
      exit 1
    fi
  else
    # 自动递增 patch
    major=$(echo "$version" | sed 's/^v//' | cut -d. -f1)
    minor=$(echo "$version" | sed 's/^v//' | cut -d. -f2)
    patch=$(echo "$version" | sed 's/^v//' | cut -d. -f3)
    new_patch=$((patch + 1))
    new_version="v${major}.${minor}.${new_patch}"
    echo "迭代版本: $version → $new_version"
    version="$new_version"
  fi

  # 重命名分支
  git branch -m "release/$current_branch" "release/$version" 2>/dev/null || true
  echo "已更新为 release/$version"
fi
```

---

## 步骤 3: 验证

```bash
echo ""
echo "Release 分支就绪:"
echo "  分支: release/$version"
echo "  基于: $(git log --oneline -1)"
echo ""
echo "接下来:"
echo "  1. 在 release 分支上进行测试和修补"
echo "  2. 需要迭代时直接修改代码，版本自动递增"
echo "  3. 测试通过后执行: sns-workflow commit-push-pr"
```
