# snsplay-marketplace

Claude Code plugin marketplace for productivity and development workflows.

## 快速开始

```bash
# 添加 marketplace
/plugin marketplace add darkphenix2025-hue/snsplay-marketplace

# 安装插件
/plugin install sns-workflow@snsplay-marketplace
```

## 架构

→ 详见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

```
snsplay-marketplace/
├── plugins/sns-workflow/   # 主工作流插件（18 个 skill）
├── backup/                 # 旧技能暂存（plugins/skills + SDLC 技能 + TS 脚本）
├── docs/                   # 渐进式文档（分层架构）
└── .claude-plugin/         # marketplace 注册
```

核心模型: Git 双线分支（main ↔ release）+ 多 worktree 并行开发 + tag 驱动发布

## 技能总览（18 个）

| 类别 | 技能 | 命令 | 用途 |
|------|------|------|------|
| Git 生命周期 | worktree / feature / hotfix / release | `/sns-workflow:<name>` | 分支创建与管理 |
| 流水线 | commit-push-pr / merge-pr / publish | `/sns-workflow:<name>` | 提交、PR 合并、发布 |
| 运行时保障 | review / heal / ui-verify | `/sns-workflow:<name>` | 交叉审查、错误恢复、UI 验证 |
| 可观测性 | status / observe | `/sns-workflow:<name>` | 项目状态、工作流运行指标 |
| 架构/文档 | arch-lint / doc-garden / drift-scanner | `/sns-workflow:<name>` | 架构检查、文档整理、漂移扫描 |
| 配置 | setup / create-prompt | `/sns-workflow:<name>` | 初始化、创建自定义 prompt |
| 同步 | sync | `/sns-workflow:sync` | 远端状态同步 |

## 开发

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
| docs/references/ | Git 工作流、开发指南 | [index](docs/references/index.md) |
| docs/product-specs/ | 产品规格 | [index](docs/product-specs/index.md) |
| docs/generated/ | 自动生成的文档 | — |

根级文档: [ARCHITECTURE](docs/ARCHITECTURE.md) · [DESIGN](docs/DESIGN.md) · [QUALITY](docs/QUALITY.md) · [SECURITY](docs/SECURITY.md)

## Notes

- Skills 使用 shell 脚本（version.sh / context.sh / doc-arch-template.sh）
- 五路分支路由: main / release / worktree / feature / hotfix
- 每次代码修改后同步更新文档（由 doc-garden hook 提醒）
- 旧技能暂存于 backup/（含旧 SDLC 技能 + 产品设计技能），后续按需引入
