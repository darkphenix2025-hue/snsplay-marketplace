# SKILL.md 重构验证契约

## 决策逻辑检查清单（必须在重构后保留）

- [ ] 清晰度门控：4 个维度（范围/目标/约束/架构），≥2 个歧义 → 询问
- [ ] 架构类型预判：元架构 vs 项目技术架构
- [ ] Type A-E 路由：5 种类型各有不同的延续
- [ ] Fetch-first 3 步：关键词扫描 → 搜索拥有者 → 评分+调用
- [ ] 关键词扫描表：tdd/review/security/debug/architecture/frontend/backend/database/DEFAULT

## 执行步骤检查清单（必须在重构后保留）

- [ ] 8 阶段脊椎：Critical→Fetch→Thinking→Execution→Review→Meta-Review→Verification→Evolution
- [ ] 规划文件：task_plan.md、findings.md、progress.md
- [ ] 门控 3 验证：5 项检查清单（agent 已分配/无越级/agent 正确/无缺口/复杂度）
- [ ] 工厂站：Genesis→Artisan 顺序，Scout/Sentinel/Librarian 条件并行
- [ ] Type B 5 步流水线：发现→预设计→设计→审查→集成
- [ ] 站交付物契约：Warden/Genesis/Artisan/Sentinel/Librarian/Conductor/Prism/Scout

## 条件与触发检查清单（必须在重构后保留）

- [ ] 可衡量的分发触发条件：读取 3+ 文件 / 20+ 行代码 / 多模块 / 任何文件修改 / 执行中捕获
- [ ] 禁止路径：6 种反模式已列出
- [ ] 门控 3 不可跳过，失败覆盖 = 治理违规
- [ ] 执行前需用户确认（第 1-3 阶段 → 展示计划 → 确认）
- [ ] 能力缺口解决阶梯：现有拥有者 → Type B 创建 → 临时回退
- [ ] agentInvocationState 生命周期：idle→discovered→matched→dispatched→returned/escalated

## 边界检查清单（必须在重构后保留）

- [ ] 禁止硬编码 agent 名称
- [ ] meta-theory 是分发器，不是执行器（>3 句话 = 违规）
- [ ] 自检 4 个问题：越级/硬编码/能力缺口/用户绕过
- [ ] 只读模式仍然可分发（不撤销 agent 授权）

## 进化规则检查清单（必须在重构后保留）

- [ ] 直接优于间接：编辑 agent SOUL.md，不是记忆文件
- [ ] 进化写回表：7 种缺口类型及目标

## 测试提示

1. **Type A 测试**："审查一下 meta-conductor 的定义是否符合五标准"
   - 预期：分类为 Type A，Fetch-first 搜索质量审查能力，分发质量审计 agent

2. **Type C 测试**："给 stop-memory-save hook 添加重试机制"
   - 预期：分类为 Type C，可衡量触发（文件修改），分发执行 agent

3. **歧义测试**："优化一下项目"
   - 预期：清晰度门控触发（≥2 个维度歧义），继续前先询问

4. **简单任务测试**："这个文件第10行什么意思"
   - 预期：不需要分发，直接回答（单文件、单问题、无修改）

5. **Type B 测试**："创建一个新的 meta-auditor agent 专门做运行时健康审计"
   - 预期：分类为 Type B，工厂站激活，Genesis→Artisan 顺序流水线
