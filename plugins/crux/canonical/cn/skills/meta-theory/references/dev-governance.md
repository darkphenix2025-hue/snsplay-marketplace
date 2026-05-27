# 开发治理流程 —— 完整规范（Type C）

> Type C（开发治理流程）的详细操作规范。
> `SKILL.md` 中的 Type C 部分是入口摘要；本文件包含完整流程。
> 理论来源见 `canonical/skills/meta-theory/references/meta-theory.md`。
> 执行 Type C —— 开发治理流程时阅读本文件。

## 1. AGENT 调用原则（不可协商）

**技能是编排层——永远不要硬编码特定 agent 名称。** 在需要 agent 的每个阶段，遵循 Fetch-first 模式：

```
需要 agent 做 X → 搜索谁声明了"Own X" → 调用最佳匹配
```

**调用决策模式**（适用于每次 agent 调用、每个阶段）：

| 步骤 | 行动 |
|------|--------|
| 1. 搜索 | 读取 `config/capability-index/meta-kim-capabilities.json`，然后运行时镜像，然后 `.meta-kim/state/{profile}/capability-index/global-capabilities.json` |
| 2. 匹配 | 将每个 agent 的"Own"边界与所需能力评分（3=完美 / 1-2=部分 / 0=无） |
| 3. 调用 | 3 → 直接调用 / 1-2 → 调用 + 标记缺口 / 0 → 检测到能力缺口 |

**⚠️ 铁律**：不要将 `call code-reviewer` 或 `call meta-prism` 写为硬编码步骤。描述**需要的能力**；让执行器在运行时通过搜索-匹配-调用模式发现**谁提供它**。

### Agent 拥有权规则

每个**可执行**任务必须有显式的 **agent 拥有者**。

仅**纯查询**可以绕过 agent 拥有权并直接回答。如果一个任务做了以下任何一项，它就**不是**纯查询：
- 修改文件/代码/配置
- 触发命令、网络调用或其他外部副作用
- 产生用于后续交接、审查或验证的持久制品
- 预期将进化写回馈入 agent/技能/契约资产

经验法则：

```
纯问题 → 可以直接回答
任何可执行/可交接的 → 必须有 agent 拥有者
```

### 能力缺口解决阶梯

当 Fetch 没有找到干净的拥有者时，按此顺序解决缺口：

1. **找到现有拥有者** → 分发给该拥有者
2. **持久的/重复的/项目特定缺口** → 先触发 Type B，创建或组合拥有者，然后分发
3. **紧急或一次性缺口** → 使用临时 `generalPurpose` 拥有者并附显式理由，然后在进化中重新审查

**无拥有者执行是非法的。** 即使是临时回退也必须被命名并作为拥有者追踪，而非作为匿名直接执行。

当选择步骤 2 时，治理运行必须显式记录工厂车道：

- `capabilityGapPacket`
- `orchestrationTaskBoardPacket`
- 当缺口通过执行 agent 创建或升级解决时的 `executionAgentCard`

### 协议优先规则

在第 4 阶段开始前，Thinking 必须为运行产生显式协议制品：
- `runHeader`
- `taskClassification`
- `fetchPacket`
- `cardPlanPacket`
- `dispatchEnvelopePacket`
- `orchestrationTaskBoardPacket`
- `dispatchBoard`
- `workerTaskPackets`
- `resultMergePlan`
- `reviewPacketPlan`
- `verificationPacketPlan`
- `summaryPacketPlan`
- `evolutionWritebackPlan`

如果这些协议制品不存在，运行尚未准备好执行。

对于 `governanceFlow` 中的 `complex_dev` 或 `meta_analysis`，机器验证的 JSON 制品还必须在执行前包含 **`intentPacket`**（`trueUserIntent`、`successCriteria`、`nonGoals`、`intentPacketVersion: v1`）和 **`intentGatePacket`**（`ambiguitiesResolved`、`requiresUserChoice`、`defaultAssumptions`、`pendingUserChoices`、`userLanguage`、`languageSource`、`nativeChoiceSurface`、`intentGatePacketVersion: v1`；如果 `requiresUserChoice` 为 true，则包含非空的 `pendingUserChoices[]`）——参见 `config/contracts/workflow-contract.json`（`protocols.intentPacket`、`protocols.intentGatePacket`、`runDiscipline.protocolFirst.intentPacketRequiredWhenGovernanceFlows` / `intentGatePacketRequiredWhenGovernanceFlows`）。

如果 `taskClassification.upgradeReasons` 包含 `owner_creation_required`，制品还必须在执行前包含 **`capabilityGapPacket`**。如果 `capabilityGapPacket.resolutionAction` 是 `create_execution_agent` 或 `upgrade_execution_agent`，制品必须在 Conductor 可以分发新拥有者前包含 **`executionAgentCard`**。

---

## 1B. 多迭代闭环（直到门控通过）

当一次通过后工作未完成（开放的审查发现、`verificationPacket.verified !== true` 或 `npm run meta:validate:run` 失败），将运行视为 **Ralph 式循环**，但不发明新的阶段名称：

1. **执行/修订**——解决最高严重度的开放发现；按需更新代码或文档。
2. **审查**——刷新 `reviewPacket` 和发现 `closeState` 转换（`open` → `fixed_pending_verify` 视情况而定）。
3. **验证**——刷新 `revisionResponses`、`verificationResults` 和 `closeFindings` 直到每个发现为 `verified_closed` 或 `accepted_risk`。
4. **摘要**——在设置 `publicReady=true` 前，将 `summaryPacket` 与 `config/contracts/workflow-contract.json` `runDiscipline.publicDisplayRequires` 对齐。
5. **验证**——运行 `npm run meta:validate:run -- <artifact.json>`；如果失败，运行 `npm run prompt:next-iteration -- <artifact.json>` 并将打印的检查清单反馈回编排器。

当 `validate:run` 通过**或**用户显式接受风险（附文档化的 `accepted_risk` 和诚实的 `publicReady=false`）时停止。

**会话恢复（API / 压缩 / 工具失败）：** 首先检查 `.meta-kim/state/{profile}/run-index.sqlite` 获取最新的已验证治理运行，然后加载治理制品作为事实来源。会话中断后，至少重新加载：`runHeader`、`taskClassification`、`intentPacket`、`intentGatePacket`（需要时）、`cardPlanPacket`、`dispatchEnvelopePacket`、`orchestrationTaskBoardPacket`、`capabilityGapPacket` / `executionAgentCard`（适用时）、`dispatchBoard`、`workerTaskPackets` / `workerResultPackets`、`reviewPacket`、`verificationPacket`、`summaryPacket`、`evolutionWritebackPacket`。如果存在本地 `compactionPacket`，仅作为连续性辅助使用；它永远不替代治理制品。在声称闭环前重新运行 `npm run meta:validate:run -- <artifact.json>`。相同的包列表由 `npm run prompt:next-iteration -- <artifact.json>` 在 **Minimal context reload** 下打印。

可选**软待办门控**（默认关闭）：运行 `validate:run` 时设置 `META_KIM_SOFT_PUBLIC_READY_GATES=1`。如果 `summaryPacket.publicReady` 为 true，则没有任何 `workerTaskPacket` 可以有 `taskTodoState: "open"`。如果不追踪待办，则省略 `taskTodoState`。参见 `config/contracts/workflow-contract.json` → `runDiscipline.runArtifactValidation.softPublicReadyTodoGate`。

可选**软评论审查门控**：运行 `validate:run` 时设置 `META_KIM_SOFT_COMMENT_REVIEW=1`。如果 `summaryPacket.publicReady` 为 true，则 `summaryPacket.commentReviewAcknowledged` 必须为 `true`。参见 `runDiscipline.runArtifactValidation.softCommentReviewGate`。

可选 Claude **Stop Hook**（项目默认关闭）：`META_KIM_STOP_COMPLETION_GUARD=hint` 在最后一条助手消息声称完成但没有治理线索时记录 stderr 提醒；`=block` 返回 `{"decision":"block",...}` 使模型继续。参见 `.claude/hooks/stop-completion-guard.mjs`。

