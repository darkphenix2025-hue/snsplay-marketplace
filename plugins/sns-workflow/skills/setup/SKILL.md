---
name: sns-workflow:setup
description: 项目初始化 —— 创建 .sns-workflow 目录结构并设置初始版本号为 v0.0.0。支持 --force 参数强制重新初始化。
user-invocable: true
allowed-tools: Bash
---

# 项目初始化技能

为仓库初始化 sns-workflow 所需的基础目录结构，并设置初始版本号 v0.0.0。

**参数**: `--force` — 强制重新初始化（删除已有 .sns-workflow 目录并重建）

---

## 步骤 1: 验证环境

```bash
FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

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

## 步骤 2: 检查初始化状态

```bash
VERSION_SH=".sns-workflow/scripts/version.sh"

if [[ -f "$VERSION_SH" ]]; then
  source "$VERSION_SH"

  all_tags=$(git tag -l --sort=-version:refname)
  latest_tag=$(echo "$all_tags" | head -1)
  tag_count=$(echo "$all_tags" | grep -c . 2>/dev/null || echo "0")

  echo "=== sns-workflow 项目已初始化 ==="
  echo ""
  echo "版本脚本: $VERSION_SH (存在)"
  echo "当前版本: ${latest_tag:-无 tag}"
  echo "总版本数: $tag_count"
  echo ""

  if [[ "$FORCE" == "true" ]]; then
    echo "⚠ --force 参数已启用，正在删除已有配置..."
    rm -rf .sns-workflow/
    echo "已删除 .sns-workflow/ 目录，继续初始化流程..."
    echo ""
  else
    echo "提示: 如需重新初始化，请使用 /sns-workflow:setup --force"
    echo ""
    echo "=== 项目初始化状态 ==="
    echo "目录: .sns-workflow/"
    echo "脚本: version.sh (已存在)"
    echo "版本: ${latest_tag:-未打 tag}"
    exit 0
  fi
fi
```

---

## 步骤 3: 创建目录结构

```bash
mkdir -p .sns-workflow/scripts
mkdir -p plugins/sns-workflow/skills
```

---

## 步骤 4: 写入版本脚本

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

## 步骤 5: 设置初始版本

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

## 步骤 6: 提交并推送

```bash
git add .sns-workflow/
CHANGES=$(git status --short)

if [[ -z "$CHANGES" ]]; then
  echo "无新变更，跳过提交"
else
  echo "提交项目初始化..."
  git commit -m "chore: initialize sns-workflow (v0.0.0)"

  echo "推送到远端..."
  git push origin main
  git push origin v0.0.0 2>/dev/null || true
fi

echo ""
echo "=== 项目初始化完成 ==="
echo "版本: v0.0.0"
echo "目录: .sns-workflow/"
```
