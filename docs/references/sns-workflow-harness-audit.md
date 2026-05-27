# sns-workflow 插件 — Harness Engineering 标准合规审计报告

> 本文档以 harness-engineering 学习档案（`/projects/todo/harness-engineering/`）中的
> 概念笔记、独立思考和翻译文章为权威来源，对 sns-workflow 插件 v1.3.0
> 的 26 项技能逐一进行标准合规检查。
>
> **生成日期**: 2026-05-19
> **审计范围**: `~/.claude/plugins/cache/snsplay-marketplace/sns-workflow/1.3.0/`
> **权威来源**: `concepts/*.md`（8 篇）、`thinking/*.md`（6 篇）、`works/*.md`（12+ 篇）

---

## 1. 审计方法论

| 维度 | 说明 |
|------|------|
| **权威来源** | harness-engineering 项目中的概念笔记定义标准，翻译文章提供实证 |
| **评分规则** | PASS（满足，有代码证据）/ PARTIAL（部分满足，有显著差距）/ FAIL（未满足）/ N/A（不适用） |
| **证据标准** | 每个 PASS 需有具体文件路径和行号；每个 FAIL/PARTIAL 需指出未满足的具体行 |
| **硬性要求** | 10 项（来自 concepts/、works/ 翻译的核心标准） |
| **强推荐** | 13 项（跨多文章验证的工程建议） |

---

## 2. 硬性要求审计（10 项）

### H1: Agent = Model + Harness 分解 ✅ PASS

**标准**: AI 编码系统必须分解为模型（LLM 推理）与 Harness（基础设施）两部分。

**检查证据**:
- 六层架构模型在 `arch-lint/SKILL.md` 第 12-21 行明确定义：`types → scripts → stages → system-prompts → skills`
- `types/stage-definitions.ts` 仅含类型定义，零业务逻辑
- 所有 `scripts/*.sh`（8 个 bash 文件）为纯确定性计算逻辑，不含 LLM 推理
- `skills/*/SKILL.md` 包含面向 Agent 的推理指令，将具体执行委托给脚本
- 边界清晰：脚本 = 确定性代码，技能 = Agent 指令依赖 LLM 推理

---

### H2: 仓库作为唯一记录系统 ✅ PASS

**标准**: 一切决策、规范、约定必须是版本控制的制品，对 Agent 而言"不在仓库里的东西不存在"。

**检查证据**:
- `doc-arch-template.sh` 第 6-31 行定义了 7 个必需文档目录和 5 个必需文件
- `doc-garden` 技能强制执行 docs/ 目录树结构（design-docs/、exec-plans/、references/、product-specs/、generated/）
- `plan` 技能将计划制品持久化到 `docs/exec-plans/active/`
- PostToolUse hook（`remind-doc-update.sh`）在每次 Edit/Write 后检查文档同步
- 所有技能产出均为 `.snsplay/task/` 下的 JSON 制品文件

---

### H3: AGENTS.md 硬限制（≤ 60 行，不得自动生成） ❌ FAIL

**标准**: AGENTS.md 必须 ≤ 60 行（HumanLayer 硬性上限），且不得自动生成。

**差距**:
1. `scripts/doc-arch-template.sh` 第 31 行：`SNS_DOC_CLAUDE_MD_MAX_LINES=150`，限制值为 150 而非 60
2. `skills/doc-garden/SKILL.md` 第 118 行和 `skills/drift-scanner/SKILL.md` 第 131 行均检查 150 行上限
3. `doc-arch-template.sh` 第 132-156 行的 `sns_doc_fix` 函数会自动生成 CLAUDE.md 内容
4. 第 152 行将 AGENTS.md 创建为 CLAUDE.md 的符号链接——本质上是自动生成的

**权威来源**: `concepts/04-agent-readability.md`（第 44 行引用 HumanLayer）；`references/articles.md`（文章 #5 HumanLayer）

---

### H4: 前馈（Guides）+ 反馈（Sensors）双维度 ✅ PASS

**标准**: 必须同时具备前馈和反馈，且计算型和推断型都要覆盖。

