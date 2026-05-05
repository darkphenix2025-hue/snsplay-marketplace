# SNS-Workflow 技能开发与改造计划

> **基于**: `workflow-development-spec.md` + `versioning_guide.md` + `test-plan.md`
> **创建日期**: 2026-04-25
> **最后更新**: 2026-04-25

---

## 一、目标与范围

本计划聚焦以下 8 个与版本工作流直接相关的技能：

- `sns-workflow:setup`
- `sns-workflow:status`
- `sns-workflow:sync`
- `sns-workflow:feature`
- `sns-workflow:hotfix`
- `sns-workflow:release`
- `sns-workflow:publish`
- `sns-workflow:commit-push-pr`

目标不是“补齐命令”，而是让这些技能与当前统一模型完全一致：

- 正式线上版本以 `tag vX.Y.Z` 为唯一事实来源
- `main` 表示未来开发态，不直接代表线上版本
- `release/x.y.z` 表示候选发布态
- `hotfix/x.y.z` 只能从正式 tag 派生
- `commit-push-pr` 负责按上下文路由到 worktree / feature / hotfix 流程

---

## 二、现状差距评估

### 2.1 技能现状矩阵

| 技能 | 当前状态 | 主要问题 | 改造优先级 |
|------|----------|----------|------------|
| `setup` | 已实现 | 版本脚本只支持正式 tag，不支持 `dev/rc` 状态辅助函数 | P1 |
| `status` | 已实现 | 只展示基础状态，缺少当前线上版本、活动 release、hotfix 回流风险提示 | P1 |
| `sync` | 基本可用 | 与新规则基本一致，但缺少 busy/behind 更细粒度状态输出 | P1 |
| `feature` | 基本可用 | 缺少“空闲 worktree”校验，不区分 busy worktree | P0 |
| `hotfix` | 规则错误 | 当前把输入版本当作“已有 tag”，与 `hotfix/x.y.z` 从线上 tag 派生到新 patch 目标的规则冲突 | P0 |
| `release` | 规则错误 | 仍保留在 `release/*` 上迭代改名的旧思路，与 `main -> release/x.y.z -> publish` 的固定路径不一致 | P0 |
| `publish` | 规则错误 | 仍支持从 `main` 快速发布，并保留旧 `product` 思维，和现行规范冲突 | P0 |
| `commit-push-pr` | 规则严重过时 | 仍包含 `main` 直推、`product` 分支、自动 bump 正式 tag 等旧逻辑，且 hotfix 回流路径不对 | P0 |

### 2.2 已识别的核心不一致

| 类别 | 现状 | 目标 |
|------|------|------|
| 版本锚点 | 部分技能仍把分支当作版本来源 | 仅 `tag vX.Y.Z` 是线上真实版本 |
| 发布路径 | `publish` 支持从 `main` 发布 | 只能从匹配的 `release/x.y.z` 发布 |
| 热修路径 | `hotfix` 以“已有 tag”为输入 | 以线上 tag 为基线，创建新的 `hotfix/x.y.z` |
| 回流路径 | `commit-push-pr` 仍走 `product -> main` | hotfix 发布后回流 `main`，必要时同步活动 `release/*` |
| 版本升级 | 自动 bump 正式 tag | 正式版本仅在 `publish` 或 hotfix 发布时生成 |
| worktree 安全 | reset 前未充分校验 | 必须检查 clean/behind/busy，避免丢失用户改动 |

---

## 三、改造原则

- 先统一共享版本与分支判定逻辑，再改各技能行为
- 先改高风险路由命令，再改信息展示和辅助命令
- 先让命令“拒绝错误行为”，再补“自动化便利能力”
- 所有危险动作必须显式前置校验，禁止隐式 reset、隐式覆盖、隐式发版
- 先落实单元与集成测试骨架，再做端到端场景回归

---

## 四、开发与改造计划

### Phase 0：基础能力收敛

**目标**

- 收敛分支识别、版本计算、上下文校验到共享脚本
- 为后续 6 个核心技能提供统一依赖

**涉及技能**

- `setup`
- `status`
- 共享脚本 `.sns-workflow/scripts/version.sh`
- 新增辅助脚本建议：`.sns-workflow/scripts/context.sh`

