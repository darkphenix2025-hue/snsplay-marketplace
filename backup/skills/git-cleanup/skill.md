---
description: "清理 Git 中无需提交的 branch 和 worktree，释放开发空间"
origin: "User Request"
---

# git-cleanup

Slash command (`/git-cleanup`) 用于清理 Git 中无需提交的 branch 和 worktree，帮助释放开发空间并保持整洁的 Git 环境。

## 使用场景

- 完成临时功能开发后，需要清理不再需要的分支
- 使用 `git worktree` 进行多分支并行开发后，需要清理临时 worktree
- 定期维护 Git 仓库，清理废弃的分支和 worktree

## 命令语法

```bash
/git-cleanup [options]
```

### 选项

| 选项 | 说明 |
|------|------|
| (无参数) | 自动清理模式，直接执行清理无需确认 |
| `--branches` | 仅清理分支 |
| `--worktrees` | 仅清理 worktree |
| `--dry-run` | 预览将要删除的内容，但不实际执行 |
| `--interactive` | 启用交互式确认模式（删除前询问） |
| `--yes` | 显式启用自动确认（默认行为） |

## 清理流程

### 1. 状态检查报告

执行清理前，首先显示详细的检查报告：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 Git 清理工具 - 状态检查报告
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

【当前状态】
  • 当前分支：main
  • 主分支：  main
  • 当前 worktree: /path/to/repo

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 第一步：分支状态检查
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

【分支统计】
  • 本地分支总数：5
  • 已合并可删除：2
  • 远程已删除：  1
  • 保护分支数：  2

【已合并到主分支的分支（可删除）】
  - feature/login
  - feature/api

【远程已删除的分支（可删除）】
  - old-feature

【保护分支（不会删除）】
  - main (主分支)
  - develop (develop)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 第一步：Worktree 状态检查
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

【Worktree 统计】
  • Worktree 总数：  3
  • 活跃 worktree:   2
  • 可删除 worktree: 1

【可删除 Worktree（关联分支已不存在）】
  - /path/to/worktree:deleted-branch
```

### 2. 执行清理

自动执行删除操作，显示每个项目的删除结果：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🗑️  第二步：执行清理
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

【清理分支】
  🗑️  feature/login ... ✅
  🗑️  feature/api ... ✅
  🗑️  old-feature ... ✅

【清理 Worktree】
  🗑️  /path/to/worktree ... ✅
```

### 3. 清理后状态报告

清理完成后，显示最终状态：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ 第三步：清理后状态
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

【清理结果】
  • 共删除项目数：4

【当前状态】
  • 剩余分支数：2
  • 剩余 worktree: 2

【剩余分支】
  * main (当前)
    develop

【剩余 Worktree】
  * /path/to/repo:main (当前)
    /path/to/other:feature-branch

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✨ Git 清理完成！
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 执行脚本

```bash
#!/bin/bash

# git-cleanup.sh - 自动清理 Git 分支和 worktree
# 用法：bash git-cleanup.sh [options]
```

## 使用方法

### 作为技能调用

```bash
/git-cleanup
```

### 手动执行

将上述脚本保存为 `~/.claude/skills/git-cleanup/scripts/cleanup.sh`，然后执行：

```bash
# 预览模式 (不实际删除)
bash ~/.claude/skills/git-cleanup/scripts/cleanup.sh --dry-run

# 自动清理 (默认，无需确认)
bash ~/.claude/skills/git-cleanup/scripts/cleanup.sh

# 交互式清理 (删除前确认)
bash ~/.claude/skills/git-cleanup/scripts/cleanup.sh --interactive

# 仅清理分支
bash ~/.claude/skills/git-cleanup/scripts/cleanup.sh --branches

# 仅清理 worktree
bash ~/.claude/skills/git-cleanup/scripts/cleanup.sh --worktrees
```

## 安全检查清单

执行清理前，确认：
- [ ] 当前工作目录是 Git 仓库的根目录
- [ ] 已保存所有重要的未提交更改
- [ ] 确认要删除的分支确实不再需要
- [ ] 确认要删除的 worktree 对应的分支已经合并或删除

## 恢复方法

如果误删分支，可通过 reflog 恢复：

```bash
# 查看 reflog
git reflog

# 恢复分支
git branch <branch-name> <commit-hash>
```

## 注意事项

1. **worktree 删除限制**: 如果 worktree 包含未提交的更改，需要使用 `--force` 标志
2. **分支保护**: 主分支 (main/master) 和当前分支永远不会被删除
3. **远程追踪**: 删除本地分支前，会检查对应的远程分支是否仍然存在
4. **默认行为**: 默认自动执行清理，无需确认；使用 `--interactive` 启用确认模式
