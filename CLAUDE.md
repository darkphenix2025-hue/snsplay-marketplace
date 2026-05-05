# snsplay-marketplace

Claude Code plugin marketplace for productivity and development workflows.

## 快速开始

```bash
# 添加 marketplace
/plugin marketplace add darkphenix2025-hue/snsplay-marketplace

# 安装插件
/plugin install superpowers@snsplay-marketplace
/plugin install sns-workflow@snsplay-marketplace
```

## 架构

→ 详见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

```
snsplay-marketplace/
├── plugins/sns-workflow/   # 主工作流插件（22 个 skill、6 个 stage）
├── skills/                 # 共享技能库（24 个 skill）
├── docs/                   # 渐进式文档（分层架构）
└── tasks/                  # 任务管理系统
```

核心概念: Stage（阶段定义）+ Role（角色提示）+ Executor（执行器 = system_prompt + preset + model）→ Skill（可调用命令）

## 技能总览

→ 详见 [docs/references/skill-conventions.md](docs/references/skill-conventions.md)

| 类别 | 技能 | 命令 |
|------|------|------|
| Git 生命周期 | worktree/feature/hotfix/release | `/sns-workflow:<name>` |
| 提交合并 | commit-push-pr / merge-pr | `/sns-workflow:commit-push-pr` |
| SDLC 阶段 | requirements/plan/review/implement/rca | `/sns-workflow:<name>` |
| 编排器 | feature-implement / bug-fix | `/sns-workflow:<name>` |
| 工具 | status/sync/once/chatroom/publish | `/sns-workflow:<name>` |
| 文档 | doc-garden | `/sns-workflow:doc-garden` |

## 开发

→ 详见 [docs/references/development-guide.md](docs/references/development-guide.md)

```bash
# 本地开发（推荐）
cc --plugin-dir /projects/snsplay-marketplace/plugins/sns-workflow

# 调试
!`echo "Plugin root: ${CLAUDE_PLUGIN_ROOT}"`
```

## 文档地图

| 目录 | 内容 | 索引 |
|------|------|------|
| docs/design-docs/ | 设计决策、版本模型 | [index](docs/design-docs/index.md) |
| docs/exec-plans/ | 执行计划（active/completed） | [PLANS](docs/PLANS.md) |
| docs/references/ | Git 工作流、技能约定、开发指南 | [index](docs/references/index.md) |
| docs/product-specs/ | 产品规格 | [index](docs/product-specs/index.md) |
| docs/generated/ | 自动生成的文档 | — |

根级文档: [ARCHITECTURE](docs/ARCHITECTURE.md) · [DESIGN](docs/DESIGN.md) · [QUALITY](docs/QUALITY.md) · [SECURITY](docs/SECURITY.md)

## Notes

- Skills 使用 `bun` 运行时
- 任务支持并行执行（见 `parallel_groups`）
- 技能描述双语（中文）
- 每次代码修改后同步更新文档（由 doc-garden hook 提醒）
