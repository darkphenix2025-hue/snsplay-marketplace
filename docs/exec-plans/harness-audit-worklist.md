# sns-workflow 插件优化工作清单

> 基于 `docs/references/sns-workflow-harness-audit.md` 审计报告的执行计划。
> 按优先级分组：P0（硬性要求违规）→ P1（显著不足）→ P2（改进建议）。

---

## P0: 硬性要求违规（必须修复）

### W-01: AGENTS.md 行数限制从 150 改为 60

**关联标准**: H3（AGENTS.md ≤ 60 行，不得自动生成）
**审计报告章节**: §5.1

**涉及文件**:
| 文件 | 行号 | 当前值 | 目标值 |
|------|------|--------|--------|
| `scripts/doc-arch-template.sh` | 31 | `SNS_DOC_CLAUDE_MD_MAX_LINES=150` | 分层：AGENTS.md ≤60，CLAUDE.md ≤150 |
| `skills/doc-garden/SKILL.md` | 118 | 检查 150 行上限 | 分层检查 |
| `skills/drift-scanner/SKILL.md` | 131 | 检查 150 行上限 | 分层检查 |

**修复步骤**:
1. [ ] 在 `doc-arch-template.sh` 中增加 `SNS_DOC_AGENTS_MD_MAX_LINES=60` 常量
2. [ ] 修改 `sns_doc_check` 函数，分别检查 AGENTS.md 和 CLAUDE.md
3. [ ] 修改 `doc-garden/SKILL.md` 和 `drift-scanner/SKILL.md` 中的检查逻辑
4. [ ] 验证：`/sns-workflow:doc-garden --check` 报告 AGENTS.md ≤ 60 行

**注意事项**:
- AGENTS.md 与 CLAUDE.md 必须解耦（不再符号链接）
- AGENTS.md 应为手写导航文件（Agent 入口），CLAUDE.md 为项目规则文件

---

### W-02: AGENTS.md 停止自动生成

**关联标准**: H3（AGENTS.md 不得自动生成）

**涉及文件**:
| 文件 | 行号 | 问题 |
|------|------|------|
| `scripts/doc-arch-template.sh` | 132-156 | `sns_doc_fix` 自动生成 CLAUDE.md 内容 |
| `scripts/doc-arch-template.sh` | 152 | AGENTS.md 创建为 CLAUDE.md 的符号链接 |

**修复步骤**:
1. [ ] `sns_doc_fix` 改为仅创建空文件 + 模板头部注释，不填充自动生成内容
2. [ ] AGENTS.md 不再符号链接到 CLAUDE.md，改为独立文件
3. [ ] `sns_doc_migrate`（首次运行迁移）同样遵循此规则
4. [ ] 更新 `doc-garden/SKILL.md` 中关于"自动创建"的描述

**验证**: `doc-garden --fix` 后 AGENTS.md 应为空模板（或含最少占位内容），不是完整自动生成文档。

---

### W-03: 评估机制从数值评分改为二元通过/失败

**关联标准**: H9（二元通过/失败优于数值评分）
**审计报告章节**: §5.2

**涉及文件**:
| 文件 | 行号 | 当前行为 |
|------|------|----------|
| `skills/qa-gate/SKILL.md` | 337-406 | 加权数值评分 0-100 → PASS/WARN/FAIL |
| `skills/drift-scanner/SKILL.md` | 341-349 | 数值评分 0-100 → A/B/C/D |
| `skills/eval-harness/SKILL.md` | 408 | 百分比通过率 → PASS/PARTIAL/FAIL |

**修复步骤**:

**qa-gate**:
1. [ ] 每项 AC 检查改为 PASS/FAIL（不赋数值分）
2. [ ] review 维度改为 PASS/FAIL（无中间分值）
3. [ ] 最终结论: `ALL_PASS` 或 `FAIL (列出未通过项)`
4. [ ] 保留数值分作为可选 `--verbose` 输出（调试用，非默认）

**drift-scanner**:
1. [ ] 每个维度（arch/doc/struct/ci）改为独立 PASS/FAIL
2. [ ] 综合结论改为 `ALL_PASS` 或 `FAIL (列出未通过维度)`
3. [ ] 保留 A/B/C/D 作为 `--verbose` 输出

