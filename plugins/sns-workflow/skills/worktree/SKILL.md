---
name: sns-workflow:worktree
description: 从 main 创建 git worktree 分支（worktree-worker-NNN），目录 .claude/worktrees/worker-NNN。支持 --count 批量创建。是 feature/hotfix/sync 等 worktree 技能的入口。
user-invocable: true
allowed-tools: Bash
---

# 创建 git worktree

在 main 上创建新的 git worktree 分支，供 feature/hotfix/sync 等 worktree 技能使用。

**参数**:
- `--count <N>` — 批量创建 N 个 worktree（默认 1）
- `--suffix <name>` — 自定义目录名（如 `--suffix worker-auth`）

---

## 步骤 1: 验证环境

```bash
SHELL_DIR="${CLAUDE_PLUGIN_ROOT:-plugins/sns-workflow}/scripts"
source "$SHELL_DIR/context.sh"

current_branch=$(git branch --show-current)
branch_type=$(sns_branch_type)

# 必须在 main 上
if [[ "$branch_type" != "main" ]]; then
  echo "错误: worktree 命令仅在 main 分支上执行 (当前: $current_branch, 类型: $branch_type)"
  exit 1
fi

# 工作区必须干净
if ! sns_workdir_clean; then
  echo "错误: 工作区有未提交的更改，请先处理"
  git status --short
  exit 1
fi

# 确保 origin/main 已同步
git fetch origin main 2>&1
```

---

## 步骤 2: 解析参数

```bash
CREATE_COUNT=1
CUSTOM_SUFFIX=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --count)
      CREATE_COUNT="$2"
      shift 2
      ;;
    --suffix)
      CUSTOM_SUFFIX="$2"
      shift 2
      ;;
    *)
      echo "未知参数: $1"
      echo "用法: /sns-workflow:worktree [--count <N>] [--suffix <name>]"
      exit 1
      ;;
  esac
done

if [[ -z "$CUSTOM_SUFFIX" ]]; then
  echo "模式: 自动编号，创建 $CREATE_COUNT 个 worktree"
else
  echo "模式: 自定义后缀 $CUSTOM_SUFFIX"
fi
```

---

## 步骤 3: 查找下一个可用编号

```bash
# 收集当前已使用的 worker-NNN 编号
# 同时扫描 git worktree list 和文件系统目录（兼容已 prune 但目录仍存在的情况）
next_num=1
if [[ -z "$CUSTOM_SUFFIX" ]]; then
  max_num=0

  # 扫描 git worktree list
  while IFS= read -r wt_line; do
    wt_path=$(echo "$wt_line" | awk '{print $1}')
    dir_name=$(basename "$wt_path")
    if [[ "$dir_name" =~ ^worker-([0-9]+)$ ]]; then
      num=$((10#${BASH_REMATCH[1]}))
      [[ "$num" -gt "$max_num" ]] && max_num="$num"
    fi
  done < <(git worktree list 2>/dev/null)

  # 扫描文件系统目录（覆盖 worktree 已 prune 但目录残留的情况）
  if [[ -d ".claude/worktrees" ]]; then
    for dir in .claude/worktrees/worker-*; do
      dir_name=$(basename "$dir")
      if [[ "$dir_name" =~ ^worker-([0-9]+)$ ]]; then
        num=$((10#${BASH_REMATCH[1]}))
        [[ "$num" -gt "$max_num" ]] && max_num="$num"
      fi
    done
  fi

  next_num=$((max_num + 1))
fi
```

---

## 步骤 4: 创建 worktree

```bash
created=0
failed=0
created_list=""

while [[ "$created" -lt "$CREATE_COUNT" ]]; do
  if [[ -n "$CUSTOM_SUFFIX" ]]; then
    dir_name="$CUSTOM_SUFFIX"
    wt_branch="worktree-$CUSTOM_SUFFIX"
  else
    dir_name=$(printf "worker-%03d" "$next_num")
    wt_branch="worktree-$dir_name"
  fi

  wt_path=".claude/worktrees/$dir_name"

  # 检查冲突
  if [[ -d "$wt_path" ]]; then
    echo "跳过: 目录 $wt_path 已存在"
    if [[ -n "$CUSTOM_SUFFIX" ]]; then
      echo "失败: 自定义目录 $wt_path 已存在"
      failed=1
      break
    fi
    next_num=$((next_num + 1))
    continue
  fi

  if git show-ref --verify --quiet "refs/heads/$wt_branch" 2>/dev/null; then
    echo "跳过: 本地分支 $wt_branch 已存在"
    if [[ -n "$CUSTOM_SUFFIX" ]]; then
      echo "失败: 本地分支 $wt_branch 已存在"
      failed=1
      break
    fi
    next_num=$((next_num + 1))
    continue
  fi

  if git ls-remote origin "refs/heads/$wt_branch" 2>/dev/null | grep -q .; then
    echo "跳过: 远端分支 $wt_branch 已存在"
    if [[ -n "$CUSTOM_SUFFIX" ]]; then
      echo "失败: 远端分支 $wt_branch 已存在"
      failed=1
      break
    fi
    next_num=$((next_num + 1))
    continue
  fi

  # 创建 worktree
  mkdir -p .claude/worktrees
  if git worktree add -b "$wt_branch" "$wt_path" origin/main 2>&1; then
    echo "已创建: $wt_path (分支: $wt_branch)"
    created=$((created + 1))
    created_list="$created_list  $wt_path → $wt_branch\n"

    if [[ -z "$CUSTOM_SUFFIX" ]]; then
      next_num=$((next_num + 1))
    fi
  else
    echo "失败: 创建 $wt_path ($wt_branch)"
    failed=$((failed + 1))
    if [[ -n "$CUSTOM_SUFFIX" ]]; then
      break
    fi
    next_num=$((next_num + 1))
  fi
done
```

---

## 步骤 5: 输出汇总

```bash
echo ""
echo "=== worktree 创建完成 ==="

if [[ "$created" -gt 0 ]]; then
  echo "已创建 $created 个 worktree:"
  echo -e "$created_list"
  echo "接下来:"
  echo "  cd .claude/worktrees/<dir_name>   → 进入 worktree 目录"
  echo "  /sns-workflow:feature              → 创建 feature 分支开始开发"
else
  echo "未创建任何 worktree"
fi

if [[ "$failed" -gt 0 ]]; then
  echo "失败: $failed 个"
fi
```