**覆盖矩阵**:

| | 计算型 | 推断型 |
|--|--------|--------|
| **前馈** | `doc-arch-template.sh` 脚手架、`setup` 初始化 | SKILL.md Agent 行为指导、`plan` AC 生成 |
| **反馈** | `arch-lint` 静态分析、`drift-scanner` 4 维扫描、`eval-harness` AC 执行、PreToolUse hooks | `review` 双视角 LLM 评审、`qa-gate` 多维度综合评判、`heal` 错误分类 |

**结论**: 四象限全覆盖。

---

### H5: Lint 错误必须嵌入修复指令 ⚠️ PARTIAL

**标准**: 错误信息必须包含自修复指令，使 Agent 无需查阅文档即可修正。

**差距**:
- **好的一面**: `drift-scanner/bin/scan-on-commit.sh` 第 138-148 行包含修复建议（如 `Run /sns-workflow:arch-lint to check`）；`doc-garden/bin/check-doc-arch.sh` 第 67 行包含 `Run /sns-workflow:doc-garden --fix`
- **不足**: `scripts/arch-lint.sh` 第 40 行 `"types/$base 不应从 $import_path 导入"`、第 68 行、第 108 行、第 132 行——这些核心违规信息只说"什么错了"，没说"怎么修"

**权威来源**: `concepts/02-mechanical-enforcement.md`（第 26-33 行，含修复指令示例）

---

### H6: Token 不可从沙箱访问 ⚠️ PARTIAL

**标准**: 访问令牌绝不能从沙箱内部访问。

**差距**:
- 未发现主动泄露 token 的行为
- `skills/heal/SKILL.md` 第 141 行处理认证错误时建议 `gh auth status`，不暴露凭证
- 脚本使用 `gh` CLI 处理认证，不直接读取 `GITHUB_TOKEN` 等环境变量
- **风险**: `scripts/skill-logger.sh` 第 67 行将参数 `"${args}"` 未脱敏直接写入 `~/.sns-workflow/skill-executions.log`——如果用户通过参数传入 token（如 `heal --token abc123`），会被记录到日志

---

### H7: 评估者与生成者分离 ⚠️ PARTIAL

**标准**: 自我评估不可靠——必须分离评估者与生成者。

**差距**:
- `review` 技能使用两个独立视角（安全+正确性 vs 架构+可维护性），SKILL.md 第 117-118 行声明"这是第二次独立审查"
- `qa-gate` 是独立技能，不生成代码
- **关键问题**: review 的两个视角运行在**同一个 Agent 会话和同一个 LLM 上下文**中——这不是真正的独立评估，而是同一个模型换不同 prompt 评估两次。真正分离需要不同的模型实例或不同的上下文

---

### H8: 渐进式披露优于巨型指令文件 ⚠️ PARTIAL

**标准**: AGENTS.md 应作为目录页而非百科全书，通过嵌套文档实现渐进式披露。

**差距**:
- 外部文档结构支持渐进式披露（design-docs/、exec-plans/、references/、product-specs/）
- 技能按需加载（运行时机制）
- **矛盾**: 单个 SKILL.md 文件极其巨大——`qa-gate` 784 行、`ralph-loop` 659 行、`eval-harness` 672 行——加载时全量进入上下文

---

### H9: 二元通过/失败优于数值评分 ❌ FAIL

**标准**: 评估应使用二元通过/失败判断，而非数值评分。

**差距**:
- `skills/qa-gate/SKILL.md` 第 337-406 行：计算加权数值评分（0-100），映射到 PASS/WARN/FAIL
- `skills/drift-scanner/SKILL.md` 第 341-349 行：计算数值评分（0-100），映射到 A/B/C/D 字母等级
- `skills/eval-harness/SKILL.md` 第 408 行：计算通过率百分比（≥80% PASS，≥50% PARTIAL）
- **核心问题**: 所有评估机制底层都是数值评分，只是最终映射到了分类结果。标准明确拒绝这种做法

---

### H10: 给目标而非状态转换 ⚠️ PARTIAL

