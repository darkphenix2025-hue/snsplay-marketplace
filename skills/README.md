# 产品设计技能套件 (Product Design Skills)

完整的软件开发工作流技能集合，覆盖从需求到交付的全过程。

## 技能列表

### 核心工作流技能

| 技能 | 说明 | 命令 |
|------|------|------|
| 敏捷工作流 | 敏捷开发工作流编排 | `/agile-workflow` |
| 头脑风暴 | 扩展想法和探索解决方案空间 | `/brainstorming` |
| 任务拆分 | 将需求转化为可执行的任务 | `/task-decomposition` |
| TDD 工作流 | 测试驱动开发流程 | `/tdd-workflow` |
| 提交推送 PR | 代码提交和创建拉取请求 | `/commit-push-pr` |
| Git 清理 | 清理分支和 worktree | `/git-cleanup` |
| 架构决策 | 系统性架构评估 | `/architecture-decision` |
| 系统设计 | 诊断设计问题并提供指导 | `/system-design` |

### 产品设计流程技能

| 技能 | 说明 | 命令 |
|------|------|------|
| 需求分析 | 初步沟通用户需求 | `/requirements-analysis` |
| 架构拆分 | 将大需求拆分为架构清晰的功能单元 | `/architecture-decomposition` |
| 产品设计 | 根据需求分析拆分产品设计 | `/product-design` |
| 技术设计 | 确定技术规则及技术方案 | `/technical-design` |
| 任务管理 | 转化为技术开发工作列表 | `/task-management` |
| 测试样例 | 制定 TDD 测试用例 | `/test-cases` |
| 任务执行 | 循环执行任务直至测试通过 | `/task-execution` |
| 架构组装调试 | 分段组装并测试 | `/architecture-assembly` |

### PRD 与文档技能

| 技能 | 说明 | 命令 |
|------|------|------|
| PRD 生成 | 产品需求文档生成 | `/prd` |
| Ralph TUI PRD | TUI 界面 PRD 生成 | `/ralph-tui-prd` |
| Ralph TUI Beads | TUI 珠子生成 | `/ralph-tui-create-beads` |
| Ralph TUI Beads Rust | Rust 版本珠子生成 | `/ralph-tui-create-beads-rust` |
| Ralph TUI JSON | JSON 配置生成 | `/ralph-tui-create-json` |

## 工作流

```
头脑风暴 → 需求分析 → 架构拆分 → 系统设计 → 架构决策 → 产品设计 → 技术设计
    → 任务拆分 → 任务管理 → 测试样例 → TDD 工作流 → 任务执行 → 架构组装调试
    → 提交推送 PR → Git 清理

敏捷工作流：贯穿整个开发周期
PRD 技能：需求阶段的文档输出
```

## 使用方法

在各个技能目录下调用对应的技能命令，或按顺序执行完成完整开发流程。