**治理医生：** `npm run meta:doctor:governance` 检查契约可读性、Claude Hook 命令集、`npm run meta:check:runtimes` 以及对示例夹具的 `meta:validate:run`——在发布前或镜像漂移时使用。

---

## 2. 核心 8 阶段执行脊椎（详细）

| 阶段 | 名称 | 关键问题 |
|-------|------|-------------|
| 1 | **Critical** | 任务是什么？清晰吗？ |
| 2 | **Fetch** | 谁能做这个？ |
| 3 | **Thinking** | 我们应该怎么做？ |
| 4 | **Execution** | 委托给 agent |
| 5 | **Review** | 结果正确吗？ |
| 6 | **Meta-Review** | 审查标准本身合理吗？ |
| 7 | **Verification** | 修复真的解决了问题吗？ |
| 8 | **Evolution** | 应该保留什么结构性学习？ |

### 隐藏骨架状态模型

8 阶段脊椎是**人类可读的编排表面**。在其之下，Meta_Kim 可以维护一个**隐藏骨架状态**，使运行保持可治理而不将系统变成可见的官僚机构：

| 状态层 | 示例值 | 主要拥有者 | 存在原因 |
|-------------|----------------|---------------|---------------|
| `stageState` | `Critical -> Fetch -> Thinking -> Execution -> Review -> Meta-Review -> Verification -> Evolution` | Conductor | 规范阶段推进 |
| `controlState` | `normal / skip / interrupt / intentional-silence / iteration` | Conductor | 修改阶段出牌而不发明新的伪阶段 |
| `gateState` | `planning-open / planning-passed / review-open / verification-open / verification-closed / synthesis-ready` | Warden + Prism | 分离阶段完成与门控通过 |
| `surfaceState` | `debug-surface / internal-ready / public-ready` | Warden | 防止脏运行被展示为完成/公开 |
| `capabilityState` | `covered / partial / gap / escalated` | Scout + Artisan | 保持 Fetch 结果显式而非含糊 |
| `agentInvocationState` | `idle / discovered / matched / dispatched / returned / escalated` | meta-theory 技能 | 跟踪技能是否委托给 agent 还是尝试直接工作——执行分发器角色 |

**规则**：这是**仅限不可见骨架**。面向用户的工作流仍以阶段语言和具体交付物表达。状态标签用于支持门控、跳过、中断和进化日志——而非成为第二个产品界面。

### 用户语言规则

阶段名称保持规范英文协议标签（`Critical`、`Fetch`、`Thinking`、`Review` 等）。围绕这些标签的所有面向用户文本遵循用户的最新语言或显式语言偏好。不要将中文、英文或任何单一语言硬编码到选项标签、澄清问题、确认卡片或摘要中。在 `intentGatePacket.userLanguage`、`intentGatePacket.languageSource`、`cardDecision.userLanguage` 和 `deliveryShell.languageSource` 中记录语言决策。

### 牌治理模型

Meta_Kim 不再将**出牌**仅视为隐喻。在工程术语中：

- **出牌者主要拥有者**：`meta-conductor`
- **出牌者上报拥有者**：`meta-warden`
- **中断信号源**：`meta-sentinel`、`meta-prism`、`user`、`system`

这有意**不是**一个新 agent。它是叠加在 Conductor/Warden 之上的协议角色，使系统获得一个显式决策链：

1. **是否出牌**：`cardDecision`
2. **出给谁**：`cardAudience`
3. **何时出牌**：`cardTiming`
4. **使用哪个交付 Shell**：`deliveryShell`

### 牌决策对象

每次真实运行可以通过 `cardPlanPacket` 发出牌决策。每张牌记录：

- `cardId`
- `cardType`
- `cardIntent`
- `cardDecision`
- `cardAudience`
- `cardTiming`
- `cardShell`
- `cardPriority`
- `cardReason`
- `cardSource`
- `cardSuppressed`
- `suppressionReason`
- `deliveryShellId`
- `choiceSurface`
- `userLanguage`

牌族：

| 牌族 | 含义 |
|------------|---------|
| `info` | 信息/澄清/状态 |
| `action` | 路由到执行、审查、修复、回滚 |
| `risk` | 治理或安全干预 |
| `silence` | 故意不出牌/延期/安静保持 |
| `default` | 首选下一步或默认路径 |
| `upgrade` | 升级、交接或治理提升 |

### 沉默/不出牌规则

沉默是一等决策，不是缺失行动。

默认原则：

```text
如果没有明确证据表明干预更好，
优先不出牌/延期/故意沉默。
```

运行制品因此必须建模：
- `noInterventionPreferred`
- `silenceDecision`
- `interruptionJustified`
- `deferUntil`
- `reasonForSilence`

### 跳过/中断/覆盖规则

Meta_Kim 区分：

- **跳过**：当前步骤故意不出牌，因为已知情/已在上下文中/不适用
- **中断**：风险或紧急治理信号临时在默认队列前插入一张牌
- **覆盖**：治理规则改变默认路径（例如，验证关闭前阻止公开展示）
- **升级插入**：Warden / Sentinel / Prism 在链中插入治理拥有者

每次此类操作必须发出一个 `controlDecision`，包含：
- `decisionType`
- `skipReason`
- `interruptReason`
- `overrideReason`
- `insertedGovernanceOwner`
- `emergencyGovernanceTriggered`
- `returnsToStage`
- `rejoinCondition`

---

## 阶段 1：Critical 分析（详细）

### 任务分类路由

Meta_Kim 现在使用**两层分类器**，使触发决策可审查而非凭直觉：

| 层 | 字段 | 允许值 | 目的 |
|-------|-------|----------------|---------|
| 意图层 | `taskClass` | `Q / A / P / S` | 保留规范的查询/行动/规划/战略拆分 |
| 运行时层 | `requestClass` | `query / execute / plan / strategy` | 解释运行时看到的请求类型 |
| 治理层 | `governanceFlow` | `query / simple_exec / complex_dev / meta_analysis / proposal_review / rhythm` | 决定哪个执行路径和门控集必须运行 |

**分类输出字段**：
- `taskClass`
- `requestClass`
- `queryScope`（`current_project` | `all_projects`）
- `projectRef`（如 `project-abc123def456`）
- `registryStatus`（`known` | `prompt_join` | `joined` | `skipped`）
- `crossProjectReason`（当 `queryScope` = `all_projects` 时必需）
- `governanceFlow`
- `triggerReasons[]`
- `upgradeReasons[]`
- `bypassReasons[]`
- `ownerRequired`
- `decisionSource`
- `classifierVersion`

### 规范映射

| `taskClass` | `requestClass` | 默认 `governanceFlow` | 默认处理 |
|-------------|----------------|--------------------------|------------------|
| `Q` | `query` | `query` | 仅当纯查询条件全部满足时直接回答 |
| `A` | `execute` | `simple_exec` 或 `complex_dev` | 需要显式拥有者；执行前分类复杂度 |
| `P` | `plan` | `complex_dev` 或 `proposal_review` | 先规划，然后产生拥有者可路由的包 |
| `S` | `strategy` | `meta_analysis` 或 `rhythm` | Warden / Conductor 领导的治理路径 |

### 触发/升级/绕过理由

记录具体理由，而非感觉：

- `triggerReasons`：`multi_file`、`cross_module`、`external_side_effect`、`durable_artifact`、`owner_missing`、`cross_runtime_sync`、`security_sensitive`、`verification_required`、`writeback_candidate`、`user_explicit_review`
- `upgradeReasons`：`cross_system_scope`、`review_or_verify_required`、`owner_creation_required`、`parallel_merge_required`、`business_workflow_upgrade`、`security_gate_required`
- `bypassReasons`：`pure_query`、`read_only_explanation`、`existing_verified_artifact_reuse`

### 无 Agent 例外（严格）