**改造内容**

- 为 `version.sh` 补充正式版本解析、版本比较、patch/minor/major bump、tag 存在校验
- 增加 `context.sh`，统一识别 `worktree-*`、`feature/*`、`release/*`、`hotfix/*`
- 为 `status` 增加线上 tag、活动 release、worktree busy 状态、待回流 hotfix 提示
- `setup` 负责初始化上述共享脚本与目录结构

**完成标准**

- 所有核心技能都复用共享脚本，不再各自写分支/版本判定
- `status` 能准确展示线上版本、当前分支语义和活动 release

### Phase 1：开发入口与安全护栏

**目标**

- 先修正进入开发态的命令，保证工作区安全与上下文正确

**涉及技能**

- `sync`
- `feature`
- `hotfix`

**改造内容**

- `sync`
  - 保留只允许在 `worktree-*` 执行
  - 增加 clean 检查、冲突提示、behind 说明
  - 输出同步前后基线摘要
- `feature`
  - 增加“空闲 worktree”校验
  - 创建 `feature/*` 前校验本地和远端重名
  - 自动记录所属 worktree，便于后续 `commit-push-pr` 回切
- `hotfix`
  - 改为“从当前线上 tag 派生新的 hotfix 目标版本”
  - 默认从最新正式 tag 自动计算 `patch + 1`
  - 显式校验目标版本大于当前线上版本
  - 分支名统一为 `hotfix/x.y.z`，tag 统一为 `vX.Y.Z`

**完成标准**

- `feature` 不能从 busy worktree 创建分支
- `hotfix` 不能从 `main`、`release/*`、不存在 tag 的上下文派生
- 三个命令的失败输出都能明确说明阻止原因

### Phase 2：主流程路由重构

**目标**

- 重构最关键的 `commit-push-pr`，使其成为上下文感知型路由器

**涉及技能**

- `commit-push-pr`

**改造内容**

- 删除旧的 `main` 直推和 `product` 分支逻辑
- 在 `worktree-*` 上：
  - commit -> push -> PR 到 `main`
  - merge 后仅在通过 clean/behind 校验后 reset 到最新 `main`
- 在 `feature/*` 上：
  - commit -> push -> PR 到 `main`
  - merge 后删除 feature 分支
  - 自动切回所属 `worktree-*`
- 在 `hotfix/*` 上：
  - commit -> push -> 发布新 tag `vX.Y.Z`
  - 生成 hotfix -> `main` 回流
  - 若存在活动 `release/*`，继续生成 hotfix -> `release/*` 的同步动作
- 全流程输出版本决策、目标分支、回流结果

**完成标准**

- 三种上下文都能被正确识别
- 不再自动生成与正式发布无关的 tag
- worktree reset 前必须显式保护未推送提交

### Phase 3：发布链路收敛

**目标**

- 让 `release` 与 `publish` 完全符合 `main -> release -> tag -> main` 模型

**涉及技能**

- `release`
- `publish`

**改造内容**

- `release`
  - 仅允许从 `main` 创建 `release/x.y.z`
  - 校验目标版本必须大于当前线上版本
  - 创建后进入 `x.y.z-rc.1` 候选态
  - 不再支持在 `release/*` 上直接“改名升级”的旧流程
- `publish`
  - 仅允许在匹配的 `release/x.y.z` 上执行
  - 校验工作区干净、tag 不存在、版本与分支匹配
  - 生成 `vX.Y.Z`
  - 发布后执行 `release/* -> main` 回流

**完成标准**

- 不能从 `main` 直接 publish
- 不能在错误 release 分支上发布其他版本
- 发布后 `main` 收到 release 修复

### Phase 4：测试落地与回归闭环

**目标**

- 将 `test-plan.md` 中的规则真正落实为可执行验证

**涉及内容**

- 单元测试
- git sandbox 集成测试
- 端到端回归场景

**改造内容**

- 抽取可测试的版本计算函数与分支识别函数
- 构建临时 git 仓库 sandbox 执行集成测试
- 为 hotfix、release、publish 建立场景回归测试
- 对 PR 创建与 merge 相关步骤使用 mock 或可替换适配层

