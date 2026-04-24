---
name: sns-workflow:bug-fix-v2
description: Hotfix 分支内的修复技能 —— 只负责 hotfix 分支内的修复逻辑，不处理 sync/commit。
user-invocable: true
allowed-tools: Read, Write, Bash, Glob, Grep, Task, TaskOutput, AskUserQuestion
---

# Bug Fix 技能（v2）

在 hotfix/* 分支内执行漏洞修复。不涉及 sync、commit、PR 等外部操作。

---

## 步骤 1: 验证当前在 hotfix 分支

```bash
current_branch=$(git branch --show-current)
if [[ ! "$current_branch" =~ ^hotfix/ ]]; then
  echo "错误: 此技能仅在 hotfix/* 分支上使用 (当前: $current_branch)"
  exit 1
fi
echo "当前在 hotfix 分支: $current_branch"
```

---

## 步骤 2: 加载漏洞信息

从用户获取漏洞描述或读取 `hotfix/v*` 相关的 bug 报告文件。

---

## 步骤 3: 修复逻辑

1. 编写回归测试（先使测试失败）
2. 编写修复代码（使测试通过）
3. 运行完整测试套件验证无回归

---

## 步骤 4: 完成

```bash
echo "Hotfix 修复完成！"
echo "接下来: sns-workflow commit-push-pr"
```
