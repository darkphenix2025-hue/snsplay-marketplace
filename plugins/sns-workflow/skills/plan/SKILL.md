---
name: sns-workflow:plan
description: 统一计划入口 —— 自动检测变更范围（small/large），生成可执行计划产物，large 时创建 feature 分支。混合模式: Agent 生成初稿 + 用户确认锁定。替代 feature 技能。
user-invocable: true
allowed-tools: Read, Write, Bash, Glob, Grep, AskUserQuestion, Agent
---

# 统一计划入口

自动检测变更范围，生成可执行计划产物（first-class artifact）。支持 small（worktree 直接开发）和 large（创建 feature 分支）两种模式。

**参数**: `<description>` — 变更描述（如 `fix-typo`、`用户认证系统`）
**可选参数**: `--scope small|large` — 手动覆盖自动范围检测

---

## 步骤 0: 引导对话 — 细化需求

Agent 基于用户初始描述，通过 AskUserQuestion 引导用户完善需求，使后续的计划产物更精准。

```bash
raw_description="${1:-}"

if [[ -z "$raw_description" ]]; then
  echo "请描述你要做的变更（如: 修复登录页超时问题、实现用户注册功能）"
  exit 0
fi
```

**引导维度**（Agent 根据描述长度和模糊程度决定提问深度）:

| 维度 | 提问示例 | 目的 |
|------|---------|------|
| **接受标准** | "完成后怎样算 '做好了'？" | 生成 AC |
| **影响面** | "涉及哪些页面/模块？" | 步骤拆分 |
| **风险偏好** | "保守修复还是大胆重构？" | 任务提示 |
| **约束条件** | "有无必须遵守的限制？" | 步骤约束 |

**对话示例**:

```
用户: "修复登录问题"
Agent: 我理解你要修复登录问题。几个问题帮助细化计划:

1. **症状** — 具体表现是什么？
   a. 登录超时/无响应
   b. 凭证验证失败
   c. Session 异常
   d. 其他

2. **影响面** — 涉及哪些模块？
   [ ] 前端登录页  [ ] 后端 API  [ ] 数据库  [ ] 认证服务

3. **风险偏好** — 你希望：
   a. 最小化变更（仅修复当前问题）
   b. 适度改进（同时优化相关代码）
   c. 全面重构（重新设计认证流程）

确认后 Agent 输出细化后的描述并进入步骤 1。
```

**细化规则**:
- 描述包含 20+ 字且明确 → 跳过引导，直接进入步骤 1
- 描述模糊或过短 → 提问 2-4 个维度
- 用户跳过提问 → 使用默认值继续（保守修复模式）

```bash
# Agent 整合用户回答，生成最终描述
# 示例: "修复登录页凭证验证失败问题，涉及前端登录页和后端 API，最小化变更"
final_description="$raw_description"
# (Agent 将基于引导对话结果更新此变量)
```

---

## 步骤 1: 验证环境与上下文

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/context.sh"
source "$SHELL_DIR/skill-logger.sh"
sns_skill_start "plan" "$*"

current_branch=$(git branch --show-current)
branch_type=$(sns_branch_type)

# 必须在 worktree 或 main 分支上
if [[ "$branch_type" != "worktree" ]] && [[ "$branch_type" != "main" ]]; then
  echo "错误: plan 命令仅在 worktree 或 main 分支上使用 (当前: $current_branch, 类型: $branch_type)"
  exit 1
fi

# 工作区必须干净
if ! sns_workdir_clean; then
  echo "错误: 工作区有未提交的更改，请先处理"
  git status --short
  exit 1
fi

# 确保 .snsplay/task/ 目录存在
mkdir -p ".snsplay/task"

echo "环境验证通过: 分支=$current_branch (类型=$branch_type)"
```

---

## 步骤 2: 解析参数与智能范围检测

```bash
# 解析 --scope 参数和描述
raw_description=""
manual_scope=""

for arg in "$@"; do
  if [[ "$arg" == "--scope" ]]; then
    continue
  fi
  if [[ "$arg" == "small" ]] || [[ "$arg" == "large" ]]; then
    if [[ -n "$manual_scope" ]]; then
      echo "错误: 无效的 --scope 值 (期望 small 或 large)"
      exit 1
    fi
    manual_scope="$arg"
    continue
  fi
  raw_description="$raw_description $arg"
done

raw_description=$(echo "$raw_description" | sed 's/^ //')

if [[ -z "$raw_description" ]]; then
  echo "错误: 请提供变更描述"
  echo "用法: /sns-workflow:plan <描述> [--scope small|large]"
  exit 1
fi