**eval-harness**:
1. [ ] 每个测试用例结果为 PASS/FAIL
2. [ ] 综合结论: `ALL_PASS` 或 `FAIL (N/M tests passed)`
3. [ ] 移除百分比阈值（≥80%/≥50%）

**验证**: 运行三个技能，确认默认输出不含数值评分，只有 PASS/FAIL。

---

## P1: 显著不足（建议修复）

### W-04: arch-lint 违规信息追加修复指令

**关联标准**: H5（Lint 错误必须嵌入修复指令）
**审计报告章节**: §5.3

**涉及文件**:
| 文件 | 行号 | 当前输出 |
|------|------|----------|
| `scripts/arch-lint.sh` | 40 | `"types/$base 不应从 $import_path 导入"` |
| `scripts/arch-lint.sh` | 68 | scripts 层违规（类似） |
| `scripts/arch-lint.sh` | 108 | 循环依赖违规 |
| `scripts/arch-lint.sh` | 132 | skills 层违规 |

**修复步骤**:
1. [ ] types 层违规追加: `→ 修复: 移除该 import，或将共享类型定义移到 types/ 目录下`
2. [ ] scripts 层违规追加: `→ 修复: 将 skills/ 的依赖提取到 scripts/ 层，避免反向依赖`
3. [ ] 循环依赖违规追加: `→ 修复: 提取共享逻辑到独立脚本文件，打破循环`
4. [ ] skills 层违规追加: `→ 修复: 使用 ${CLAUDE_PLUGIN_ROOT} 变量引用脚本路径，不硬编码路径`

**验证**: 故意制造 arch-lint 违规，确认输出包含修复建议。

---

### W-05: review 双视角拆分为独立上下文

**关联标准**: H7（评估者与生成者分离）
**审计报告章节**: §5.4

**涉及文件**:
| 文件 | 行号 | 问题 |
|------|------|------|
| `skills/review/SKILL.md` | 117-182 | 双视角共享同一 Agent 上下文 |

**修复步骤**:
1. [ ] 将 Perspective B 改为使用 `Agent` 工具启动独立子 Agent（上下文隔离）
2. [ ] Perspective B 只接收审查范围定义（变更文件列表 + AC），不接收 A 的分析结果
3. [ ] 综合阶段由主 Agent 读取两份独立报告后合并
4. [ ] 或者：保持当前结构但明确文档说明"上下文共享是已知折衷"，在 `qa-gate` 层面做最终独立评判

**验证**: review 运行后检查产物文件，确认两个视角的 JSON 报告内容无重叠。

---

### W-06: skill-logger 参数脱敏

**关联标准**: H6（Token 不可从沙箱访问）
**审计报告章节**: §5.5

**涉及文件**:
| 文件 | 行号 | 问题 |
|------|------|------|
| `scripts/skill-logger.sh` | 67 | `"${args}"` 未脱敏直接写入日志 |

**修复步骤**:
1. [ ] 增加脱敏函数:
   ```bash
   _sns_sanitize() {
     echo "$1" | sed -E 's/(--token|--secret|--password|--api-key|--key|--credential)[= ]+[^ ]+/\1=***REDACTED***/gI'
   }
   ```
2. [ ] 第 67 行改为: `_sns_log_write "... args\":\"$(_sns_sanitize "${args}")\",..."`
3. [ ] `sns_skill_step` 和 `sns_skill_error` 中的 `details` 参数同样脱敏
4. [ ] 检查 `snsplay-logger.ts` 是否有类似问题

**验证**: 传入 `--token test123` 参数，检查日志文件中是否显示 `***REDACTED***`。

---

### W-07: SKILL.md 文件拆分（降低单文件尺寸）

**关联标准**: H8（渐进式披露优于巨型指令文件）

**涉及文件**:
| 文件 | 当前行数 | 目标 |
|------|----------|------|
| `skills/qa-gate/SKILL.md` | ~784 | ≤ 200 行主文件 + 引用子文档 |
| `skills/ralph-loop/SKILL.md` | ~659 | ≤ 200 行主文件 + 引用子文档 |
| `skills/eval-harness/SKILL.md` | ~672 | ≤ 200 行主文件 + 引用子文档 |
| `skills/review/SKILL.md` | ~500+ | ≤ 200 行主文件 + 引用子文档 |