**完成标准**

- P0 相关技能都有单元与集成测试
- 至少覆盖 5 条场景测试和 5 条负向测试
- 每次重构能执行回归套件，防止规则退化

---

## 五、测试落实计划

### 5.1 测试分层

| 层级 | 覆盖内容 | 优先级 |
|------|----------|--------|
| 单元测试 | 分支识别、版本计算、版本比较、命令上下文校验 | P0 |
| 集成测试 | 本地 git 分支创建、切换、rebase、tag、回流 | P0 |
| 场景测试 | 快捷模式、feature 模式、release 演进、hotfix 并行 | P1 |
| E2E 测试 | 完整开发到发布闭环 | P1 |

### 5.2 测试落地顺序

1. 先落地共享脚本单元测试
2. 再落地 `sync`、`feature`、`hotfix` 集成测试
3. 然后落地 `commit-push-pr` 路由集成测试
4. 最后落地 `release`、`publish` 以及 hotfix 并行回归测试

### 5.3 推荐测试组织

```text
.sns-workflow/tests/
  unit/
    test_version.sh
    test_context.sh
  integration/
    test_sync.sh
    test_feature.sh
    test_hotfix.sh
    test_commit_push_pr.sh
    test_release.sh
    test_publish.sh
  scenarios/
    test_quick_mode.sh
    test_feature_mode.sh
    test_release_flow.sh
    test_hotfix_flow.sh
    test_hotfix_with_active_release.sh
```

### 5.4 测试里程碑

| 里程碑 | 必须通过的测试 |
|--------|----------------|
| M1 | `TC-UNIT-BR-*`、`TC-UNIT-VER-*`、`TC-UNIT-CMD-*` |
| M2 | `TC-SYNC-*`、`TC-FEAT-*`、`TC-CPP-01~05` |
| M3 | `TC-REL-*`、`TC-PUB-*`、`TC-SCN-01~05` |
| M4 | `TC-NEG-01~05`、`TC-E2E-01~05` |

---

## 六、Task 工作列表

### Epic A：基础脚本与状态模型

| ID | Task | 类型 | 优先级 | 依赖 | 预估 |
|----|------|------|--------|------|------|
| A1 | 盘点并收敛 `version.sh` 中的公共函数 | 开发 | P0 | 无 | 0.5d |
| A2 | 新增 `context.sh`，统一分支上下文识别 | 开发 | P0 | A1 | 0.5d |
| A3 | 改造 `setup` 以初始化共享脚本与目录 | 改造 | P1 | A1,A2 | 0.5d |
| A4 | 改造 `status` 展示线上版本、活动 release、worktree busy 状态 | 改造 | P1 | A1,A2 | 0.5d |
| A5 | 为共享脚本补单元测试 | 测试 | P0 | A1,A2 | 0.5d |

### Epic B：开发入口命令

| ID | Task | 类型 | 优先级 | 依赖 | 预估 |
|----|------|------|--------|------|------|
| B1 | 改造 `sync`，补强 clean/behind/冲突输出 | 改造 | P1 | A2 | 0.5d |
| B2 | 改造 `feature`，增加空闲 worktree 校验 | 改造 | P0 | A2,B1 | 0.5d |
| B3 | 重写 `hotfix` 输入与派生逻辑 | 重构 | P0 | A1,A2 | 1d |
| B4 | 为 `sync/feature/hotfix` 补集成测试 | 测试 | P0 | B1,B2,B3 | 1d |

### Epic C：主流程路由器

| ID | Task | 类型 | 优先级 | 依赖 | 预估 |
|----|------|------|--------|------|------|
| C1 | 重构 `commit-push-pr` 的分支识别与路由骨架 | 重构 | P0 | A1,A2 | 1d |
| C2 | 实现 worktree 路径的 PR 合并与安全回收 | 开发 | P0 | C1 | 0.5d |
| C3 | 实现 feature 路径的回切与分支清理 | 开发 | P0 | C1 | 0.5d |
| C4 | 实现 hotfix 路径的 tag 发布与回流动作 | 开发 | P0 | C1,B3 | 1d |
| C5 | 为 `commit-push-pr` 补集成测试与负向测试 | 测试 | P0 | C2,C3,C4 | 1d |

