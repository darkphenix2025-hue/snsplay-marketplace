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

if [[ "$current_branch" == "main" ]]; then
  mode="create"
elif [[ "$current_branch" =~ ^release/ ]]; then
  mode="iterate"
else
  echo "错误: release 命令仅在 main 或 release/* 分支上使用 (当前: $current_branch)"
  exit 1
fi

git fetch origin main
```

---

## 步骤 2: 版本参数处理

```bash
source .sns-workflow/scripts/version.sh

version="${1:-}"

if [[ "$mode" == "create" ]]; then
  if [[ -z "$version" ]]; then
    latest_tag=$(sns_latest_tag)
    version=$(sns_bump_version "$latest_tag" minor)
    echo "自动计算版本号: $latest_tag → $version"
  fi

  if ! sns_validate_version "$version"; then
    echo "错误: 版本号格式必须为 v<major>.<minor>.<patch>"
    exit 1
  fi

  git checkout -b "release/$version"
  echo "已创建 release/$version 分支"
else
  current_version=$(echo "$current_branch" | sed 's/^release\///')

  if [[ -n "$1" ]]; then
    version="$1"
    if ! sns_validate_version "$version"; then
      echo "错误: 版本号格式必须为 v<major>.<minor>.<patch>"
      exit 1
    fi
  else
    version=$(sns_bump_version "$current_version" patch)
    echo "迭代版本: $current_version → $version"
  fi

  git branch -m "release/$current_version" "release/$version" 2>/dev/null || true
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
