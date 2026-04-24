---
name: sns-workflow:feature-implement-v2
description: Feature 分支内的 TDD 实现循环 —— 只负责开发阶段的测试驱动开发，不处理 sync/commit。
user-invocable: true
allowed-tools: Read, Write, Bash, Glob, Grep, Task, TaskOutput, AskUserQuestion
---

# Feature 实现技能（v2）

在 feature/* 分支内执行 TDD 开发循环。不涉及 sync、commit、PR 等外部操作。

---

## 步骤 1: 验证当前在 feature 分支

```bash
current_branch=$(git branch --show-current)
if [[ ! "$current_branch" =~ ^feature/ ]]; then
  echo "错误: 此技能仅在 feature/* 分支上使用 (当前: $current_branch)"
  exit 1
fi
echo "当前在 feature 分支: $current_branch"
```

---

## 步骤 2: 加载开发需求

从用户获取 feature 需求或读取 `features/<name>/requirements.md`（如果存在）。

---

## 步骤 3: TDD 开发循环

执行标准红-绿-重构循环：

1. **红**: 编写失败的测试用例
2. **绿**: 编写最少代码使测试通过
3. **重构**: 清理代码，保持测试通过

```bash
# 示例循环
bun test --watch  # 持续运行测试
```

---

## 步骤 4: 验证测试

```bash
# 运行完整测试套件
bun test
echo "所有测试通过"
```

---

## 步骤 5: 完成

```bash
echo "Feature 实现完成！"
echo "接下来: sns-workflow commit-push-pr"
```