### Epic D：发布链路

| ID | Task | 类型 | 优先级 | 依赖 | 预估 |
|----|------|------|--------|------|------|
| D1 | 重构 `release`，仅保留从 `main` 创建 release 的路径 | 重构 | P0 | A1,A2 | 0.5d |
| D2 | 重构 `publish`，仅保留从匹配 release 发布的路径 | 重构 | P0 | A1,A2,D1 | 1d |
| D3 | 实现 `release/* -> main` 回流逻辑 | 开发 | P0 | D1,D2 | 0.5d |
| D4 | 为 `release/publish` 补集成测试与场景测试 | 测试 | P0 | D1,D2,D3 | 1d |

### Epic E：场景回归与验收

| ID | Task | 类型 | 优先级 | 依赖 | 预估 |
|----|------|------|--------|------|------|
| E1 | 实现快捷模式 E2E 测试 | 测试 | P1 | B4,C5 | 0.5d |
| E2 | 实现 Feature 模式 E2E 测试 | 测试 | P1 | B4,C5 | 0.5d |
| E3 | 实现 Release 完整路径 E2E 测试 | 测试 | P1 | D4 | 0.5d |
| E4 | 实现 Hotfix 完整路径 E2E 测试 | 测试 | P1 | B4,C5 | 0.5d |
| E5 | 实现 Hotfix 与活动 release 并行回归测试 | 测试 | P1 | C5,D4 | 0.5d |
| E6 | 按验收清单完成一次全量验收走查 | 验收 | P0 | E1,E2,E3,E4,E5 | 0.5d |

---

## 七、推荐执行顺序

1. `A1 -> A2 -> A5`
2. `B3 -> C1`
3. `B1 -> B2 -> B4`
4. `C2 -> C3 -> C4 -> C5`
5. `D1 -> D2 -> D3 -> D4`
6. `E1 -> E2 -> E3 -> E4 -> E5 -> E6`

这样安排的原因：

- 先统一基础脚本，避免每个技能各修各的
- 先拿下 `hotfix` 和 `commit-push-pr`，这是当前偏差最大的高风险点
- 发布链路放在主流程稳定后收敛，避免返工
- E2E 放最后，作为规则闭环的最终验收

---

## 八、阶段性验收标准

### 阶段一通过条件

- `feature`、`hotfix`、`sync` 全部符合当前上下文约束
- 共享脚本单元测试通过

### 阶段二通过条件

- `commit-push-pr` 完成 worktree / feature / hotfix 三路改造
- 高风险负向测试通过

### 阶段三通过条件

- `release` 与 `publish` 完全符合 `release -> tag -> main` 链路
- 活动 release 与 hotfix 并行场景通过

### 阶段四通过条件

- `test-plan.md` 中 P0/P1 测试全部具备可执行脚本或明确 mock 方案
- 全量验收清单项全部通过

---

## 九、主要风险与缓解措施

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 旧技能逻辑分散在多个脚本片段中 | 改造时易出现口径不一致 | 先抽共享脚本，再改技能 |
| `gh` CLI 依赖不稳定 | 集成测试难稳定 | PR 创建与 merge 先提供 mock 适配层 |
| hotfix 回流到活动 release 易冲突 | 回归用例复杂 | 先做 git sandbox，再做场景回归 |
| worktree reset 存在误伤风险 | 可能丢失用户工作 | reset 前强制 clean/behind/busy 校验 |
| 文档与实现再次漂移 | 后续维护成本升高 | 每个 Epic 完成后同步校验文档和测试计划 |

---

## 十、实施建议

- 以 `Epic A + Epic B + Epic C` 作为第一迭代，先修正主线开发与 hotfix 主路径
- `release/publish` 不建议与 `commit-push-pr` 同时改，避免调试面过大
- 每完成一个 Epic，就执行对应测试分层，不要等到最后一次性联调
- 若需要进入实际编码，建议下一步从 `A1` 和 `A2` 开始，先抽共享脚本与判定函数