唯一有效的无 agent 路径是：

```text
taskClass = Q
AND requestClass = query
AND governanceFlow = query
AND 无文件/代码/配置变更
AND 无外部副作用
AND 无持久制品/交接包需要
```

如果这些条件中任一失败，任务必须被视为 `A`、`P` 或 `S`，因此必须有 agent 拥有者。

### 越级自我反思门控

> 核心问题：**我应该做这个，还是应该分发它？**

自检清单：
- [ ] 当前角色是"执行层"吗？（是 → 越级嫌疑，应该分发到对应的执行 agent）
- [ ] 任务涉及写代码/修改文件吗？（是 → 必须委托给执行层；meta-theory 不直接执行）
- [ ] 我是否"方便地"在替执行层做决策？（是 → 仅提供约束；让执行层自主判断实现细节）
- [ ] 上一轮是否也做了类似任务？（是 → 检查是否形成了越级模式，记录疤痕）

越级判断：
```
如果自检有 ≥1 项命中 且 taskClass = A
  → 标记为"应分发任务"
  → 组装任务包（上下文 + 约束 + 交付物）
  → 交给 Conductor 编排 → 分发到执行层
  → 记录疤痕（如果确实发生了越级）
```

### 升级信号（预防性）

> 与越级检测（事后捕获违规）不同，升级信号让**被分发的 agent 自己**认识到它无法处理任务——在浪费精力之前。

分发到 agent 时，在任务包中包含此指令：

```
如果你检测到以下任何信号，立即停止并报告：
- 任务超出你声明的"Own"边界
- 同一子问题的多次失败尝试（>2 次）
- 你无法从上下文追踪的跨系统依赖
- 需要专门审查的安全敏感变更
- 不可逆操作（数据库迁移、生产部署）
```

Agent 升级响应格式：
```json
{
  "escalation": true,
  "reason": "为什么这超出了我的能力",
  "suggestedCapability": "需要什么类型的 agent/技能",
  "workCompletedSoFar": "在碰到墙壁前我成功做了什么"
}
```

收到升级信号后：重新进入 Fetch（阶段 2）寻找更有能力的 agent。

### 清晰度门控

| 状态 | 条件 | 行动 |
|-------|-----------|--------|
| **已确认** | 用户指定了文件路径或 ≥2 个交付物或说了"直接做这个" | → 阶段 2 |
| **已探查** | 需要范围或优先级澄清 | → 跟进探查（最多 2 轮） |
| **已假设** | 2 轮后仍模糊 | 记录假设，标记 `clarity: "assumed"`，→ 阶段 2 |

**跟进探查策略**：
- 第 1 轮：询问**范围**——"哪些场景需要支持？哪些可以延期？"
- 第 2 轮：询问**优先级**——"如果时间紧张，哪些部分可以砍掉？"
- 提前退出：第 1 轮已指定文件路径或 ≥2 个交付物 → 跳过第 2 轮

### 简化回推规则

在从 Critical 进入 Fetch 之前，检查：

- 如果存在比用户描述的更简单的方法，**显式说明并推荐**——当简单方法可行时不要静默执行复杂计划。
- 单次使用的代码不需要抽象，不可能的场景不需要错误处理，未被请求的"灵活性"不需要设计。
- 自测："一个资深工程师会说这过于复杂吗？"如果是，在分发前简化。

### 复杂度路由

| 文件变更 | 复杂度 | 执行路径 | 升级到 10 步？ |
|-------------|-----------|---------------|-------------------|
| 1 个文件，纯逻辑/样式/注释 | 简单 | Execution → Review → Verification → Evolution（4 个阶段，仍由拥有者驱动） | 否——8 阶段是最低要求；这 4 个阶段足够 |
| 2-5 个文件，1 个模块 | 中等 | 完整 8 阶段脊椎 | 否——8 阶段是中等复杂度的完整可执行链 |
| >5 个文件或跨系统或多团队 | 复杂 | 完整 8 阶段脊椎，带升级门控 | **是**——当以下情况升级到完整 10 步治理：(a) >5 个文件，(b) 检测到跨系统依赖，(c) 需要多团队交接，(d) 安全敏感变更，或 (e) 运行契约明确需要 11 步阶段（方向/规划/执行/审查/元审查/修订/验证/摘要/反馈/进化/镜像） |

**升级触发条件**（任一即足够）：
- 文件范围 > 5 个文件
- 检测到跨系统依赖（阶段 3 Thinking 识别跨模块边界的共享组件）
- 需要多团队交接（业务部门 + meta 部门协调）
- 安全敏感或权限关键的变更
- 业务运行契约明确需要 11 步阶段

**注意**：8 阶段脊椎是无论复杂度如何的**最低可执行链**。10 步治理是复杂场景的**升级层**——8 个阶段仍会运行，但扩展了方向细化、摘要和反馈阶段（在 Evolution 之前）。

### Critical 阶段输出

```json
{
  "taskClass": "A",
  "requestClass": "execute",
  "queryScope": "current_project",
  "projectRef": "project-abc123def456",
  "registryStatus": "known",
  "crossProjectReason": null,
  "governanceFlow": "complex_dev",
  "triggerReasons": ["multi_file", "durable_artifact"],
  "upgradeReasons": ["review_or_verify_required"],
  "bypassReasons": [],
  "requiresAgentOwner": true,
  "ownerRequired": true,
  "ownerPolicy": "existing-owner | create-owner-first | temporary-fallback-owner",
  "decisionSource": "classifier-v2",
  "classifierVersion": "v2",
  "skipLevel": "should-dispatch",
  "complexity": "medium",
  "clarity": "confirmed",
  "understanding": "对任务理解的一句话描述",
  "scope": {
    "mustHave": ["项目1", "项目2"],
    "deferLater": ["项目3"]
  }
}
```

---

## 阶段 2：Fetch —— 发现可用 Agent（详细）

**目的**：搜索其"Own"边界匹配所需能力的 agent/技能。

**⚠️ 按顺序执行所有 5 个步骤——不可跳过。**

**步骤 1 —— 本地 agent 扫描**：
```
Glob: .claude/agents/*.md
读取每个文件，验证它有 `name:` YAML frontmatter（有效 = 已注册 agent）
提取每个 agent 的"Own / Do Not Touch"边界
评分匹配："Own"是否覆盖所需能力？
```

**步骤 1.5 —— 全局能力搜索**（通过搜索索引的快速关键词匹配）：
```
如果在本地扫描中未找到能力：
  在 .meta-kim/state/{profile}/capability-index/ 中 Grep capability-search-index.tsv
  按关键词搜索（如 "review|audit"、"debug|error"、"frontend|ui"）
  TSV 格式：type <tab> key <tab> name <tab> description <tab> trigger <tab> section_headings
  每行匹配标识一个候选 agent/技能及其平台和 ID
  从描述和关键词评分匹配
```

**步骤 1.6 —— 技能协同发现**（与 agent 搜索并行运行，不推迟到 Evolution）：
```
使用与步骤 1-1.5 相同的能力关键词：
  过滤 type=skills 在 capability-search-index.tsv 中 Grep
  收集匹配的技能 ID 和描述
  记录在 fetchPacket.recommendedSkills 中（按子任务）：
    { "subTaskId": "task-001", "skills": ["coding-standards", "code-security"], "source": "search-index" }
  同时检查匹配 agent 的 YAML frontmatter 中的 recommended_skills 字段
    （由之前的 Evolution 运行预填充——提供更快的查找而无需重新搜索）
  合并两个来源：搜索索引发现 + agent 的 recommended_skills
```

**为什么步骤 1.6 在 Fetch 期间运行而非 Evolution**：第一次运行必须已经知道使用哪些技能。Evolution 仅缓存发现以便未来运行更快查找。第一次运行对技能无知 = agent 无缘无故地做了更差的工作。