**修复步骤**:
1. [ ] 选择一个技能（建议从 `review` 开始）做试点拆分
2. [ ] 主 SKILL.md 保留: 概述 + 入口逻辑 + 步骤摘要（每步 1-2 行）+ 输出格式
3. [ ] 详细步骤内容移到 `skills/{name}/steps/` 子目录（如 `steps/step-1-context.md`）
4. [ ] bash 代码块移到 `skills/{name}/bin/` 下的独立脚本文件
5. [ ] 验证拆分后技能仍能正常执行
6. [ ] 将模式推广到其他大文件

**注意事项**:
- Claude Code 的 Skill 加载机制可能对引用子文档有限制，需先确认是否支持
- 如果不支持子文档引用，考虑将详细内容移到 `docs/` 目录，SKILL.md 中用路径引用

---

## P2: 改进建议（建议实施）

### W-08: setup 技能引导创建 principles.json

**关联标准**: R2（黄金法则 + 定期 GC）

**修复步骤**:
1. [ ] `setup` 技能增加交互式 principles.json 创建流程
2. [ ] 提供默认模板（含 3-5 条常见黄金法则）
3. [ ] 后续 `/sns-workflow:drift-scanner` 可直接使用

---

### W-09: 增加"最小可行子集"快速入门

**关联标准**: R8（从简单开始，按需增加）

**修复步骤**:
1. [ ] 在 CLAUDE.md 或 docs/ 中增加 Quick Start 段落
2. [ ] 定义最小子集: `setup` + `arch-lint` + `review` + `commit-push-pr` + `merge-pr`（5 个核心技能）
3. [ ] 按复杂度分级: L1（5 技能）→ L2（+ plan/qa-gate/drift-scanner）→ L3（全部 26 技能）

---

### W-10: SKILL.md 步骤格式改为目标块

**关联标准**: H10（给目标而非状态转换）

**修复步骤**:
1. [ ] 将编号步骤格式（Step 1/2/3...）改为目标块格式:
   ```
   ## 目标: 收集变更上下文
   **输入**: git diff、PR 信息
   **输出**: context JSON 文件
   **工具**: Bash、Read
   ```
2. [ ] Agent 自行决定使用哪些工具和步骤达成目标
3. [ ] 从 `plan` 或 `review` 技能开始试点

---

### W-11: 增加技能废弃检测

**关联标准**: R9（Harness 生命周期园艺）

**修复步骤**:
1. [ ] `drift-scanner` 或 `observe` 技能增加"技能使用频率"统计
2. [ ] 30 天未被调用的技能标记为"待审查"
3. [ ] 输出建议: `技能 X 已 30 天未使用，考虑移除或合并`

---

## 工作量估算

| 优先级 | 工作项 | 预估工作量 | 风险 |
|--------|--------|------------|------|
| P0 | W-01 AGENTS.md 行数限制 | 2h | 低 |
| P0 | W-02 AGENTS.md 停止自动生成 | 3h | 中（需修改模板逻辑） |
| P0 | W-03 评估改二元 | 4h | 中（三个技能，改动面广） |
| P1 | W-04 arch-lint 修复指令 | 1h | 低 |
| P1 | W-05 review 独立上下文 | 3h | 高（需改变 review 执行模型） |
| P1 | W-06 skill-logger 脱敏 | 1h | 低 |
| P1 | W-07 SKILL.md 拆分 | 6h | 高（需确认 Skill 加载机制兼容性） |
| P2 | W-08 principles.json 引导 | 2h | 低 |
| P2 | W-09 快速入门文档 | 2h | 低 |
| P2 | W-10 步骤格式改目标块 | 4h | 中（需逐个技能修改） |
| P2 | W-11 技能废弃检测 | 2h | 低 |
| **总计** | | **~30h** | |

---

## 建议执行顺序

```
W-01 ──→ W-02 ──→ W-04 ──→ W-06 ──→ W-03 ──→ W-05 ──→ W-07
 │         │        │        │        │        │        │
 │         │        │        │        │        │        └─→ W-08 ~ W-11
 │         │        │        │        │        │
 └─ P0 最高优先级   └─ P1    └─ P1    └─ P0    └─ P1    └─ P1
```

1. **第一轮（W-01 + W-02 + W-04）**: 低风险文档限制修复，建立信心
2. **第二轮（W-06 + W-03）**: 安全修复 + 评估机制重构
3. **第三轮（W-05 + W-07）**: 高风险结构性变更
4. **第四轮（W-08 ~ W-11）**: 渐进式改进