**标准**: Agent 应接收目标和工具，自主决定实现路径，而非刚性状态机步骤。

**差距**:
- SKILL.md 格式普遍使用编号步骤（Step 1、Step 2...），整体结构类似状态机
- 但步骤内的 Agent 行为指导是目标导向的（如 plan SKILL.md 第 193 行"Agent 分析变更描述，推断验收标准"）
- **矛盾**: 格式是刚性步骤序列，步骤内内容是柔性目标——方向对了但格式不一致

---

## 3. 强推荐审计（13 项）

| ID | 推荐 | 评分 | 简注 |
|----|------|------|------|
| R1 | "无聊技术"偏好 | ✅ PASS | 全 bash + Python3 + git，无外来依赖 |
| R2 | 黄金法则 + 定期 GC | ⚠️ PARTIAL | drift-scanner 有 `.snsplay/principles.json` 机制，但默认不引导创建 |
| R3 | 快速迭代 | ✅ PASS | review 3 轮 fix、eval-harness 2 轮、qa-gate 3 轮、ralph-loop 可配置 |
| R4 | 反馈飞轮 | ✅ PASS | observe → heal → fix → measure 链完整 |
| R5 | Spec as Product | N/A | 适用于 Agent 驱动产品团队，不适用于插件本身 |
| R6 | 子 Agent 上下文防火墙 | ✅ PASS | 产物文件（`.snsplay/task/*.json`）实现有效的上下文隔离 |
| R7 | 能力/回归评估分离 | ✅ PASS | eval-harness = 能力；ui-verify + drift-scanner = 回归 |
| R8 | 从简单开始 | ⚠️ PARTIAL | 完整 26 技能套装交付，无最小子集引导文档 |
| R9 | Harness 生命周期园艺 | ⚠️ PARTIAL | 园艺被管理项目，未园艺自身（无技能废弃检测） |
| R10 | 三层最小可行 Harness | ⚠️ PARTIAL | 三层技能齐备，但 setup 过于简单，无分层引导 |
| R11 | Ashby 必要多样性 | ✅ PASS | 多维度独立约束提供充分多样性 |
| R12 | 上下文压缩 | ✅ PASS | 产物文件模式 + 按需加载 |
| R13 | API 缓存优化 | ⚠️ PARTIAL | 制品文件提供隐式缓存；无显式 API 响应缓存 |

---

## 4. 汇总评分

### 硬性要求

| 评分 | 数量 | 占比 |
|------|------|------|
| PASS | 3 (H1, H2, H4) | 30% |
| PARTIAL | 5 (H5, H6, H7, H8, H10) | 50% |
| FAIL | 2 (H3, H9) | 20% |

### 强推荐

| 评分 | 数量 | 占比 |
|------|------|------|
| PASS | 7 (R1, R3, R4, R6, R7, R11, R12) | 58% |
| PARTIAL | 5 (R2, R8, R9, R10, R13) | 42% |
| N/A | 1 (R5) | — |

### 总览

| 评分 | 数量 | 百分比 |
|------|------|--------|
| PASS | **10** | 43% |
| PARTIAL | **10** | 43% |
| FAIL | **2** | 9% |
| N/A | **1** | 4% |

---

## 5. 关键差距详细分析

### 5.1 H3 — AGENTS.md 60 行限制

**问题深度**: 这是 HumanLayer 的硬性要求，基于大规模 Agent 编码实践。150 行的 CLAUDE.md 会导致：
1. Agent 注意力分散——关键指令淹没在细节中
2. 维护困难——150 行难以在提交前人工审查
3. 上下文浪费——占用宝贵的 context window

**涉及文件**:
- `scripts/doc-arch-template.sh:31` — 常量定义
- `scripts/doc-arch-template.sh:132-156` — `sns_doc_fix` 自动生成逻辑
- `scripts/doc-arch-template.sh:152` — AGENTS.md 符号链接
- `skills/doc-garden/SKILL.md:118` — 150 行检查
- `skills/drift-scanner/SKILL.md:131` — 150 行检查

