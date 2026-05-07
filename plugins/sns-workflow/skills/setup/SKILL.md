---
name: sns-workflow:setup
description: 项目初始化 —— 创建 .sns-workflow 目录并设置初始版本号为 v0.0.0。支持 --force 参数强制重新初始化。
user-invocable: true
allowed-tools: Bash
---

# 项目初始化技能

创建 `.sns-workflow/` 目录（用于项目配置和状态文件），设置初始版本号 v0.0.0。

脚本（version.sh / context.sh）直接从插件 `shell/` 目录引用，不再复制到项目。

**参数**: `--force` — 强制重新初始化（删除已有 .sns-workflow 目录）

---

## 步骤 1: 验证环境与解析参数

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/skill-logger.sh"
sns_skill_start "setup" "$*"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

current_branch=$(git branch --show-current)

if [[ "$current_branch" != "main" ]]; then
  echo "错误: 初始化仅在 main 分支上执行 (当前: $current_branch)"
  exit 1
fi
```

---

## 步骤 2: 检查初始化状态

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/version.sh"

if [[ -d ".sns-workflow" ]]; then
  latest_tag=$(sns_latest_tag)

  echo "=== sns-workflow 项目已初始化 ==="
  echo ""
  echo "当前版本: ${latest_tag:-无 tag}"
  echo ""

  if [[ "$FORCE" == "true" ]]; then
    echo "--force 参数已启用，正在删除已有配置..."
    rm -rf .sns-workflow/
    echo "已删除 .sns-workflow/ 目录，继续初始化流程..."
    echo ""
  else
    echo "提示: 如需重新初始化，请使用 /sns-workflow:setup --force"
    echo ""
    echo "=== 项目初始化状态 ==="
    echo "目录: .sns-workflow/"
    echo "版本: ${latest_tag:-未打 tag}"
    echo "脚本: 直接引用插件 shell/ 目录（无需安装）"
    exit 0
  fi
fi
```

---

## 步骤 3: 创建目录结构

```bash
mkdir -p .sns-workflow

echo "已创建: .sns-workflow/"
```

---

## 步骤 4: 验证脚本可用

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/version.sh"
source "$SHELL_DIR/context.sh"

if ! type sns_latest_tag &>/dev/null; then
  echo "错误: version.sh 函数不可用 (路径: $SHELL_DIR/version.sh)"
  exit 1
fi

if ! type sns_branch_type &>/dev/null; then
  echo "错误: context.sh 函数不可用 (路径: $SHELL_DIR/context.sh)"
  exit 1
fi

echo "脚本验证通过 (引用: $SHELL_DIR/)"
```

---

## 步骤 5: 设置初始版本

```bash
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
echo "目录: .sns-workflow/（项目配置和状态）"
echo "脚本: 直接引用插件 shell/ 目录（version.sh + context.sh）"

sns_skill_end "success"
```