**步骤 0.5 —— 项目图谱上下文**（自动检测，在步骤 1 之前运行）：
```
检查：目标项目根目录中是否存在 graphify-out/graph.json？
  如果是 →
    - 验证新鲜度：比较 graph.json mtime 与 git log 最后提交
    - 如果过期 → 运行 `graphify --update`（增量，SHA256 缓存）
    - 加载图谱元数据：节点数、边数、置信度分布
    - 质量门控：如果 AMBIGUOUS 节点 > 30% 或总节点 < 10 → 标记为低质量，agent 使用直接 Read 为主
    - 在 Fetch 输出中记录 graphContext 供下游阶段使用
  如果否 →
    - 对于 Meta_Kim 本身：使治理运行失败并要求 `npm run meta:graphify:check` / 图谱重建后再执行。
    - 对于外部目标项目：在 Fetch 输出中记录图谱缺失并决定任务是否需要图谱生成。
```

**步骤 2 —— 能力索引搜索**（如果本地无完美匹配）：
```
如果 config/capability-index/meta-kim-capabilities.json 缺失或过期
  → 先运行 npm run discover:global

如果 discover:global 列出的技能/agent 很少但任务需要 Meta_Kim 第三方技能（install-deps 列表）
  且 ~/.codex/skills 或 ~/.openclaw/skills 在此机器上为空
  → 操作者应运行 npm run meta:deps:install:all-runtimes（或 npm run meta:deps:install 仅限 Claude），然后再次 npm run discover:global

先读取 config/capability-index/meta-kim-capabilities.json
然后读取当前运行时镜像
然后读取 .meta-kim/state/{profile}/capability-index/global-capabilities.json
搜索声明所需能力的 agent/技能
评分匹配

如果 globalProjectRegistry 可用（~/.meta-kim/global/project-registry.sqlite）
  → 检查其他注册项目是否有相关能力
  → 在 fetchPacket 中记录 globalRegistryHits
  → 使用外部项目上下文时遵守 cross_project_readonly 记忆模式
```

**步骤 3 —— 外部技能发现**（如果本地 + 索引基线仍无完美匹配）：
```
调用 **findskill** 技能
在 Skills.sh 生态中搜索缺失能力
记录搜索了什么和发现了什么
```

**步骤 4 —— 专家生态回退**（如果外部搜索仍无清晰胜出者）：
```
搜索 Meta_Kim 已集成的已知专家生态：
- everything-claude-code agent
- gstack 专家技能
- 能力索引中其他全局安装的运行时原生 agent/技能
```

**步骤 5 —— 拥有者解析分支**（如果未找到匹配）：

**步骤 5a —— 输出 `capabilityGapPacket`（强制）：**
```json
{
  "capabilityGapPacket": {
    "gapCapability": "[能力描述]",
    "gapType": "durable | recurring | project-specific | one-off",
    "searchedSources": ["local-agents", "capability-index", "global-registry", "findskill", "specialist-ecosystem"],
    "bestPartialMatch": null,
    "resolutionAction": "pending_user_confirmation",
    "userConfirmationRequired": true
  }
}
```

**步骤 5b —— 用户确认门控：**
```
如果缺口是持久的/重复的/项目特定的
  → 询问用户："检测到能力缺口：{gapCapability}。触发 Type B 创建流水线？（是/否）"
  → 如果用户批准 → 在执行前触发 Type B 创建流水线
  → 如果用户拒绝 → generalPurpose 回退 + 需要 Evolution 跟进
否则（缺口是一次性的/紧急的）
  → 调用 Agent(subagent_type="generalPurpose") 或 Codex 默认子 agent 作为临时拥有者
  → 记录理由 + 需要 Evolution 跟进
```

**步骤 5c —— 在 `fetchPacket` 中记录缺口解析：**
```json
{
  "gapResolution": {
    "userAsked": true,
    "userResponse": "approved | declined | one-off-auto",
    "resolutionPath": "type-b | generalPurpose-fallback",
    "evolutionFollowUpRequired": true
  }
}
```

### 匹配评分

| 分数 | 含义 | 行动 |
|-------|---------|--------|
| 3 | 完美匹配——"Own"完全覆盖所需能力 | 直接调用 |
| 2 | 部分匹配——覆盖大部分，有一些缺口 | 调用 + 标记缺口 |
| 1 | 弱匹配——略微相关 | 调用 + 标记显著缺口 |
| 0 | 无匹配 | 检测到能力缺口 → 步骤 5 拥有者解析分支 |

### 拥有者解析规则

| 情况 | 解决方案 |
|----------|------------|
| 现有拥有者覆盖工作 | 分发给该拥有者 |
| 无拥有者，但缺口是重复的/战略性的/项目特定的 | 先创建或组合拥有者（Type B） |
| 无拥有者，缺口是一次性的且低风险 | 使用临时 `generalPurpose` 拥有者并标记为 Evolution 审查 |

临时回退是**过渡状态**，不是成熟的架构状态。

### 层级感知路由

> 不是所有任务都需要 Opus 级别的 agent。将任务复杂度匹配到 agent 权重以优化上下文消耗和速度。

在评分候选后，应用层级偏好：

| 任务复杂度 | 首选层级 | 理由 |
|----------------|---------------|-----------|
| 简单（1 个文件，纯逻辑） | 轻量 agent（如 `model: "haiku"`） | 快速、便宜、足够 |
| 中等（2-5 个文件） | 标准 agent（默认模型） | 平衡 |
| 复杂（>5 个文件，跨层） | 重量级 agent（如 `model: "opus"`） | 需要深度推理 |

层级选择规则：
```
如果 complexity = "simple" 且候选有轻量变体
  → 优先轻量变体（节省上下文，更快）
否则
  → 使用匹配到的默认 agent
```

这是一个**偏好**而非硬性规则——如果轻量 agent 升级（参见升级信号），重新分发到重量级版本。

### Fetch 阶段输出

```json
{
  "capabilityNeeded": "代码质量审查",
  "graphContext": {
    "available": false,
    "suggestedForProjectsWithMoreThan": 20,
    "path": null,
    "nodeCount": null,
    "edgeCount": null,
    "confidenceDistribution": null,
    "quality": null
  },
  "fetchPacket": {
    "projectsChecked": ["current_project"],
    "projectLocalSources": [".claude/agents", ".claude/skills"],
    "globalRegistryHits": [],
    "capabilityMatches": [
      { "name": "code-reviewer", "source": "global", "score": 3, "matchReason": "Own 覆盖代码质量审查" }
    ],
    "capabilityGaps": [],
    "graphSources": [],
    "knowledgeSources": []
  },
  "searchTrail": [
    "local-agents",
    "global-capability-index",
    "global-project-registry",
    "findskill",
    "specialist-ecosystem"
  ],
  "candidates": [
    { "name": "code-reviewer", "source": "global", "score": 3, "matchReason": "Own 覆盖代码质量审查" }
  ],
  "selected": { "name": "code-reviewer", "score": 3 },
  "capabilityGap": null,
  "ownerMode": "existing-owner",
  "createOwnerRecommended": false,
  "temporaryOwnerJustification": null,
  "fallbackUsed": false
}
```

---

## 阶段 3：Thinking —— 规划方法（详细）

**目的**：探索解决方案路径、识别风险、分解为子任务。此阶段桥接 Fetch 和 Execution。

### 步骤 1：选项探索
分析至少 2 条可能的解决方案路径：

| 路径 | 方法 | 优点 | 缺点 |
|------|----------|------|------|
| A | [方法描述] | [理由] | [理由] |
| B | [替代方法] | [理由] | [理由] |

### 步骤 2：风险识别

| 信号 | 类型 | 缓解 |
|--------|------|------------|
| 共享组件修改 | Risk 牌 | 继续前通知用户 |
| 涉及认证/权限逻辑 | Risk 牌 | 立即暴露 |
| 影响 >3 个文件 | 跨污染风险 | 标记为 Review |
| 未找到匹配的 agent | 能力缺口 | 记录 + 建议 Type B |

### 步骤 3：任务分解

