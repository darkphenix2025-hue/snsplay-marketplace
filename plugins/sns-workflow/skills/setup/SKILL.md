---
name: sns-workflow:setup
description: 项目初始化 —— 创建 .sns-workflow 目录结构并设置初始版本号为 v0.0.0。
user-invocable: true
allowed-tools: Bash
---

# 项目初始化技能

为仓库初始化 sns-workflow 所需的基础目录结构，并设置初始版本号 v0.0.0。

---

## 步骤 1: 验证环境

```bash
current_branch=$(git branch --show-current)

if [[ "$current_branch" != "main" ]]; then
  echo "错误: 初始化仅在 main 分支上执行 (当前: $current_branch)"
  exit 1
fi

if [[ -n $(git status --porcelain) ]]; then
  echo "错误: 工作目录有未提交的更改，请先处理"
  git status --short
  exit 1
fi
```

---

## 步骤 2: 创建目录结构

```bash
mkdir -p .sns-workflow/scripts
mkdir -p plugins/sns-workflow/skills
```

---

## 步骤 3: 写入版本脚本

```bash
cat > .sns-workflow/scripts/version.sh << 'VERSION_SCRIPT'
#!/usr/bin/env bash
# sns-workflow 版本计算脚本
# 所有涉及版本号的技能 source 此脚本，消除重复代码

sns_validate_version() {
  local v="$1"
  [[ "$v" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

sns_latest_tag() {
  git tag -l --sort=-version:refname | head -1
}

sns_bump_version() {
  local tag="${1:-}"
  local bump_type="$2"
  local major minor patch

  if [[ -z "$tag" ]]; then
    case "$bump_type" in
      patch)  echo "v0.0.1"; return ;;
      minor)  echo "v0.1.0"; return ;;
      major)  echo "v1.0.0"; return ;;
    esac
  fi

  major=$(echo "$tag" | sed 's/^v//' | cut -d. -f1)
  minor=$(echo "$tag" | sed 's/^v//' | cut -d. -f2)
  patch=$(echo "$tag" | sed 's/^v//' | cut -d. -f3)

  case "$bump_type" in
    patch) patch=$((patch + 1));;
    minor) minor=$((minor + 1)); patch=0;;
    major) major=$((major + 1)); minor=0; patch=0;;
  esac

  echo "v${major}.${minor}.${patch}"
}
VERSION_SCRIPT

chmod +x .sns-workflow/scripts/version.sh
echo "已创建 .sns-workflow/scripts/version.sh"
```

---

## 步骤 4: 设置初始版本

```bash
source .sns-workflow/scripts/version.sh

latest_tag=$(sns_latest_tag)

if [[ -n "$latest_tag" ]]; then
  echo "警告: 已存在 tag $latest_tag，跳过版本初始化"
else
  git tag -a "v0.0.0" -m "Initial version"
  echo "已创建初始版本 tag: v0.0.0"
fi
```

---

## 步骤 5: 提交并推送

```bash
git add .sns-workflow/
git status --short

echo "提交项目初始化..."
git commit -m "chore: initialize sns-workflow (v0.0.0)"

echo "推送到远端..."
git push origin main
git push origin v0.0.0

echo ""
echo "=== 项目初始化完成 ==="
echo "版本: v0.0.0"
echo "目录: .sns-workflow/"
```
