---
name: sns-workflow:feature
description: Feature 模式入口命令 —— 自动 sync 到最新 main 并创建 feature 分支。仅可在空闲 worktree-NNN 分支上使用。参数: <feature-name>。
user-invocable: true
allowed-tools: Bash
---

# Feature 模式入口命令

在空闲 worktree 上同步到最新 main 并创建 feature 分支，进入 Feature 开发模式。feature 完成后通过 `/sns-workflow:commit-push-pr` 提交。

**参数**: `<feature-name>` — 可选，feature 名称（如 `user-auth`、`payment`）。省略时自动生成随机名称。支持中文名称，将自动转换为英文分支名（如 `用户认证` → `feature/user-auth`）。

---

## 步骤 1: 验证环境与上下文

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/version.sh"
source "$SHELL_DIR/context.sh"

current_branch=$(git branch --show-current)
branch_type=$(sns_branch_type)

# 必须在 worktree 分支上
if [[ "$branch_type" != "worktree" ]]; then
  echo "错误: feature 命令仅在 worktree 分支上使用 (当前: $current_branch, 类型: $branch_type)"
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

## 步骤 2: 解析并生成 feature 名称

```bash
raw_name="${1:-}"

if [[ -z "$raw_name" ]]; then
  # 无参数: 自动生成随机英文名称
  words=(auth payment user order search notification image analytics cache config deploy feature module api service webhook template component workflow)
  w1=${words[$((RANDOM % ${#words[@]}))]}
  w2=${words[$((RANDOM % ${#words[@]}))]}
  suffix=$(date +%s | tail -c 4)
  feature_name="${w1}-${w2}-${suffix}"
  echo "未提供 feature 名称，自动生成: $feature_name"
else
  # 有参数: 检查是否为纯英文合法名称
  if [[ "$raw_name" =~ ^[a-z0-9-]+$ ]]; then
    feature_name="$raw_name"
  else
    # 包含非英文字符（中文等），尝试转换为拼音
    converted=""

    # 尝试使用 pinyin 工具
    if command -v pinyin &> /dev/null; then
      converted=$(pinyin -s '-' "$raw_name" 2>/dev/null | head -1 | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
    fi

    # 尝试使用 lux 工具（ibus 拼音）
    if [[ -z "$converted" ]] && command -v lux &> /dev/null; then
      converted=$(echo "$raw_name" | lux 2>/dev/null | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
    fi

    # 都没有工具时，使用随机名称并提示
    if [[ -z "$converted" ]]; then
      words=(auth payment user order search notification image analytics cache config deploy feature module api service webhook template component workflow)
      w1=${words[$((RANDOM % ${#words[@]}))]}
      w2=${words[$((RANDOM % ${#words[@]}))]}
      suffix=$(date +%s | tail -c 4)
      feature_name="${w1}-${w2}-${suffix}"
      echo "未安装 pinyin 转换工具，自动生成: $feature_name"
      echo "如需中文自动转换，请安装: pip install pypinyin 或使用 pinyin 命令行工具"
    else
      feature_name="$converted"
      echo "中文名称 '$raw_name' 转换为: $feature_name"
    fi
  fi
fi

# 截取有效部分
feature_name=$(echo "$feature_name" | cut -c1-50)

# 确保最终名称格式合法
if [[ ! "$feature_name" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] && [[ ! "$feature_name" =~ ^[a-z0-9]$ ]]; then
  # 清理后仍不合法，用随机名称兜底
  feature_name="feat-$(date +%s | tail -c 4)"
fi

target_branch="feature/$feature_name"
echo "分支名称: $target_branch"
```

---

## 步骤 3: 校验无重名分支

```bash
if git show-ref --verify --quiet "refs/heads/$target_branch" 2>/dev/null; then
  echo "错误: 本地分支 $target_branch 已存在"
  exit 1
fi

if git ls-remote origin "refs/heads/$target_branch" 2>/dev/null | grep -q .; then
  echo "错误: 远端分支 $target_branch 已存在"
  exit 1
fi
```

---

## 步骤 4: 自动 Sync

```bash
echo "同步到最新 main..."
git fetch origin main

ahead=$(sns_ahead_count)
behind=$(sns_behind_count)

if [[ "$behind" -gt 0 ]]; then
  if [[ "$ahead" -eq 0 ]]; then
    git reset --hard origin/main
  else
    if ! git rebase origin/main; then
      echo "错误: sync 失败 (rebase 冲突)，请先解决冲突"
      echo "可执行: git rebase --abort 放弃同步"
      exit 1
    fi
  fi
  echo "同步完成"
else
  echo "已是最新"
fi
```

---

## 步骤 5: 创建 feature 分支

```bash
git checkout -b "$target_branch"

echo ""
echo "=== Feature 分支已创建 ==="
echo "所属 worktree: $current_branch"
echo "feature 分支: $target_branch"
echo "线上版本: $(sns_latest_tag)"
echo ""
echo "接下来:"
echo "  1. 修改代码（开发阶段不手动 commit）"
echo "  2. 完成后执行: /sns-workflow:commit-push-pr"
echo "  3. 系统将自动: PR 合并到 main → 删除 feature → 回到 $current_branch"
```