将阶段 1 的任务拆分为独立子任务：

```json
{
  "subTasks": [
    {
      "id": 1,
      "description": "具体要做什么",
      "owner": "来自阶段 2 的 agent 名称",
      "ownerMode": "existing-owner | create-owner-first | temporary-fallback-owner",
      "parallel": true,
      "parallelGroup": "group-a",
      "dependsOn": [],
      "mergeOwner": "负责整合的 agent",
      "taskPacketId": "task-001",
      "fileScope": ["file-or-module-a", "file-or-module-b"],
      "constraints": ["边界1", "依赖1"],
      "recommendedSkills": ["skill-id-1", "skill-id-2"]
    }
  ]
}
```

`recommendedSkills` 来自 Fetch 步骤 1.6——通过搜索索引发现的技能 + agent 自己的 `recommended_skills` YAML 字段（由之前的 Evolution 运行缓存）。在 Execution 期间，在 agent 的分发提示中包含这些技能引用，以便 agent 在工作期间调用它们。

### 步骤 3.5：协议优先分发制品

Thinking 必须在任何 `Agent` 工具调用开始前锁定执行协议：

```json
{
  "taskClassification": {
    "taskClass": "A",
    "requestClass": "execute",
    "queryScope": "current_project",
    "projectRef": "project-abc123def456",
    "registryStatus": "known",
    "crossProjectReason": null,
    "governanceFlow": "complex_dev",
    "triggerReasons": ["multi_file", "durable_artifact"],
    "upgradeReasons": ["review_or_verify_required"],
    "bypassReasons": [],
    "ownerRequired": true,
    "decisionSource": "classifier-v2",
    "classifierVersion": "v2"
  },
  "runHeader": {
    "department": "团队或部门",
    "primaryDeliverable": "单一交付物名称",
    "audience": "结果面向谁",
    "freshnessRequirement": "新鲜度规则",
    "visualPolicy": "视觉策略",
    "handoffPlan": "交付链如何闭环"
  },
    "cardPlanPacket": {
    "dealerOwner": "meta-conductor",
    "dealerMode": "conductor-primary-warden-escalation",
    "cards": [
      {
        "cardId": "card-001",
        "cardType": "action",
        "cardIntent": "execute",
        "cardDecision": "deal",
        "cardAudience": "owner",
        "cardTiming": "next_stage",
        "cardShell": "agent_dispatch",
        "cardPriority": 8,
        "cardReason": "工作已准备好由拥有者执行",
        "cardSource": "meta-conductor",
        "cardSuppressed": false,
        "suppressionReason": "",
        "deliveryShellId": "shell-tech-detail",
        "choiceSurface": "conversation_fallback",
        "userLanguage": "match_latest_user_message"
      }
    ],
    "deliveryShells": [
      {
        "deliveryShellId": "shell-tech-detail",
        "shellType": "technical_detail",
        "presentationMode": "direct",
        "exposureLevel": "internal",
        "interventionForm": "agent_dispatch",
        "audience": "developer-owner",
        "contentBoundary": "仅实现包",
        "userLanguage": "match_latest_user_message",
        "languageSource": "latest_user_message_or_explicit_preference"
      }
    ],
    "silenceDecision": {
      "silenceDecision": "defer",
      "noInterventionPreferred": true,
      "interruptionJustified": false,
      "deferUntil": "verification-complete",
      "reasonForSilence": "验证待定时不再推送更好"
    },
    "controlDecisions": [
      {
        "decisionId": "ctl-001",
        "decisionType": "interrupt",
        "skipReason": "",
        "interruptReason": "security_risk",
        "overrideReason": "",
        "insertedGovernanceOwner": "meta-sentinel",
        "emergencyGovernanceTriggered": true,
        "returnsToStage": "verification",
        "rejoinCondition": "critical risk reviewed"
      }
    ],
    "defaultShellId": "shell-tech-detail"
  },
  "dispatchBoard": {
    "boardId": "dispatch-001",
    "goal": "一句话目标",
    "ownerResolution": "existing-owner | create-owner-first | temporary-fallback-owner"
  },
  "workerTaskPackets": [
    {
      "packetId": "task-001",
      "owner": "agent 名称",
      "ownerMode": "existing-owner",
      "dependsOn": [],
      "parallelGroup": "group-a",
      "mergeOwner": "agent 名称",
      "deliverableLink": "此包如何连接回主要交付物",
      "recommendedSkills": ["skill-id-1", "skill-id-2"]
    }
  ],
  "resultMergePlan": {
    "mergeOwner": "负责整合的 agent",
    "consolidationArtifact": "单一交付物制品"
  }
}
```

可并行化的独立工作必须标记为相同的 `parallelGroup`。任何未声明 `owner`、`dependsOn` 和 `mergeOwner` 的任务都未准备好执行。

### 步骤 3.6：分解接受门控

在继续步骤 4 之前，计划必须通过此门控：

| 检查 | 条件 | 失败行动 |
|-------|-----------|-------------|
| **多文件/多能力** | 任务跨越 >1 个文件或 >1 个能力维度 | 必须产生 >= 2 个 `workerTaskPackets` |
| **单包反模式** | 多文件/多能力任务仅产生 1 个包 | 拒绝——重新分解或证明单包确实足够（单文件、单能力、纯逻辑变更） |
| **包完整性** | 每个包有非空的 `owner`、`dependsOn`（或显式 `[]`）、`parallelGroup`、`mergeOwner` | 拒绝——填写缺失字段 |

单包理由仅在以下**全部**成立时有效：(1) 恰好 1 个文件，(2) 恰好 1 个能力维度，(3) 无跨模块影响，(4) 无持久制品交接。

输出：
```json
{
  "decompositionGate": {
    "packetCount": 2,
    "multiFileOrMultiCapability": true,
    "singlePacketJustification": null,
    "gateResult": "PASS"
  }
}
```

### 步骤 3.7：规划文件补充（强制）

**此步骤是补充，非替代。** 它不替代步骤 3-3.6 的任何协议制品。它在分发协议旁边创建持久规划文件，用于人类可见性和跨会话连续性。

安装 `planning-with-files` 技能时，先调用它（通过 Skill 工具 `/planning-with-files`）并让它的模板驱动文件创建。未安装时，使用以下模板手动创建文件。

**要创建的文件**（在项目根目录，不在技能目录）：

| 文件 | 目的 | 来源数据 |
|------|---------|-------------|
| `task_plan.md` | 阶段路线图、决策、错误 | 阶段 1-3 范围、分解、协议制品 |
| `findings.md` | 研究、发现、技术决策 | Fetch 结果、能力匹配、技能发现 |
| `progress.md` | 会话日志、测试结果、错误日志 | 所有阶段完成时的行动 |

**创建规则：**

1. `task_plan.md`——从阶段 1 范围填充目标；从步骤 3 分解填充阶段（每个 `workerTaskPacket` = 一个阶段）；从清晰度门控填充关键问题；从选项探索填充决策。
2. `findings.md`——从用户请求填充需求；从 Fetch 阶段 2 结果填充研究发现的发现；从步骤 3 选项探索填充技术决策；从能力索引匹配填充资源。
3. `progress.md`——创建会话头；将阶段 1-3 行动记录为阶段 1 条目。

**更新规则（在运行期间补充）：**

- 阶段 4（Execution）后：用 agent 输出、创建/修改的文件、测试结果更新 `progress.md`。
- 阶段 5（Review）后：用审查发现更新 `progress.md`；用发现的问题更新 `findings.md`。
- 阶段 6（Meta-Review）后：更新 `task_plan.md` 阶段状态。
- 阶段 7（Verification）后：用验证结果更新 `progress.md`。
- 阶段 8（Evolution）后：在 `task_plan.md` 标记所有阶段完成；在 `findings.md` 记录进化写回。

**Conductor 是唯一写入者。** 没有其他 agent 写入规划文件。子 agent 返回结果；Conductor（或充当 Conductor 的分发器线程）持久化它们。

