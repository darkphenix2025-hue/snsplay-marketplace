#!/bin/bash

# git-cleanup.sh - 自动清理 Git 分支和 worktree
# 用法：bash git-cleanup.sh [options]
# 默认行为：自动清理已合并分支和关联分支已删除的 worktree

set -e

DRY_RUN=false
AUTO_YES=true
BRANCHES_ONLY=false
WORKTREES_ONLY=false

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --yes) AUTO_YES=true; shift ;;
        --interactive) AUTO_YES=false; shift ;;
        --branches) BRANCHES_ONLY=true; shift ;;
        --worktrees) WORKTREES_ONLY=true; shift ;;
        *) shift ;;
    esac
done

# 获取当前分支和主分支
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
MAIN_BRANCH=$(git remote show origin 2>/dev/null | grep -o 'HEAD branch: \K.*' || echo "main")
CURRENT_WORKTREE=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Git 清理工具 - 状态检查报告"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "【当前状态】"
echo "  • 当前分支：$CURRENT_BRANCH"
echo "  • 主分支：  $MAIN_BRANCH"
echo "  • 当前 worktree: $CURRENT_WORKTREE"
echo ""

# ========== 第一部分：原始状态报告 ==========
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 第一步：原始状态检查"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 获取所有本地分支
ALL_BRANCHES=()
while IFS= read -r branch; do
    if [[ -n "$branch" ]]; then
        ALL_BRANCHES+=("$branch")
    fi
done < <(git branch --format='%(refname:short)' 2>/dev/null)

# 显示原始分支列表
echo "【原始分支列表】"
for branch in "${ALL_BRANCHES[@]}"; do
    if [[ "$branch" == "$CURRENT_BRANCH" ]]; then
        echo "  * $branch (当前)"
    elif [[ "$branch" == "$MAIN_BRANCH" ]] || [[ "$branch" == "master" ]]; then
        echo "    $branch (主分支)"
    elif [[ "$branch" == "develop" ]]; then
        echo "    $branch (开发分支)"
    else
        echo "    $branch"
    fi
done
echo ""

# 已合并到主分支的分支
MERGED_BRANCHES=()
while IFS= read -r branch; do
    if [[ -n "$branch" ]] && \
       [[ "$branch" != "$CURRENT_BRANCH" ]] && \
       [[ "$branch" != "$MAIN_BRANCH" ]] && \
       [[ "$branch" != "master" ]] && \
       [[ "$branch" != "develop" ]]; then
        MERGED_BRANCHES+=("$branch")
    fi
done < <(git branch --merged "$MAIN_BRANCH" --format='%(refname:short)' 2>/dev/null)

# 远程已删除的分支 (gone branches)
GONE_BRANCHES=()
while IFS= read -r branch; do
    if [[ -n "$branch" ]] && \
       [[ "$branch" != "$CURRENT_BRANCH" ]] && \
       [[ ! " ${MERGED_BRANCHES[@]} " =~ " ${branch} " ]]; then
        GONE_BRANCHES+=("$branch")
    fi
done < <(git branch -vv 2>/dev/null | grep ': gone]' | awk '{print $1}' | tr -d '*')

# 保护分支（不会被删除的分支）
PROTECTED_BRANCHES=()
for branch in "${ALL_BRANCHES[@]}"; do
    if [[ "$branch" == "$CURRENT_BRANCH" ]] || \
       [[ "$branch" == "$MAIN_BRANCH" ]] || \
       [[ "$branch" == "master" ]] || \
       [[ "$branch" == "develop" ]]; then
        PROTECTED_BRANCHES+=("$branch")
    fi
done

# ========== 分类统计分析 ==========
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 第二步：分类统计分析"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "【分支统计】"
echo "  • 本地分支总数：${#ALL_BRANCHES[@]}"
echo "  • 已合并可删除：${#MERGED_BRANCHES[@]}"
echo "  • 远程已删除：  ${#GONE_BRANCHES[@]}"
echo "  • 保护分支数：  ${#PROTECTED_BRANCHES[@]}"
echo ""