echo "变更描述: $raw_description"
echo "手动范围: ${manual_scope:-自动检测}"
```

**范围检测逻辑**（Agent 分析描述自动判断）:

| 维度 | Small | Large |
|------|-------|-------|
| 文件数 | 1-3 个文件 | 4+ 文件或跨目录 |
| 类型 | Bug 修复/配置/文案/小优化 | 新功能/重构/架构变更 |
| 影响面 | 不影响 API/接口/数据模型 | 涉及 API/接口/数据模型变更 |
| 测试 | 单测覆盖即可 | 需要集成测试 + UI 验证 |

```bash
if [[ -n "$manual_scope" ]]; then
  scope="$manual_scope"
  echo "使用手动范围: $scope"
else
  # Agent 自动检测: 分析 raw_description 关键词
  description_lower=$(echo "$raw_description" | tr '[:upper:]' '[:lower:]')

  # Large 关键词: feature, refactor, redesign, implement, add, create (新功能), system, architecture, api, schema
  large_keywords="feature|refactor|redesign|implement|add.*system|create.*system|architecture|api.*design|schema.*change|database|migration|authentication|authorization|new.*component|multiple.*file"

  # Small 关键词: fix typo, fix bug, small fix, minor, update text, change config, patch, hotfix (小修复)
  small_keywords="fix.*typo|minor|trivial|update.*text|change.*config|spell|format|whitespace|readme"

  if echo "$description_lower" | grep -qiE "$large_keywords"; then
    scope="large"
  elif echo "$description_lower" | grep -qiE "$small_keywords"; then
    scope="small"
  else
    # 默认: 中等描述按 large 处理（保守策略）
    scope="large"
  fi

  echo "自动检测范围: $scope"
fi
```

---

## 步骤 3: 生成可执行计划（混合模式）

Agent 根据用户描述自动生成计划初稿，包括执行步骤、接受标准和任务特定提示。

```bash
TIMESTAMP=$(date +%Y%m%d%H%M%S)
plan_id="plan-${TIMESTAMP}"
plan_file=".snsplay/task/${plan_id}.json"
plan_slug=$(echo "$raw_description" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | cut -c1-50)
```

**生成 Acceptance Criteria**（3-5 条，基于描述自动推断）:

Agent 分析变更描述，推断具体的接受标准。例如:
- Bug 修复: 修复生效、无回归、相关测试通过
- 新功能: 功能可用、API 正确、测试覆盖、文档更新
- 配置变更: 配置生效、不影响其他功能

**生成执行步骤**（3-10 步，按文件/模块分组）:

Agent 分析涉及的代码区域，生成结构化的步骤清单:
- 每个步骤包含: 描述、涉及文件列表、类型（create/modify/refactor）
- 步骤按依赖顺序排列

**生成任务特定 Prompt**（1-2 句）:

基于描述生成聚焦的 Agent 提示:
- Bug 修复: "专注修复指定问题，避免引入回归，确保相关测试通过"
- 新功能: "按照现有架构模式实现，关注安全性和错误处理"
- 重构: "保持行为不变，优化代码结构和可读性"

```bash
# 展示计划初稿给用户
cat << 'DRAFT_HEADER'

=== 计划初稿 ===

DRAFT_HEADER

# 输出结构化预览
cat << PLAN_PREVIEW
描述: $raw_description
范围: $scope
步骤数: (Agent 生成后填入)
接受标准: (Agent 生成后填入)
任务提示: (Agent 生成后填入)

分支: $(if [[ "$scope" == "large" ]]; then echo "将创建 feature 分支"; else echo "无（在 $current_branch 直接开发）"; fi)
PLAN_PREVIEW
```

```bash
# 用户确认计划
# 通过 AskUserQuestion 询问用户是否确认计划，或需要修改
# 确认: 继续步骤 4
# 修改: Agent 根据用户反馈迭代直到确认
```

---

## 步骤 4: Large scope — 创建 Feature 分支

仅当 scope 为 large 时执行。分支创建逻辑从 feature 技能迁移。

```bash
# 解析 feature 名称（从描述生成）
feature_raw="$raw_description"

if [[ "$feature_raw" =~ ^[a-z0-9-]+$ ]]; then
  feature_name="$feature_raw"