**跳过条件**：仅当 `queryBypass: true`（纯查询、无文件修改）时跳过。对于所有有执行的 Type A/B/C/D/E 运行，此步骤是**强制的**。

### 步骤 4：`cardDeck`（阶段-牌节奏）+ 交付计划

Thinking 必须将计划转化为**`cardDeck`**——阶段-牌节奏的规范阶段 3 制品（序列/lane——不是遗留的"Planning/Guidance/Direction"牌名）。每个条目是一个**阶段-牌意图**（优先级、lane、跳过/中断 hook）。Conductor 拥有分发板上的具体出牌；Thinking 仅输出 `cardDeck` 约束和分解。

```json
{
  "cardDeck": [
    {
      "stage": "Thinking",
      "priority": 8,
      "laneIntent": "decompose-and-surface-risks",
      "skipCondition": "任务简单且已分解",
      "interruptTrigger": "security-risk or scope-drift"
    }
  ],
  "deliveryShellPlan": [
    {
      "audience": "user",
      "channel": "conversation",
      "shell": "structured-status"
    }
  ],
  "interruptChannels": [
    { "source": "sentinel", "severity": "critical", "action": "暂停并前置中断" },
    { "source": "prism", "severity": "high", "action": "在下一个执行阶段前插入" }
  ]
}
```

### 步骤 5：决策记录

```json
{
  "selected": "A",
  "reason": "为什么选择此路径而非替代方案",
  "rejectedOptions": [{ "path": "B", "reason": "为什么未选择" }],
  "risks": [{ "type": "shared-component", "mitigation": "通知用户" }]
}
```

### Thinking 阶段输出契约

```json
{
  "subTasks": [],
  "taskClassification": {},
  "runHeader": {},
  "cardPlanPacket": {},
  "dispatchBoard": {},
  "workerTaskPackets": [],
  "resultMergePlan": {},
  "cardDeck": [],
  "deliveryShellPlan": [],
  "interruptChannels": [],
  "reviewPlan": ["code-quality", "security"],
  "reviewPacketPlan": ["owner-coverage", "protocol-compliance", "quality-findings", "finding-closure-model"],
  "metaReviewGate": "complexity=complex OR abnormal review confidence",
  "verificationGate": "所有失败断言必须用新证据重新运行",
  "verificationPacketPlan": ["fixEvidence", "revisionResponses", "verificationResults", "closeFindings", "regressionGuard"],
  "summaryPacketPlan": ["verifyPassed", "summaryClosed", "deliverableChainClosed", "publicReady"],
  "evolutionWritebackPlan": ["writebackDecision", "agent-boundary", "skill", "contract", "scar"],
  "evolutionFocus": ["pattern reuse", "boundary drift", "process bottlenecks"]
}
```

---

## 阶段 4：Execution —— 委托给 Agent（详细）

**⚠️ 核心规则：meta-theory 不直接写代码。**

**编排**：Conductor 的任务板驱动执行。子任务通过 Fetch-first 模式（能力索引）发现的能力映射到执行 agent，而非按名称硬编码。Conductor 编排；执行 agent 执行——meta-agent 不自我执行业务逻辑。

### 步骤 1：调用阶段 2 选择的 agent

对阶段 3 的每个子任务，调用匹配的 agent：
```
Agent(
  subagent_type="<来自阶段 2 的选定 agent>",
  prompt="""
  Packet: [workerTaskPacket JSON]
  Task: [子任务描述]
  Constraints: [来自阶段 3 的边界]
  Deliverable: [预期输出格式]
  Graph context: [如果 graphContext.available，包含与此任务 fileScope 相关的压缩子图——节点拓扑、依赖边、AMBIGUOUS 节点的置信度说明。图谱上下文告诉事物在哪里；要知道它们如何工作，始终 Read 实际源文件。]
  """
)
```

### 步骤 2：并行/串行决策
- 无依赖边 + 文件范围不重叠 → **必须并行运行**
- 共享文件、显式依赖边或共享整合步骤 → **串行**
- 每个并行 lane 必须声明一个 `parallelGroup`
- 每个并行组必须声明一个 `mergeOwner`

### 步骤 2.5：按阶段顺序执行

执行必须遵守阶段 3 的**`cardDeck`**（阶段-牌序列/控制中断——委托给 Conductor 进行实际出牌）：
- 按约定顺序运行阶段，除非控制中断（沉默/跳过/风险）处于活动状态
- 过载规则触发时插入故意沉默
- 报告进度或交接结果时使用选定的交付 Shell

### 步骤 3：结果聚合
- 修改了哪些文件
- 需要解决哪些冲突
- 任何子任务失败 → 通过故障协议处理
- 每个结果通过 `WorkerResultPacket` 返回，不是自由形式的孤立输出

### 精准变更卫生（Karpathy 启发）

每个执行 agent 必须遵守以下约束：

- **只触及必须触及的。** 不要"改进"相邻代码、注释或格式。不要重构没坏的东西。匹配现有风格，即使你会用不同方式做。
- **只清理自己的烂摊子。** 如果你的变更导致导入/变量/函数未使用，移除它们。不要移除之前就存在的死代码，除非被明确要求——改为提及它。
- **可追溯性测试：** 每个变更的行必须能直接追溯到用户的请求。如果一行无法追溯，它不应该出现在 diff 中。
- **适时回推：** 如果存在比计划的更简单的方法，在执行前说出来。

---

## 阶段 5：Review —— 验证结果（详细）

**触发**：阶段 4 产生了代码变更或任何持久执行制品。如果阶段 4 两者都未产生，跳到阶段 6。

**⚠️ 执行者不自我审查。遵循 Agent 调用原则。**

### 步骤 1：越级回顾

检查：是否有人（包括我自己）做了本应该分发的工作？
- [ ] 谁写了这一轮的代码？（如果 meta-theory 直接使用了 Edit/Write → 越级）
- [ ] 是否跳过了所需的 agent？
- [ ] 阶段 1 的越级结果是否被遵守？

越级处理：
```
如果检测到越级 → 记录疤痕 → 评估影响 → 如果产生了影响 → 用 agent 重新验证
```

### 步骤 1.5：拥有者覆盖 + 协议合规审查

在内容质量审查开始前，检查执行契约本身：
- [ ] 每个可执行子任务是否有显式拥有者？
- [ ] 如果使用了临时回退拥有者，理由是否显式？
- [ ] 所有 `WorkerResultPackets` 是否映射回 `dispatchBoard` 和主要交付物？
- [ ] 每个并行组是否声明了 `mergeOwner`？
- [ ] 运行是否保持了一个统一的交付物而非漂移到分散的输出？

如果任一答案为否，Review 包必须记录**协议不合规**，即使实现质量看起来不错。

### 步骤 2：质量审查（动态，Fetch-first）

遵循**Agent 调用原则**（搜索 → 匹配 → 调用）：
```
→ 搜索：谁声明了"Own: 代码质量审查"？
→ 匹配：评分候选
→ 调用：选定的 agent
```

调用代码质量 agent 时，指定以下检查维度：
- **类型安全**：any / 隐式 any / 类型断言
- **错误处理**：try/catch 覆盖和回退策略
- **权限边界**：调用了哪些外部 API/文件系统/网络请求
- **代码复用**：重复逻辑、DRY 检测

### 步骤 3：安全扫描（动态，Fetch-first）

```
→ 搜索：谁声明了"Own: 安全分析"？
→ 匹配：评分候选
→ 调用：选定的 agent
```

调用安全 agent 时，指定以下检查维度：
- **硬编码秘密**：API key / token / password
- **未验证输入**：参数验证
- **注入风险**：SQL 注入 / XSS

### 步骤 4：UX 审查（对于 UI 相关变更）

如果文件涉及 UI/组件：
- 无障碍性（键盘导航 focus-visible、aria-label、aria-live）
- 加载状态（骨架屏 vs 纯旋转器）
- 响应性（移动端断点）