**建议修复方案**: 分层策略——AGENTS.md 手写 ≤ 60 行（导航索引），CLAUDE.md 独立维护 ≤ 150 行（项目规则），两者分离而非符号链接。`sns_doc_fix` 改为检查存在性而非自动生成内容。

---

### 5.2 H9 — 数值评分替代二元判断

**问题深度**: Bockeler 在反馈飞轮文章中明确指出数值评分的问题是——不同评估者对"7 分"和"8 分"的理解不同，导致不可比较。二元 PASS/FAIL 消除了标度主观性。

**涉及文件**:
- `skills/qa-gate/SKILL.md:337-406` — 加权数值评分（0-100）
- `skills/drift-scanner/SKILL.md:341-349` — 数值评分 → A/B/C/D
- `skills/eval-harness/SKILL.md:408` — 百分比通过率

**建议修复方案**: 每项检查改为独立 PASS/FAIL，综合结论也改为"ALL_PASS"或"FAIL + 列出未通过项"。可保留数值评分作为内部调试指标，但对外输出必须是二元的。

---

### 5.3 H5 — arch-lint 错误无修复指令

**问题深度**: Harness Engineering 的核心原则是"Agent 能自行修正"。如果 lint 错误不包含修复指令，Agent 需要：
1. 查阅文档理解错误含义
2. 自行推断修复方式
3. 可能引入新的错误

**涉及文件**:
- `scripts/arch-lint.sh:40` — types 层违规
- `scripts/arch-lint.sh:68` — scripts 层违规
- `scripts/arch-lint.sh:108` — 循环依赖违规
- `scripts/arch-lint.sh:132` — skills 层违规

**建议修复方案**: 每条违规追加修复建议。例如：`"types/$base 不应从 $import_path 导入 → 修复: 移除该 import 或将共享定义移到 types/ 目录下"`。

---

### 5.4 H7 — 双视角共享上下文

**问题深度**: 同一 LLM 在同一上下文中用不同 prompt 评估两次，不是真正的独立——模型会"看到"自己第一次的分析，产生确认偏差。

**涉及文件**:
- `skills/review/SKILL.md:117-182` — 双视角设计（但共享上下文）

**建议修复方案**: 将两个视角拆分为独立的 Agent 调用（使用 `Agent` 工具），或使用顺序执行但 B 看不到 A 的原始分析（只接收结论摘要）。

---

### 5.5 H6 — skill-logger 参数未脱敏

**问题深度**: 技能参数可能包含 token、密码、API key 等敏感信息，直接记录到日志文件是潜在的安全漏洞。

**涉及文件**:
- `scripts/skill-logger.sh:67` — `"${args}"` 直接写入日志

**建议修复方案**: 对 args 进行敏感词过滤：
```bash
_sanitized_args() {
  echo "$1" | sed -E 's/(--token|--secret|--password|--api-key|--key)[= ]+[[:alnum:]]+/\1=***REDACTED***/gI'
}
```

---

## 6. 权威来源引用索引

| 标准 | 权威来源文件 | 关键行 |
|------|-------------|--------|
| H1 (Model+Harness) | `concepts/06-harness-definition.md` | 全文 |
| H2 (Repo as record) | `concepts/01-repo-as-source-of-truth.md` | 全文 |
| H3 (AGENTS.md ≤60) | `concepts/04-agent-readability.md` | 第 44 行 |
| H4 (Feedforward+Feedback) | `references/articles.md` 文章 #2 Fowler | 2×2 矩阵 |
| H5 (Fix instructions) | `concepts/02-mechanical-enforcement.md` | 第 26-33 行 |
| H6 (Token security) | `works/anthropic-managed-agents-translation.md` | 安全边界段 |
| H7 (Evaluator separation) | `thinking/cross-article-insights.md` | 洞见 4 |
| H8 (Progressive disclosure) | `concepts/04-agent-readability.md` | 全文 |
| H9 (Binary pass/fail) | `works/langchain-agent-evaluation-checklist-translation.md` | 全文 |
| H10 (Goals not transitions) | `references/articles.md` 文章 #16 Symphony | 第 102-104 行 |
