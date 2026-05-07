---
name: sns-workflow:doc-garden
description: 渐进式文档花园 —— 检查并整理当前项目的 CLAUDE.md 地图和 docs/ 目录。首次运行自动迁移现有文件到分层架构，后续运行检查合规性。支持 --check（仅检查）和 --fix（自动修复）模式。
user-invocable: true
allowed-tools: Bash
---

# 渐进式文档花园

检查并整理当前项目的 CLAUDE.md 地图和 docs/ 目录。首次运行自动迁移现有文件到分层架构，后续运行检查合规性。

**参数**:
- `--check` — 仅检查，不修改
- `--fix` — 检查并自动修复（创建缺失目录和模板文件）
- `--cron` — Cron 自动化模式（仅 main worktree 执行写入，其他分支跳过）
- 无参数 — 首次运行自动迁移，后续运行自动检查+修复

**Cron 调度**: 使用 `scripts/cron-runner.sh doc-garden` 包装，自动限定 main worktree 运行。

---

## 步骤 1: 验证环境

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/context.sh"
source "$SHELL_DIR/skill-logger.sh"
sns_skill_start "doc-garden" "$*"
source "$SHELL_DIR/doc-arch-template.sh"

# 确认在 git 仓库中
current_branch=$(git branch --show-current 2>/dev/null)
if [[ -z "$current_branch" ]]; then
  echo "错误: 未在 git 仓库中"
  exit 1
fi

# 解析参数
MODE="auto"
CRON_MODE=false
for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    --fix) MODE="fix" ;;
    --cron) CRON_MODE=true ;;
  esac
done

# Cron 模式: 仅 main worktree 执行写入，非 main 跳过
if $CRON_MODE && ! sns_is_main_worktree; then
  echo "[cron] 跳过: 不在 main worktree (当前: $current_branch)"
  sns_skill_end "skipped" "cron: not on main worktree"
  exit 0
fi

if $CRON_MODE && ! sns_cron_lock "doc-garden"; then
  echo "[cron] 跳过: 已有其他 doc-garden 实例运行"
  sns_skill_end "skipped" "cron: lock busy"
  exit 0
fi

echo "当前分支: $current_branch | 模式: $MODE"
```

---

## 步骤 2: 检测是否首次运行

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/doc-arch-template.sh"

ROOT=$(_sns_doc_root)
IS_FIRST_RUN=false

if [[ ! -f "$ROOT/docs/ARCHITECTURE.md" ]] || [[ ! -s "$ROOT/docs/ARCHITECTURE.md" ]]; then
  IS_FIRST_RUN=true
  echo "检测到首次运行，将执行自动迁移"
fi
```

---

## 步骤 3: 首次迁移（仅首次运行）

如果 `IS_FIRST_RUN=true`，执行迁移：

```bash
if $IS_FIRST_RUN; then
  echo "=== 执行首次文档迁移 ==="
  sns_doc_migrate
  echo ""
  echo "迁移完成！请检查 docs/ 目录内容。"
  echo "CLAUDE.md 需要手动精简为地图索引（<150 行）。"
fi
```

迁移步骤会自动完成以下工作：
- 创建目标目录结构（design-docs/、exec-plans/、references/、product-specs/、generated/）
- 迁移现有文件到新架构位置
- 生成 index.md 索引文件
- 创建空模板文件（DESIGN.md、SECURITY.md 等）
- 创建 AGENTS.md 符号链接 → CLAUDE.md

---

## 步骤 4: 检查 CLAUDE.md 地图

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/doc-arch-template.sh"

ROOT=$(_sns_doc_root)
if [[ -f "$ROOT/CLAUDE.md" ]]; then
  LINES=$(wc -l < "$ROOT/CLAUDE.md")
  echo "CLAUDE.md: $LINES 行 (最大 $SNS_DOC_CLAUDE_MD_MAX_LINES 行)"

  if [[ "$LINES" -gt "$SNS_DOC_CLAUDE_MD_MAX_LINES" ]]; then
    echo "警告: CLAUDE.md 过长 ($LINES > $SNS_DOC_CLAUDE_MD_MAX_LINES)"
    echo "建议: 精简为地图索引，详细内容移至 docs/ 子目录"
  fi

  if ! grep -q "文档地图\|docs/" "$ROOT/CLAUDE.md" 2>/dev/null; then
    echo "警告: CLAUDE.md 缺少文档地图索引"
    echo "建议: 添加「文档地图」章节，指向 docs/ 子目录"
  fi
fi
```

---

## 步骤 5: 运行架构检查

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/doc-arch-template.sh"

echo ""
echo "=== 文档架构检查 ==="
CHECK_OUTPUT=$(sns_doc_check --report 2>&1)
CHECK_EXIT=$?

if [[ "$CHECK_EXIT" -eq 0 ]]; then
  echo "✓ 文档架构合规"
else
  echo "$CHECK_OUTPUT"
fi
```

---

## 步骤 6: 修复模式（--fix 或 auto）

如果 `MODE=fix` 或 `MODE=auto`，执行修复：

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/doc-arch-template.sh"

if [[ "$MODE" == "fix" ]] || [[ "$MODE" == "auto" ]]; then
  if [[ "$CHECK_EXIT" -ne 0 ]]; then
    echo ""
    echo "=== 自动修复 ==="
    sns_doc_fix --auto
    echo ""
    echo "已创建缺失的目录结构和模板文件。"
    echo "请手动填写内容文件（CLAUDE.md、ARCHITECTURE.md 等）。"
  fi
fi
```

---

## 步骤 7: 输出汇总

```bash
echo ""
echo "=== doc-garden 完成 ==="
echo "模式: $MODE"
echo "首次运行: $IS_FIRST_RUN"

if [[ "$CHECK_EXIT" -eq 0 ]]; then
  echo "状态: 合规"
else
  echo "状态: 待修复"
fi

sns_skill_end "success"

# Cron 模式释放锁
if $CRON_MODE; then sns_cron_unlock "doc-garden"; fi
```
