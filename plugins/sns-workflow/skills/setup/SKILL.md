---
name: sns-workflow:setup
description: 项目初始化 —— 从插件模板安装 .sns-workflow 目录结构并设置初始版本号为 v0.0.0。支持 --force 参数强制重新初始化。
user-invocable: true
allowed-tools: Bash
---

# 项目初始化技能

从插件模板目录安装 sns-workflow 所需的脚本和配置到目标项目，并设置初始版本号 v0.0.0。

**参数**: `--force` — 强制重新初始化（删除已有 .sns-workflow 目录并从模板重新安装）

---

## 步骤 1: 验证环境与解析参数

```bash
FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

current_branch=$(git branch --show-current)

if [[ "$current_branch" != "main" ]]; then
  echo "错误: 初始化仅在 main 分支上执行 (当前: $current_branch)"
  exit 1
fi

# 注意: 不要求工作区干净。模板安装是纯文件复制操作，
# 不影响已有未提交变更。commit 时再处理工作区状态。
```

---

## 步骤 2: 检查初始化状态

```bash
INIT_MARKER=".sns-workflow/scripts/version.sh"

if [[ -f "$INIT_MARKER" ]]; then
  source "$INIT_MARKER"

  all_tags=$(git tag -l --sort=-version:refname)
  latest_tag=$(echo "$all_tags" | head -1)
  tag_count=$(echo "$all_tags" | grep -c . 2>/dev/null || echo "0")

  echo "=== sns-workflow 项目已初始化 ==="
  echo ""
  echo "版本脚本: $INIT_MARKER (存在)"
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
    echo "脚本: version.sh + context.sh (已存在)"
    echo "版本: ${latest_tag:-未打 tag}"
    exit 0
  fi
fi
```

---

## 步骤 3: 从模板安装脚本

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"

if [[ -z "$PLUGIN_ROOT" ]]; then
  echo "错误: 无法确定插件根目录 (CLAUDE_PLUGIN_ROOT 未设置)"
  exit 1
fi

TEMPLATES_DIR="$PLUGIN_ROOT/templates/scripts"

if [[ ! -d "$TEMPLATES_DIR" ]]; then
  echo "错误: 模板目录不存在: $TEMPLATES_DIR"
  exit 1
fi

mkdir -p .sns-workflow/scripts

cp "$TEMPLATES_DIR/version.sh" .sns-workflow/scripts/version.sh
cp "$TEMPLATES_DIR/context.sh" .sns-workflow/scripts/context.sh

chmod +x .sns-workflow/scripts/*.sh

echo "已从模板安装:"
echo "  .sns-workflow/scripts/version.sh"
echo "  .sns-workflow/scripts/context.sh"

# 验证安装
source .sns-workflow/scripts/version.sh
source .sns-workflow/scripts/context.sh

if ! type sns_latest_tag &>/dev/null; then
  echo "错误: version.sh 安装后函数不可用"
  exit 1
fi

if ! type sns_branch_type &>/dev/null; then
  echo "错误: context.sh 安装后函数不可用"
  exit 1
fi

echo "脚本验证通过"
```

---

## 步骤 4: 创建目录结构

```bash
mkdir -p .sns-workflow/scripts
mkdir -p plugins/sns-workflow/skills
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
echo "脚本: version.sh + context.sh (从模板安装)"
```
