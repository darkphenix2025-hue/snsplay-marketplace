#!/usr/bin/env bash
# cron-runner.sh — Cron 自动化任务包装器
#
# 限定 cron 任务仅在 main worktree 运行，避免多 worktree 并发冲突。
# 用法:
#   bash cron-runner.sh drift-scanner
#   bash cron-runner.sh doc-garden
#   bash cron-runner.sh drift-scanner --quiet
#
# 通过 CronCreate 或系统 crontab 调用:
#   cron: "*/30 * * * *"
#   prompt: "运行 /sns-workflow:drift-scanner --cron"

set -euo pipefail

SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")

source "$SHELL_DIR/context.sh"
source "$SHELL_DIR/skill-logger.sh"

# 1. 分支守卫：仅在 main worktree 运行 cron 任务
if ! sns_is_main_worktree; then
  current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
  echo "[cron] 跳过: 不在 main worktree (当前: $current_branch)"
  exit 0
fi

# 2. 解析参数
SKILL_NAME="${1:-drift-scanner}"
shift 1 2>/dev/null || true

# 3. 获取锁：防止同一时刻多 agent 并发
if ! sns_cron_lock "$SKILL_NAME"; then
  echo "[cron] 跳过: $SKILL_NAME 已有其他实例运行"
  exit 0
fi

# 确保退出时释放锁
trap 'sns_cron_unlock "$SKILL_NAME"' EXIT

# 4. 执行技能
echo "[cron] 开始执行: $SKILL_NAME (PID $$, branch: main)"
sns_skill_start "cron-$SKILL_NAME" "$*"

# 将执行委托给技能本身（Agent 在此处调用对应技能）
echo "[cron] 请执行: /sns-workflow:$SKILL_NAME --auto"
echo "[cron] 等待技能完成..."

sns_skill_end "success" "cron-$SKILL_NAME"
echo "[cron] 完成: $SKILL_NAME"
