# SNS-Workflow 架构

## 当前版本

sns-workflow 1.3.0 — Git 生命周期管理插件（精简版）

## 核心模型

```
main (x.y.z-dev.N)
  ├──► release/x.y.z (x.y.z-rc.N) ──► tag vX.Y.Z
  ├──► worktree-NNN ──► PR ──► main
  ├──► feature/* ──► PR ──► main
  └──► hotfix/x.y.z ──► tag vX.Y.(Z+1) ──► main
```

**五条路径**: main 直接提交、release 打预发布 tag、worktree 创建 PR、feature 创建 PR、hotfix 打正式 tag。

## 共享脚本

| 脚本 | 用途 |
|------|------|
| `scripts/version.sh` | 语义化版本号解析、校验、递进 |
| `scripts/context.sh` | 分支类型检测、工作区状态检查 |
| `scripts/doc-arch-template.sh` | 文档架构规则（必需目录/文件、check/fix/migrate） |
| `scripts/arch-lint.sh` | 六层架构检查函数库（可 source 供 arch-lint/drift-scanner 共用） |

## 技能分组（21 个）

### Git 生命周期（4）

| 技能 | 输入 | 输出 |
|------|------|------|
| `worktree` | 空闲标识 | 创建 `worktree-NNN` 分支 + worktree 目录 |
| `plan` | 空闲 worktree/main | 范围检测 → 生成计划产物 → large 时创建 feature 分支 |
| `hotfix` | 线上 tag | 创建 `hotfix/<version>` 分支 |
| `release` | 版本号 | 创建 `release/<version>` 分支 |

### 流水线（3）

| 技能 | 路由逻辑 |
|------|---------|
| `commit-push-pr` | 检测分支类型 → main 直接提交 / release 打 tag / 其他创建 PR |
| `merge-pr` | 获取待合并 PR → squash 合并 → 清理分支 → reset worktree |
| `publish` | 校验 release 分支 → 打正式 tag → 回流 main |

### 执行控制（1）

| 技能 | 用途 |
|------|------|
| `ralph-loop` | Ralph Wiggum 循环：持续检测 Harness Engineering 差距 → 自动触发开发 → 再验证，直到所有实践覆盖 |

### 运行时保障（5）

| 技能 | 审查/恢复/验证逻辑 |
|------|-------------------|
| `review` | 两视角交叉审查（安全+正确性 vs 架构+可维护性）→ 综合去重 → artifact |
| `heal` | 读取错误上下文 → 分类（auth/network/conflict 等 9 类）→ 分步恢复计划 |
| `ui-verify` | 页面快照基线化 → 变更比对 / Bug 复现取证 / Lighthouse 审计 → artifact |
| `dev-server` | per-worktree 开发服务器管理（自动检测项目类型 / 启动停止 / 端口分配 / 健康检查） |
| `qa-gate` | 多维度质量门禁（AC/review/UI/架构综合评分）→ PASS/WARN/FAIL → --auto 自主修复循环 |

### 可观测性（2）

| 技能 | 数据源 |
|------|--------|
| `status` | git 状态（分支、版本、worktree、提交历史） |
| `observe` | .snsplay/task/ 产物文件、调试日志、CLI 追踪、review/heal/ui-verify artifact |

### 架构/文档（3）

| 技能 | 检查项 |
|------|--------|
| `arch-lint` | types/scripts/tests/stages/prompts/skills 六层架构、循环依赖、非法导入 |
| `doc-garden` | docs/ 目录结构、CLAUDE.md 行数、index.md 索引、首次迁移 |
| `drift-scanner` | 多维度质量扫描（架构/文档/结构/CI）、加权评分、基线对比、PreToolUse commit 拦截 |

### 配置/同步（3）

| 技能 | 用途 |
|------|------|
| `setup` | 初始化插件配置 |
| `create-prompt` | 发现/列出/创建自定义 agent prompt（专注可复用角色，任务计划用 plan） |
| `sync` | 同步远端 main 到本地 worktree |

## 六层架构（代码组织）

| 层级 | 目录 | 依赖方向 |
|------|------|---------|
| 1. Types | `types/` | 无依赖 |
| 2. Scripts | `scripts/` | → types/ + 标准库 |
| 3. Tests | `scripts/__tests__/` | → scripts/ + types/ |
| 4. Stages | `stages/` | 只读（已移至 backup/） |
| 5. Prompts | `system-prompts/` | 只读（已移至 backup/） |
| 6. Skills | `skills/` | → scripts/（运行时） |

## 旧技能暂存

10 个 SDLC 技能（bug-fix / chatroom / dev-config / feature-implement / implement / once / plan / rca / requirements / review）及其依赖的 8 个 TypeScript 脚本、6 个 stage 定义、6 个角色提示、评审规则、Web UI 已移至 `backup/`。后续按需引入。
