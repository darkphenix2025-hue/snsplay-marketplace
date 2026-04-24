# Git Worktree 双线管理模型

## 分组策略

```
┌─────────────────────────────────────────────────────────────┐
│  发布线 (Release Line)                                      │
│  main ←→ production                                         │
│  职责：稳定版本管理、发布、热修复                            │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  开发线 (Development Line)                                  │
│  wt1, wt2 ←→ main                                           │
│  职责：功能开发、并行迭代                                   │
└─────────────────────────────────────────────────────────────┘
```

**管理原则**：发布线和开发线解耦，先保证发布线稳定，再处理开发线同步。

---

## 发布线状态机（main ↔ production）

### 状态定义

| 状态 | 描述 | 触发条件 |
|------|------|----------|
| **Sync** | main 和 production 同步 | 初始状态 / 完成同步后 |
| **MainUpdated** | main 有新提交 | 功能合并完成 |
| **ProdHotfixed** | production 有热修复 | 生产环境发现 bug |
| **BothUpdated** | 双方都有新提交 | main 开发中 + 生产 hotfix |

### 状态变迁规则

```
                    ┌──────────────────────────────────────┐
                    │           Sync 状态                  │
                    │   main === production (v1.0.0)       │
                    └──────────────────────────────────────┘
                                      │
            ┌─────────────────────────┼─────────────────────────┐
            │                         │                         │
            ▼                         ▼                         ▼
    ┌───────────────┐         ┌───────────────┐         ┌───────────────┐
    │ 规则 1         │         │ 规则 2         │         │ 规则 3         │
    │ Main 更新      │         │ Prod Hotfix   │         │ 双方都有更新   │
    └───────────────┘         └───────────────┘         └───────────────┘
            │                         │                         │
            ▼                         ▼                         ▼
    main → production        production → main          Step1: prod → main
    (git tag)                (git merge hotfix)         (保留 main 变更)
            │                         │                         │
            ▼                         ▼                         ▼
         Sync 状态                Sync 状态                Step2: main → prod
                                                           (git tag)
                                                                   │
                                                                   ▼
                                                              Sync 状态
```

---

## 详细规则

### 规则 1：Main 更新流程

**前提**：Sync 状态，main 有功能合并完成

```
时序：
main        ──────[C]─────────────────────→ [C]+[D] (新功能)
                                               │
                                               │ git tag -a v1.1.0
                                               ▼
production  ──────[C]─────────────────────→ [C]+[D] (已发布)

结果：Sync 状态
```

**命令**：
```bash
# 1. 确保 main 是最新的
git pull origin main

# 2. 打标签发布
git tag -a v1.1.0 -m "Release v1.1.0: feature-D"
git push origin v1.1.0

# 3. 生产环境部署
# (在 production 服务器)
git fetch origin
git checkout v1.1.0
```

---

### 规则 2：Production Hotfix 流程

**前提**：Sync 状态，production 发现紧急 bug

```
时序：
main        ──────[C]─────────←──────── [C]+[H1]
                                 (热修复同步)
                                │
                                │ git merge hotfix/bug-1
                                │
production  ──────[C]─────────→ [C]+[H1] (热修复)
                                │
                                │ git tag -a v1.0.1
                                ▼
                           production (v1.0.1)

结果：Sync 状态
```

**命令**：
```bash
# 1. 从 production 创建 hotfix 分支
git checkout production
git checkout -b hotfix/bug-1

# 2. 修复并提交
# (修复代码...)
git add . && git commit -m "fix: 紧急修复 XXX bug"

# 3. 合并到 production 并打标签
git checkout production
git merge hotfix/bug-1 --no-ff
git tag -a v1.0.1 -m "Hotfix v1.0.1"
git push origin production v1.0.1

# 4. ⚠️ 关键：同步回 main
git checkout main
git merge hotfix/bug-1 --no-ff
git push origin main
```

---

### 规则 3：双方都有更新流程

**前提**：BothUpdated 状态（最复杂场景）

```
时序：
main        ──────[C]─────┬─────→ [C]+[D]
                          │          │
                          │          │ Step1: 热修复
                          │          │ (保留 D)
                          │          ▼
                          │      [C]+[H1]+[D]
                          │          │
                          │          │ Step2: 发布
                          │          │ (包含 H1 和 D)
                          │          ▼
                          └──────→ [C]+[H1]+[D] (v1.1.1)

production  ──────[C]─────→ [C]+[H1] (热修复)
```

**命令**：
```bash
# ========== Step 1: hotfix → main (保留 main 变更) ==========
# 1.1 创建 hotfix 分支
git checkout production
git checkout -b hotfix/bug-1
# (修复代码...)
git commit -m "fix: XXX"

# 1.2 发布 hotfix
git checkout production
git merge hotfix/bug-1 --no-ff
git tag -a v1.0.1 -m "Hotfix"
git push origin production v1.0.1

# 1.3 ⚠️ 同步回 main (使用 rebase 保留 main 变更)
git checkout main
# main 当前有 D 提交，production 有 H1
# 需要 H1 和 D 都保留

# 方法 A: rebase (推荐，保持线性历史)
git rebase hotfix/bug-1
# 如有冲突，解决后 git rebase --continue

# 方法 B: merge (保留合并历史)
git merge hotfix/bug-1 --no-ff

git push origin main

# ========== Step 2: main → production ==========
git tag -a v1.1.1 -m "Release v1.1.1: hotfix + feature-D"
git push origin v1.1.1
```

---

## 开发线同步规则（wt1/wt2 ↔ main）

开发线的同步规则相对简单，遵循以下原则：

| 触发事件 | wt1 操作 | wt2 操作 |
|----------|----------|----------|
| main 更新 | `git rebase origin/main` | `git rebase origin/main` |
| wt1 完成 | `git merge wt1` → main | 等待，然后 rebase |
| wt2 完成 | 等待 | `git merge wt2` → main |

**关键**：开发线变更不直接影响 production，必须先合并到 main，经过验证后才能发布。

---

## 状态检查清单

### 每日开始工作前

```bash
# 检查发布线状态
git log --oneline -5 main
git log --oneline -5 production

# 检查是否同步
git rev-parse main~0 == git rev-parse production~0  # 应该相同

# 检查开发线状态
git worktree list
git branch -vv
```

### 发布前检查

```bash
# 确认 main 和 production 的关系
git log --oneline --graph main production~0

# 确认标签
git tag -l

# 确认无未提交变更
git status
```

---

## 决策树

```
当前状态？
│
├─ Sync → 有新功能？
│   ├─ 是 → 规则 1: main → production
│   └─ 否 → 等待
│
├─ MainUpdated → 生产有 bug？
│   ├─ 是 → 规则 3: 先 hotfix→main，再 main→production
│   └─ 否 → 规则 1: 发布 main
│
├─ ProdHotfixed → hotfix 已同步回 main？
│   ├─ 是 → Sync 状态
│   └─ 否 → 规则 2: 立即同步
│
└─ BothUpdated → 
    Step1: hotfix→main (保留 main 变更)
    Step2: main→production
```

---

## 常见错误与避免方法

| 错误 | 后果 | 正确做法 |
|------|------|----------|
| hotfix 后未同步回 main | main 丢失修复，下次发布会覆盖 | 规则 2 第 4 步必须执行 |
| 双方更新时直接覆盖 | 丢失 hotfix 或 main 变更 | 规则 3: 先 hotfix→main，再发布 |
| wt 直接发布 | 未经测试的代码上线 | 必须通过 main 主线 |
| 标签跳过版本 | 版本混乱 | 按顺序递增 v1.0.0 → v1.0.1 → v1.1.0 |