if [[ ${#MERGED_BRANCHES[@]} -gt 0 ]]; then
    echo "【已合并到主分支的分支（可删除）】"
    for branch in "${MERGED_BRANCHES[@]}"; do
        echo "  - $branch"
    done
    echo ""
fi

if [[ ${#GONE_BRANCHES[@]} -gt 0 ]]; then
    echo "【远程已删除的分支（可删除）】"
    for branch in "${GONE_BRANCHES[@]}"; do
        echo "  - $branch"
    done
    echo ""
fi

if [[ ${#PROTECTED_BRANCHES[@]} -gt 0 ]]; then
    echo "【保护分支（不会删除）】"
    for branch in "${PROTECTED_BRANCHES[@]}"; do
        if [[ "$branch" == "$CURRENT_BRANCH" ]]; then
            echo "  - $branch (当前分支)"
        elif [[ "$branch" == "$MAIN_BRANCH" ]] || [[ "$branch" == "master" ]]; then
            echo "  - $branch (主分支)"
        else
            echo "  - $branch (develop)"
        fi
    done
    echo ""
fi

# ========== Worktree 检查 ==========
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 原始 Worktree 状态"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ALL_WORKTREES=()
ACTIVE_WORKTREES=()
DELETABLE_WORKTREES=()

while IFS= read -r line; do
    if [[ -n "$line" ]]; then
        WORKTREE_PATH=$(echo "$line" | awk '{print $1}')
        WORKTREE_BRANCH=$(echo "$line" | awk '{print $NF}')
        WORKTREE_HASH=$(echo "$line" | awk '{print $2}')

        ALL_WORKTREES+=("$WORKTREE_PATH:$WORKTREE_BRANCH")

        # 跳过当前 worktree
        if [[ "$WORKTREE_PATH" == "$CURRENT_WORKTREE" ]]; then
            ACTIVE_WORKTREES+=("$WORKTREE_PATH:$WORKTREE_BRANCH [当前]")
            continue
        fi

        # 检查关联分支是否存在
        if git show-ref --verify --quiet "refs/heads/$WORKTREE_BRANCH" 2>/dev/null; then
            ACTIVE_WORKTREES+=("$WORKTREE_PATH:$WORKTREE_BRANCH")
        else
            DELETABLE_WORKTREES+=("$WORKTREE_PATH:$WORKTREE_BRANCH")
        fi
    fi
done < <(git worktree list 2>/dev/null)

# 显示原始 worktree 列表
echo "【原始 Worktree 列表】"
if [[ ${#ALL_WORKTREES[@]} -gt 0 ]]; then
    for wt in "${ALL_WORKTREES[@]}"; do
        WORKTREE_PATH="${wt%%:*}"
        if [[ "$WORKTREE_PATH" == "$CURRENT_WORKTREE" ]]; then
            echo "  * $wt (当前)"
        else
            echo "    $wt"
        fi
    done
else
    echo "  无"
fi
echo ""

echo "【Worktree 统计】"
echo "  • Worktree 总数：  ${#ALL_WORKTREES[@]}"
echo "  • 活跃 worktree:   ${#ACTIVE_WORKTREES[@]}"
echo "  • 可删除 worktree: ${#DELETABLE_WORKTREES[@]}"
echo ""

# ========== 汇总报告 ==========
DELETABLE_BRANCHES=()
if [[ ${#MERGED_BRANCHES[@]} -gt 0 ]]; then
    DELETABLE_BRANCHES+=("${MERGED_BRANCHES[@]}")
fi
if [[ ${#GONE_BRANCHES[@]} -gt 0 ]]; then
    for b in "${GONE_BRANCHES[@]}"; do
        if [[ ! " ${DELETABLE_BRANCHES[*]} " =~ " $b " ]]; then
            DELETABLE_BRANCHES+=("$b")
        fi
    done
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 第三步：清理汇总报告"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  • 待删除分支数：   ${#DELETABLE_BRANCHES[@]}"
echo "  • 待删除 worktree: ${#DELETABLE_WORKTREES[@]}"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN 模式] 不会执行实际删除操作"
    echo ""
    exit 0
fi

if [[ ${#DELETABLE_BRANCHES[@]} -eq 0 ]] && [[ ${#DELETABLE_WORKTREES[@]} -eq 0 ]]; then
    echo "✅ 无需清理，所有分支和 worktree 都是活跃的"
    echo ""
    exit 0
fi

# ========== 第四部分：执行清理 ==========
if [[ "$AUTO_YES" == "false" ]]; then
    read -p $'\n是否执行清理？[y/N] ' -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "已取消清理操作"
        exit 0
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🗑️  第四步：执行清理"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

DELETED_COUNT=0

# 清理分支
if [[ "$WORKTREES_ONLY" == "false" ]] && [[ ${#DELETABLE_BRANCHES[@]} -gt 0 ]]; then
    echo "【清理分支】"
    for branch in "${DELETABLE_BRANCHES[@]}"; do
        echo -n "  🗑️  $branch ... "
        if git branch -D "$branch" 2>/dev/null; then
            echo "✅"
            ((DELETED_COUNT++)) || true
        else
            echo "❌ 失败"
        fi
    done
    echo ""
fi

# 清理 worktree
if [[ "$BRANCHES_ONLY" == "false" ]] && [[ ${#DELETABLE_WORKTREES[@]} -gt 0 ]]; then
    echo "【清理 Worktree】"
    for wt in "${DELETABLE_WORKTREES[@]}"; do
        WORKTREE_PATH="${wt%%:*}"
        echo -n "  🗑️  $WORKTREE_PATH ... "
        if git worktree remove "$WORKTREE_PATH" 2>/dev/null; then
            echo "✅"
            ((DELETED_COUNT++)) || true
        elif git worktree remove --force "$WORKTREE_PATH" 2>/dev/null; then
            echo "✅ (force)"
            ((DELETED_COUNT++)) || true
        else
            echo "❌ 失败"
        fi
    done
    echo ""
fi

# ========== 第五部分：清理后状态 ==========
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 第五步：清理后状态"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 获取清理后的分支状态
REMAINING_BRANCHES=()
while IFS= read -r branch; do
    if [[ -n "$branch" ]]; then
        REMAINING_BRANCHES+=("$branch")
    fi
done < <(git branch --format='%(refname:short)' 2>/dev/null)

# 获取清理后的 worktree 状态
REMAINING_WORKTREES=()
while IFS= read -r line; do
    if [[ -n "$line" ]]; then
        WORKTREE_PATH=$(echo "$line" | awk '{print $1}')
        WORKTREE_BRANCH=$(echo "$line" | awk '{print $NF}')
        REMAINING_WORKTREES+=("$WORKTREE_PATH:$WORKTREE_BRANCH")
    fi
done < <(git worktree list 2>/dev/null)

echo "【清理结果】"
echo "  • 共删除项目数：$DELETED_COUNT"
echo ""

echo "【当前状态】"
echo "  • 剩余分支数：${#REMAINING_BRANCHES[@]}"
echo "  • 剩余 worktree: ${#REMAINING_WORKTREES[@]}"
echo ""

echo "【剩余分支】"
for branch in "${REMAINING_BRANCHES[@]}"; do
    if [[ "$branch" == "$CURRENT_BRANCH" ]]; then
        echo "  * $branch (当前)"
    else
        echo "    $branch"
    fi
done
echo ""

if [[ ${#REMAINING_WORKTREES[@]} -gt 0 ]]; then
    echo "【剩余 Worktree】"
    for wt in "${REMAINING_WORKTREES[@]}"; do
        if [[ "$wt" == "$CURRENT_WORKTREE"* ]]; then
            echo "  * $wt (当前)"
        else
            echo "    $wt"
        fi
    done
    echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Git 清理完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