### 步骤 5：AI-Slop 检测（可选——用于 agent/系统定义）

```
→ 搜索：谁声明了"Own: 质量取证，AI-Slop 检测"？
→ 如果找到则调用
```

### Review 阶段输出

```json
{
  "skipLevelDetected": false,
  "skipLevelScar": null,
  "ownerCoverage": "PASS",
  "protocolCompliance": "PASS",
  "qualityGate": "FAIL",
  "revisionNeeded": true,
  "revisionRound": 1,
  "sourceProjects": ["project-abc123def456"],
  "crossProjectContaminationCheck": "pass",
  "temporaryOwnerFollowUp": [],
  "reviews": [
    { "type": "code-quality", "agent": "code-reviewer", "result": "PASS", "issues": [] },
    { "type": "security", "agent": "security-reviewer", "result": "FAIL", "issues": ["config.ts 中硬编码 API key"] }
  ],
  "findings": [
    {
      "findingId": "rev-001",
      "severity": "high",
      "owner": "security-reviewer",
      "sourceProject": "project-abc123def456",
      "summary": "config.ts 中硬编码 API key",
      "requiredAction": "移除秘密并从安全的运行时配置加载",
      "fixArtifact": "src/config.ts",
      "verifiedBy": "meta-prism",
      "closeState": "open"
    }
  ]
}
```

每个非通过问题必须成为**审查发现对象**。一旦修订和验证开始，自由形式的议题列表是不够的。

**质量门控规则——自动修复循环**：

```
第 1 轮：审查 agent 报告问题
  → 自动分发修复给原始执行 agent（附议题列表作为约束）
  → 对修复后的输出重新运行审查
第 2 轮：如果仍失败 → 附累积上下文再次自动修复
  → 重新运行审查
第 3 轮：如果仍失败 → 停止，通知用户进行手动决策
  → 包含：所有 3 轮的议题、尝试了什么、什么仍未修复
```

与简单"最多 2 轮"的关键区别：修复是**自动的**——审查 agent 将修复分发回执行 agent 而不等待用户输入。仅在 3 次自动修复失败后才上报给用户。

---

## 阶段 6：Meta-Review —— 审查审查标准（详细）

**触发**：复杂任务、异常通过率或用户明确要求更严格的治理。

Meta-Review **不**重新审查实现本身。它审查阶段 5 的审查标准是否足够强：

| 检查维度 | 问题 | 失败行动 |
|----------------|----------|-------------|
| 断言覆盖 | 审查是否覆盖了所有关键维度？ | 添加缺失断言并重新运行审查 |
| 断言强度 | 明显错误的结果是否仍能通过？ | 收紧弱断言并重新运行审查 |
| 标准一致性 | 标准是否与类似历史运行发生了实质性漂移？ | 记录漂移并请求 Warden 仲裁 |

**触发启发式**：
- 审查通过率 > 0.9 但输出仍有嫌疑
- 审查通过率 < 0.3 但输出看起来基本合理
- 安全敏感或跨层变更

---

## 阶段 7：Verification —— 确认修复（详细）

**触发**：阶段 5 或阶段 6 产生了修订工作。

验证是使用新证据的独立重新检查，不是基于信任的确认：

| 检查 | 方法 |
|------|--------|
| 议题闭环 | 重新运行最初失败的断言 |
| 回归保护 | 确认修复没有破坏相邻路径 |
| 新证据 | 引用当前文件/输出/日志，而非对变更的记忆 |

**验证输出**：
```json
{
  "verified": true,
  "remainingIssues": [],
  "evidence": ["当前文件或运行时证据"],
  "fixEvidence": ["提交 diff、文件路径或测试输出显示修复已落地"],
  "revisionResponses": [
    {
      "findingId": "rev-001",
      "actionId": "fix-001",
      "owner": "execution-owner",
      "responseType": "code-change",
      "status": "applied",
      "fixArtifact": "src/config.ts",
      "responseSummary": "移除硬编码 key 并切换到环境变量查找"
    }
  ],
  "verificationResults": [
    {
      "findingId": "rev-001",
      "verifiedBy": "meta-prism",
      "result": "pass",
      "evidence": ["src/config.ts 现在读取 process.env.API_KEY"],
      "closeState": "verified_closed"
    }
  ],
  "closeFindings": ["rev-001"]
}
```

如果验证失败，带累积的议题列表路由回 Execution。

**闭环规则**：
- `审查发现 -> 修订响应 -> 验证结果 -> closeFindings`
- 缺少任何一环意味着发现保持开放
- `closeFindings` 只能包含有匹配验证结果和新证据的发现 ID

### 回滚协议

当验证揭示修复造成了比解决的问题更多的损害，或风险超出原始任务范围时，调用回滚协议：

| 回滚级别 | 触发 | 行动 |
|---------------|---------|--------|
| **文件级** | 检测到单文件回归 | 从最后已知良好状态恢复特定文件（`git checkout HEAD~1 -- <file>`） |
| **子任务级** | 一个子任务的变更破坏了相邻路径 | 仅回滚该子任务的文件集；对剩余变更重新运行审查 |
| **完全回滚** | 跨 >3 个文件的跨污染；原始任务假设失效 | `git stash` 所有未提交的变更；以修订后的范围返回阶段 1 Critical |
| **部分回滚** | 部分子任务成功、部分失败 | 保留成功的子任务；回滚失败的；重新进入阶段 3 Thinking 重新分解失败部分 |

**回滚决策流程**：
```
验证失败
  → 计算受影响文件数
  → 如果 1 个文件：文件级回滚 → 仅对该文件重新运行阶段 4
  → 如果同一子任务中 2-3 个文件：子任务级回滚
  → 如果 >3 个文件或跨模块：通知用户 → 完全或部分回滚（用户决定）
```

**铁律**：回滚不是失败。回滚是系统展示它知道何时停止让事情变得更糟。没有回滚能力的系统是只能向灾难前进的系统。

### 摘要/公开展示包

8 阶段脊椎没有单独的"摘要阶段"，但业务运行在成为展示就绪前仍需要结构化的闭环对象。

```json
{
  "verifyPassed": true,
  "summaryClosed": true,
  "singleDeliverableMaintained": true,
  "deliverableChainClosed": true,
  "consolidatedDeliverablePresent": true,
  "publicReady": true,
  "sourceProjects": ["project-abc123def456"],
  "deliveryShellsUsed": ["shell-tech-detail"],
  "blockedBy": []
}
```

规则：
- `publicReady = true` 仅当所有公开展示条件为真
- 如果任何门控为 false，`blockedBy` 必须解释原因
- 摘要闭环是已验证运行的公开 Shell，不是验证的替代

---

## 阶段 8：Evolution —— 提取学习（详细）

每次任务后使用 **5+1 进化模型**：规范的 5 个结构维度，加上疤痕编码作为始终开启的叠加。

| 维度 | 检测什么 | 放大行动 |
|-----------|---------------|---------------------|
| 模式复用 | 这个解决方案能成为可复用模式吗？ | 提取为新技能/agent |
| Agent 边界 | 边界需要调整吗？ | 触发拆分/合并 |
| 节奏优化 | 交互路径能更短吗？ | 收紧阶段或控制牌触发条件（Conductor 拥有的出牌） |
| 流程瓶颈 | 哪个步骤最慢/最易出错？ | 调整编排 |
| 能力覆盖 | 发现了新缺口吗？ | 触发 Scout 或 Type B |
| **疤痕编码** | 越级/边界违规/流程缺口？ | 记录结构化疤痕 → 预防规则 |

### Agent 自测（"The Test" 模式）

每个 agent（治理 meta-agent 和执行 agent）应在 SOUL 定义中包含一个**自测**——一个简洁的、可检查的声明，定义 agent 何时正常工作：

```markdown
## The Test
[此 agent] 正常工作当：
- [具体、可观察的条件 1]
- [具体、可观察的条件 2]
```

