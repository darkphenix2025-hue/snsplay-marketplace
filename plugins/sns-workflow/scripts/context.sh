#!/usr/bin/env bash
# sns-workflow 分支上下文识别脚本
# 所有涉及分支判定的技能 source 此脚本，统一口径

# 识别当前分支类型
# 返回: worktree | feature | release | hotfix | main | unknown
sns_branch_type() {
  local branch
  branch=$(git branch --show-current 2>/dev/null)

  case "$branch" in
    main)         echo "main" ;;
    worktree-*) echo "worktree" ;;
    feature/*)    echo "feature" ;;
    release/*)    echo "release" ;;
    hotfix/*)     echo "hotfix" ;;
    "")           echo "unknown" ;;
    *)            echo "unknown" ;;
  esac
}

# 当前工作区是否干净
sns_workdir_clean() {
  [[ -z $(git status --porcelain 2>/dev/null) ]]
}

# 当前 worktree 是否空闲
# 空闲 = 工作区干净 + 当前在 worktree-NNN 分支 + 与 origin/main 同步
sns_worktree_is_idle() {
  local branch
  branch=$(git branch --show-current 2>/dev/null)

  # 必须在 worktree 分支上
  [[ ! "$branch" =~ ^worktree- ]] && return 1

  # 工作区必须干净
  sns_workdir_clean || return 1

  # 必须与 origin/main 同步（无 ahead/behind）
  local ahead behind
  ahead=$(git rev-list --count "origin/main..HEAD" 2>/dev/null || echo "1")
  behind=$(git rev-list --count "HEAD..origin/main" 2>/dev/null || echo "1")
  [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]
}

# 获取活动中的 release 分支列表
# 返回: 本地 release/* 分支名，每行一个
sns_active_release_branches() {
  git branch --list 'release/*' --format='%(refname:short)' 2>/dev/null
}

# 获取当前分支的 behind 状态（落后 origin/main 多少提交）
sns_behind_count() {
  git rev-list --count "HEAD..origin/main" 2>/dev/null || echo "0"
}

# 获取当前分支的 ahead 状态（领先 origin/main 多少提交）
sns_ahead_count() {
  git rev-list --count "origin/main..HEAD" 2>/dev/null || echo "0"
}

# 校验当前分支是否为指定类型
# 用法: sns_require_branch <type>
# 返回: 0=匹配, 1=不匹配
sns_require_branch() {
  local required="$1"
  local actual
  actual=$(sns_branch_type)
  [[ "$actual" == "$required" ]]
}

# 判断当前是否在 main worktree 上
# main worktree = 在 main 分支上 + 工作区干净
# 用于限定 cron 自动化任务仅在 main worktree 运行，避免多 worktree 并发冲突
sns_is_main_worktree() {
  [[ "$(sns_branch_type)" == "main" ]] && sns_workdir_clean
}

# 尝试获取 cron 锁（原子操作）
# 用法: sns_cron_lock <lock-name>
# 返回: 0=获取成功, 1=锁已被占用
sns_cron_lock() {
  local lock_name="${1:-cron}"
  local lock_dir
  lock_dir="${SNS_CRON_LOCK_DIR:-.snsplay/task}/.cron-lock-${lock_name}"
  # mkdir -p 不是原子的，但 mkdir（无 -p）是原子的
  if mkdir "$lock_dir" 2>/dev/null; then
    echo $$ > "${lock_dir}.pid"
    return 0
  fi
  # 检查锁是否过期（60 分钟）
  local lock_age
  lock_age=$(( $(date +%s) - $(stat -c %Y "$lock_dir" 2>/dev/null || echo 0) ))
  if [[ "$lock_age" -gt 3600 ]]; then
    rm -rf "$lock_dir" "${lock_dir}.pid"
    mkdir "$lock_dir" 2>/dev/null && echo $$ > "${lock_dir}.pid"
    return 0
  fi
  return 1
}

# 释放 cron 锁
# 用法: sns_cron_unlock <lock-name>
sns_cron_unlock() {
  local lock_name="${1:-cron}"
  local lock_dir
  lock_dir="${SNS_CRON_LOCK_DIR:-.snsplay/task}/.cron-lock-${lock_name}"
  rm -rf "$lock_dir" "${lock_dir}.pid"
}
