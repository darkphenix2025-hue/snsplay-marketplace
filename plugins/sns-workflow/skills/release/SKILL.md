---
name: sns-workflow:release
description: 发布工作流入口 —— 从 main 切出 release 分支。
user-invocable: true
allowed-tools: Bash
---

# 发布工作流技能

从 main 创建 release 分支，准备发布候选版本。

---

## 步骤 1: 验证环境

```bash
current_branch=$(git branch --show-current)

# 验证 main 分支
if [[ "$current_branch" != "main" ]]; then
  echo "错误: release 命令仅在 main 分支上使用 (当前: $current_branch)"
  exit 1
fi

# 确保本地与远程同步
git fetch origin main
```

---

## 步骤 2: 验证版本参数

```bash
version="${1:-}"
if [[ -z "$version" ]]; then
  echo "用法: sns-workflow release <version>"
  echo "示例: sns-workflow release v1.1.0"
  exit 1
fi

# 验证版本号格式
if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "错误: 版本号格式必须为 v<major>.<minor>.<patch> (例如: v1.1.0)"
  exit 1
fi
```

---

## 步骤 3: 创建 release 分支

```bash
git checkout -b "release/$version"
echo "已创建 release/$version 分支"
```

---

## 步骤 4: 验证

```bash
echo "Release 分支就绪:"
echo "  分支: release/$version"
echo "  基于: $(git log --oneline -1)"
echo ""
echo "接下来:"
echo "  1. 在 release 分支上进行最终测试和修补"
echo "  2. 测试通过后执行: sns-workflow publish $version"
```