审查（阶段 5）和元审查（阶段 6）使用每个 agent 的自测作为显式验证检查清单，用结构化的通过/失败标准替代主观的"看起来不错"判断。此模式受 Karpathy 的目标驱动执行原则启发——将定性标准转化为声明式的、可验证的目标。

### 放大操作

| 维度 | 检测 | 行动 |
|-----------|-----------|--------|
| 模式复用 | 发现可复用模式 | → 提取为技能/模板 → 注册 |
| Agent 边界 | 边界不合理 | → 触发拆分/合并 |
| 节奏优化 | 交互路径冗余 | → 更新阶段/控制触发条件（通过 Conductor） |
| 流程瓶颈 | 发现瓶颈 | → 调整阶段-牌优先级/序列（Conductor） |
| 能力覆盖 | 发现缺口 | → Scout 或 Type B |
| 疤痕 | 检测到问题 | → 记录疤痕 → 更新 Critical 检查清单 |

### 拥有者写回规则

每次完成的运行必须询问：

1. 现有拥有者被证明足够了吗？
2. 临时回退拥有者是否揭示了重复的能力缺口？
3. 是否应该更新 agent 边界、SOUL、技能负载或工作流契约？

如果运行对同一能力族多次使用了临时拥有者，Evolution 应默认为 **Type B 或拥有者-边界调整**，而非重复临时回退。

### 疤痕结构化记录

```yaml
scar:
  id: "{date}-{type}-{short-desc}"
  type: overstep | boundary-violation | process-gap | false-positive
  triggered_by: "{context}"
  what_happened: "一句话"
  root_cause: "为什么（非表面原因）"
  impact: none | degraded | recovered | critical
  prevention_rule: "下次的具体规则"
```

### 进化写回包

```json
{
  "ownerAssessment": "keep-existing | adjust-boundary | create-owner | retire-temporary-fallback",
  "writebackDecision": "writeback | none",
  "decisionReason": "为什么需要写回，或为什么此运行不需要写回是可接受的",
  "writebacks": [
    { "target": ".claude/agents/<agent>.md", "reason": "边界漂移" },
    { "target": ".claude/skills/<skill>/SKILL.md", "reason": "可复用执行模式" },
    { "target": "config/contracts/workflow-contract.json", "reason": "协议或门控细化" }
  ],
  "scarIds": ["2026-04-02-overstep-example"],
  "syncRequired": true
}
```

**规则**：Evolution 不可静默消失。每次运行必须输出以下之一：
- `writebackDecision = "writeback"` 并附具体目标，或
- `writebackDecision = "none"` 并附具体的 `decisionReason`

### 进化写回检查清单（标记 Evolution 完成前强制）

在标记 Evolution 完成前，遍历此检查清单并记录每项的结果：

```json
{
  "evolutionWritebackChecklist": {
    "agentBoundaryEdit": { "needed": false, "targets": [], "reason": "未发现边界问题" },
    "skillCreateOrUpdate": { "needed": false, "targets": [], "reason": "未发现可复用模式" },
    "capabilityIndexUpdate": { "needed": false, "targets": [], "reason": "未发现覆盖缺口" },
    "contractRefinement": { "needed": false, "targets": [], "reason": "不需要门控或协议细化" },
    "scarRecord": { "needed": false, "scarIds": [], "reason": "未检测到违规" },
    "syncRequired": { "needed": false, "reason": "未修改规范文件" }
  }
}
```

每项必须显式处理——省略某项等同于未声明的假设，违反了显式性设计原则。

### 进化制品存储

进化输出必须持久化到特定位置——而非漂浮在对话上下文中：

| 制品类型 | 存储位置 | 生命周期 |
|--------------|-----------------|-----------|
| **Agent 边界 / CT / DR 调整** | `canonical/agents/{agent}.md`（直接编辑） | 立即；主要进化目标——触发 `npm run meta:sync` |
| **新技能**（提取的） | `.claude/skills/{skill-name}/SKILL.md` | 永久；通过 skill-creator 创建，通过 Type D Review 验证 |
| **节奏优化** | 记录在 `config/contracts/workflow-contract.json` 或 Conductor 的牌组默认值中 | 立即；影响下次运行的分发板 |
| **能力缺口记录** | `canonical/capability-gaps.md` | 直到解决；Scout 监控并在填充时关闭 |

**进化规则——直接优于间接**：agent 定义**就是**记忆。发现缺口时，直接编辑具体 agent 的 SOUL.md。不要路由通过中间抽象层。memory/ 是 Claude Code 的会话记忆——不是 Meta_Kim 的进化机制。

**存储规则**：如果进化制品没有定义的存储位置，它不算"已捕获"。5+1 模型的放大行动仅在制品写入磁盘并索引后才算完成。

### 公开展示纪律

外部就绪输出是一个**门控状态**，不是讲故事的选择。在任何运行被视为公开完成之前，以下所有条件必须成立：

- `verifyPassed`
- `summaryClosed`
- `singleDeliverableMaintained`
- `deliverableChainClosed`
- `consolidatedDeliverablePresent`

如果其中任一为 false，运行可以产生内部笔记，但不得被框架为最终的公开交付物。

---

## 阶段脊椎 vs 控制牌

**8 阶段脊椎**（始终是骨干）：Critical → Fetch → Thinking → Execution → Review → Meta-Review → Verification → Evolution。`config/contracts/workflow-contract.json` 中的业务工作流**阶段名**（如 `direction`、`planning`、`execution`）是部门运行的独立词汇——不要将脊椎阶段重新标记为"Guidance / Direction / Planning cards"。

**控制/叠加牌**（节奏和安全——Conductor 出牌；不是第二脊椎）：

| 牌 | 触发条件 | 行动 |
|------|-------------------|--------|
| 范围收缩 | 仓库太大/重复文件名/分支历史 | 询问要变更哪个目标，然后继续 |
| 风险 | 共享组件/认证/全局接口/热门多编辑区域 | 暴露；可能触发中断路径 |
| 建议 | 用户犹豫；中断成本高 | 低成本的前进计划或故意沉默 |
| 沉默 | 连续 ≥3 轮高密度推送 | 暂停以消化 |
| 跳过 | 注意力成本 > 收益 | 简化或延期 |
| 中断 | 紧急或 Sentinel 关键 | 优先并重排 |
| 迭代 | 在约定轮次内验收未关闭 | 附显式门控循环；最多 3 次迭代，然后上报 Warden |
| **回滚** | 风险超出原始范围或影响范围扩大超出接受度 | 回退到最后稳定状态；重新进入阶段 3 Thinking 重新分解 |

**牌命名注意**：英文名称在本仓库中是规范的。使用 `canonical/skills/meta-theory/references/meta-theory.md` 作为理论来源，并与你的受众和区域对齐措辞。

脊椎覆盖参考（每个阶段的用途——不是独立的"牌"名称）：

| 脊椎阶段 | 角色 |
|-------------|------|
| Critical | 清晰度、分类、越级检查 |
| Fetch | 能力发现（搜索-匹配-调用） |
| Thinking | 选项、风险、分解 |
| Execution | 委托工作 |
| Review | 结果验证（Fetch-first 审查者） |
| Meta-Review | 触发时的审查之审查 |
| Verification | 修订后的新证据重新检查 |
| Evolution | 学习和疤痕 |

---

## "它不是什么"护栏

- Meta ≠ 角色命名：把某物叫做"前端 agent"不使它成为 meta；没有清晰边界的命名只是包装
- Meta ≠ 全能执行者 Meta：把所有职责塞进一个 agent 不是强大；清晰的分工才是成熟
- 组织镜像 ≠ metadata/ORM：它不是技术术语——它是 meta 之间协作关系、职责边界和谁先上场的架构设计方法
- Meta ≠ 框架复杂度：简单场景不需要 meta 分解；直接执行更高效——meta 是治理工具，不是装饰
- Meta ≠ 一劳永逸：meta 边界需要随系统进化而调整；它们不是定义一次就不变的