else
  # 包含非英文字符（中文等），尝试转换为拼音
  converted=""

  if command -v pinyin &> /dev/null; then
    converted=$(pinyin -s '-' "$feature_raw" 2>/dev/null | head -1 | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
  fi

  if [[ -z "$converted" ]] && command -v lux &> /dev/null; then
    converted=$(echo "$feature_raw" | lux 2>/dev/null | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
  fi

  if [[ -z "$converted" ]]; then
    # 无转化工具时，基于描述关键词生成英文名称
    converted=$(echo "$feature_raw" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//' | cut -c1-50)
    if [[ -z "$converted" ]] || [[ ${#converted} -lt 3 ]]; then
      words=(auth payment user order search notification image analytics cache config deploy feature module api service webhook template component workflow)
      w1=${words[$((RANDOM % ${#words[@]}))]}
      w2=${words[$((RANDOM % ${#words[@]}))]}
      suffix=$(date +%s | tail -c 4)
      converted="${w1}-${w2}-${suffix}"
    fi
  fi

  feature_name="$converted"
fi

feature_name=$(echo "$feature_name" | cut -c1-50)

if [[ ! "$feature_name" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] && [[ ! "$feature_name" =~ ^[a-z0-9]$ ]]; then
  feature_name="feat-$(date +%s | tail -c 4)"
fi

target_branch="feature/$feature_name"
echo "分支名称: $target_branch"
```

```bash
# 校验无重名分支
if git show-ref --verify --quiet "refs/heads/$target_branch" 2>/dev/null; then
  echo "错误: 本地分支 $target_branch 已存在"
  exit 1
fi

if git ls-remote origin "refs/heads/$target_branch" 2>/dev/null | grep -q .; then
  echo "错误: 远端分支 $target_branch 已存在"
  exit 1
fi
```

```bash
# 自动 Sync 到最新 main
echo "同步到最新 main..."
git fetch origin main

if [[ "$branch_type" == "worktree" ]]; then
  source "$SHELL_DIR/context.sh"
  behind=$(sns_behind_count)
  if [[ "$behind" -gt 0 ]]; then
    if ! git rebase origin/main 2>/dev/null; then
      echo "错误: sync 失败 (rebase 冲突)"
      echo "可执行: git rebase --abort 放弃同步"
      exit 1
    fi
  fi
  echo "同步完成"
else
  # 在 main 分支上: 直接基于 origin/main
  git pull origin main
  echo "已更新 main"
fi
```

```bash
# 创建 feature 分支
git checkout -b "$target_branch"

echo ""
echo "=== Feature 分支已创建 ==="
echo "目标分支: $target_branch"
echo "所属工作区: $current_branch"
```

---

## 步骤 5: 写入 Plan Artifact 并锁定基线

用户确认后，写入结构化的 plan artifact 并持久化到项目目录。

```bash
# 写入 JSON artifact (运行时)
cat > "$plan_file" << PLAN_JSON
{
  "id": "${plan_id}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "scope": "${scope}",
  "description": "$(echo "$raw_description" | sed 's/"/\\"/g')",
  "acceptance_criteria": [],
  "steps": [],
  "branch": $([[ "$scope" == "large" ]] && echo "\"${target_branch}\"" || echo "null"),
  "status": "confirmed",
  "locked_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "task_prompt": "",
  "created_by": "agent"
}
PLAN_JSON

echo "Plan artifact 已写入: $plan_file"
```

```bash
# 持久化到 docs/exec-plans/active/
mkdir -p "docs/exec-plans/active"

cat > "docs/exec-plans/active/${plan_slug}.md" << PLAN_MD
# ${raw_description}

| 字段 | 值 |
|------|------|
| ID | ${plan_id} |
| 范围 | ${scope} |
| 状态 | confirmed |
| 时间 | $(date -u +%Y-%m-%dT%H:%M:%SZ) |
$(if [[ "$scope" == "large" ]]; then echo "| 分支 | \`${target_branch}\` |"; fi)

## Acceptance Criteria

<!-- Agent 生成后填入 -->

## 执行步骤

<!-- Agent 生成后填入 -->

## 任务提示

<!-- Agent 生成后填入 -->
PLAN_MD

echo "Plan 已持久化: docs/exec-plans/active/${plan_slug}.md"
```

```bash
# 输出执行指引
echo ""
echo "=== Plan 已锁定 ==="
echo "ID: $plan_id"
echo "范围: $scope"
echo "描述: $raw_description"

if [[ "$scope" == "large" ]]; then
  echo "分支: $target_branch"
  echo ""
  echo "接下来:"
  echo "  1. 在 $target_branch 上开发（可手动 commit）"
  echo "  2. 完成后执行: /sns-workflow:commit-push-pr"
  echo "  3. 系统将自动: PR 合并到 main → 删除 feature → 回到 $current_branch"
else
  echo ""
  echo "接下来:"
  echo "  1. 在 $current_branch 上直接开发（可手动 commit）"
  echo "  2. 完成后执行: /sns-workflow:commit-push-pr"
  echo "  3. 系统将自动: 推送到 main"
fi

sns_skill_end "success"
```
