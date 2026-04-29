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
    worker-*)  echo "worktree" ;;
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
  [[ ! "$branch" =~ ^worker- ]] && return 1

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
