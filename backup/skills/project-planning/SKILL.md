---
name: project-planning
description: "Comprehensive project requirements planning workflow. Transform ideas into structured development plans through requirement refinement, task decomposition, PRD design, and task list generation. Triggers when user says: '我想做xx', '我要实现一个xx功能', '开发一个xx系统', '规划这个项目', '制定开发计划'. Use this skill whenever the user mentions building a feature, system, or project, even if they don't explicitly ask for 'planning'."
license: MIT
---

# Project Planning Workflow

Transform ideas into structured, executable development plans through a multi-phase workflow that adapts to project complexity.

---

## Overview

This skill orchestrates the complete project planning process with a **parallel pipeline workflow**:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     PARALLEL PIPELINE WORKFLOW                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Phase 1: 需求分析 ──→ requirements.md                                     │
│        │                                                                     │
│        ↓                                                                     │
│   Phase 2: 任务分解 ──→ master-index.json (主任务索引)                      │
│        │                                                                     │
│        ↓                                                                     │
│   ┌────┴─────────────────────────────────────────────────────────────────┐  │
│   │                                                                        │  │
│   │   [规划端]                    [任务列表]                [开发端]       │  │
│   │   (Phase 3-4)                 (JSON文件)               (Phase 5)      │  │
│   │                                                                        │  │
│   │   ┌───────────┐               ┌─────────┐              ┌───────────┐  │  │
│   │   │ T001 PRD  │──写入──→     │         │←──轮询──     │ Agent 1   │  │  │
│   │   │ T001 Tasks│               │ 任务列表 │              │ 执行任务  │  │  │
│   │   └───────────┘               │         │              └───────────┘  │  │
│   │                               │  • T001 │                            │  │
│   │   ┌───────────┐               │  • T002 │              ┌───────────┐  │  │
│   │   │ T002 PRD  │──写入──→     │  • ...  │←──轮询──     │ Agent 2   │  │  │
│   │   │ T002 Tasks│               │         │              │ 执行任务  │  │  │
│   │   └───────────┘               │         │              └───────────┘  │  │
│   │                               │         │                            │  │
│   │   ┌───────────┐               │         │              ┌───────────┐  │  │
│   │   │ T003 PRD  │──写入──→     │         │←──轮询──     │ Agent 3   │  │  │
│   │   │ T003 Tasks│               │         │              │ 等待任务  │  │  │
│   │   └───────────┘               └─────────┘              └───────────┘  │  │
│   │                                     ↑                                  │  │
│   │                                     │                                  │  │
│   │                              无任务时等待                              │  │
│   │                            定期重试获取任务                            │  │
│   │                                                                        │  │
│   └───────────────────────────────────────────────────────────────────────┘  │
│        │                                                                     │
│        ↓                                                                     │
│   Phase 6: 集成测试                                                          │
│        │                                                                     │
│        ├──→ 直接修复                                                         │
│        │                                                                     │
│        └──→ 增加任务 → 写入任务列表 → 开发端获取处理                          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key Principles:**

1. **Decoupled phases:** Phase 4 and Phase 5 have no direct connection - they interact only through the task list
2. **Polling mechanism:** Phase 5 agents poll the task list for available tasks; if empty, they wait and retry periodically
3. **Parallel pipeline:** Phase 5 starts immediately and runs independently of Phase 3-4
4. **Continuous planning:** Phase 3-4 continues generating PRDs and task lists while development is ongoing
5. **Feedback loop:** Phase 6 issues can be fixed directly or add new tasks to development queue
6. **Adaptive depth:** Simple tasks skip phases; complex tasks iterate through multiple levels

---

## Phase 0: Complexity Assessment

Before starting, determine the appropriate workflow depth and whether to invoke supporting skills.

### Step 0.1: Initial Input Assessment

**Key insight:** Project initiation typically starts with a brief one-line description. This is usually insufficient for planning.

**Assessment rule:**

```
用户输入是一句话描述?
    │
    ├── 是简单任务? (如 "修改错误", "调整xxx样式", "添加日志")
    │   └── Simple → Skip brainstorming, direct execution
    │
    └── 其他情况 (功能开发、系统构建、新特性等)
        └── 一句话说明不足 → Invoke brainstorming (required)
```

### Step 0.2: Complexity Evaluation

| Complexity | Indicators | Workflow |
|------------|------------|----------|
| **Simple** | Single function, <1 day work, clear outcome, one-step fix | Direct to execution |
| **Medium** | Feature with multiple components, 1-5 days | Brainstorming → Requirements → PRD → Task List |
| **Complex** | System with dependencies, >1 week, multiple units | Brainstorming → Full workflow with multi-level decomposition |

### Step 0.3: Invoke Brainstorming (Default for Non-Simple Tasks)

**Invoke brainstorming when:**

1. ✅ Task is NOT a simple fix/adjustment
2. ✅ User input is a brief one-line description
3. ✅ Building a feature, system, or new capability

**Skip brainstorming only when:**
- ❌ Task is explicitly simple: "fix bug X", "adjust Y", "add log"

```
Use the Skill tool to invoke: brainstorming

Purpose: Expand the brief input into clear requirements
```

**Brainstorming goals:**

| Goal | Question |
|------|----------|
| **功能描述清楚** | What exactly should this do? |
| **边界清晰** | What should it NOT do? |
| **用户明确** | Who will use this? |
| **标准可衡量** | How do we know it's done? |
| **技术栈清楚** | What technologies are involved? |

### Step 0.4: Assessment Questions

After brainstorming (if invoked), confirm understanding:

1. How many distinct components/modules are involved?
2. Are there dependencies between components?
3. What's the estimated time range?
4. How many people/agents will work on this?

---

## Phase 1: Requirement Analysis

**Goal:** Transform brainstorming outputs into structured requirement document.

**Note:** Use brainstorming outputs to populate the requirement document. If certain aspects remain unclear, ask targeted clarifying questions.

### Step 1.1: Capture Requirements from Brainstorming

Ask clarifying questions with lettered options:

```
1. What is the primary goal of this feature/system?
   A. [Option A based on context]
   B. [Option B]
   C. [Option C]
   D. Other: [please specify]

2. Who will use this?
   A. End users
   B. Internal team
   C. Both
   D. Other
```

### Step 1.2: Define Boundaries

Create explicit scope definition:

| Category | IN Scope | OUT of Scope |
|----------|----------|--------------|
| Features | ... | ... |
| Users | ... | ... |
| Platforms | ... | ... |
| Integrations | ... | ... |

### Step 1.3: Generate User Stories

Extract user stories from requirements:

```markdown
**US-001: [Story Title]**
As a [user type], I want [action] so that [benefit].

**Acceptance Criteria:**
- [ ] Criterion 1
- [ ] Criterion 2
```

### Output: Requirement Document

```markdown
# Requirements: [Feature Name]

## Overview
[Brief description]

## Goals
- Goal 1
- Goal 2

## User Stories
### US-001: [Title]
...

## Scope
| IN | OUT |
|----|-----|
| ... | ... |

## Quality Gates
- `pnpm typecheck` - Type checking
- `pnpm lint` - Linting

## Open Questions
- [Question 1]
```

---

## Phase 2: Task Decomposition

**Goal:** Break down complex requirements into manageable, independent units.

### Step 2.0: Invoke Task-Decomposition (Conditional)

Based on complexity from Phase 0:

| Complexity | Invoke Task-Decomposition? |
|------------|---------------------------|
| **Simple** | ❌ Skip (no decomposition needed) |
| **Medium** | ✅ Optional (if >3 components) |
| **Complex** | ✅ Yes (required) |

**If complexity is Complex OR (Medium AND >3 components):**

```
Use the Skill tool to invoke: task-decomposition

Purpose: Apply INVEST criteria, identify cognitive limits, create vertical slices
```

**Task-decomposition provides:**
- INVEST criteria validation (Independent, Negotiable, Valuable, Estimable, Small, Testable)
- Cognitive limit awareness (7±2 items per task)
- Vertical slicing patterns
- Dependency analysis

### Step 2.1: Apply Decomposition Rules

**Critical rule:** Each decomposition level should contain **approximately 10 steps** (range: 8-15).

- If >15 steps: Create another decomposition level
- If <5 steps: Consider merging with related tasks

### Step 2.2: Identify Dependencies

Map task dependencies:

```
Task A ──→ Task B ──→ Task C
    │
    └──────→ Task D
```

### Step 2.3: Create Task Hierarchy

```json
{
  "level": 0,
  "tasks": [
    {
      "id": "T001",
      "title": "Main Task 1",
      "status": "pending",
      "estimated_hours": 8,
      "depends_on": [],
      "children": [
        {
          "id": "T001-1",
          "title": "Subtask 1.1",
          "status": "pending",
          "depends_on": []
        }
      ]
    }
  ]
}
```

### Output: Master Task Index

```markdown
# Task Decomposition: [Feature Name]

## Task Tree

```
T001: Authentication Module
├── T001-1: User schema design
├── T001-2: Login endpoint
│   ├── T001-2-1: Password validation
│   └── T001-2-2: JWT generation
└── T001-3: Session management
```

## Dependencies
- T001-2 depends on T001-1
- T001-3 depends on T001-2

## Execution Order
1. T001-1 (no dependencies)
2. T001-2 (after T001-1)
3. T001-3 (after T001-2)
```

---

## Phase 3: Unit PRD Design

**Goal:** Create detailed PRD for each task unit.

### Step 3.0: Unit Clarity Assessment

**Before designing unit PRD, assess if the unit needs deeper analysis:**

| Unit Clarity | Indicators | Action |
|--------------|------------|--------|
| **Clear** | Unit purpose, inputs, outputs, and acceptance criteria are obvious | Proceed to PRD directly |
| **Unclear** | Ambiguous requirements, multiple possible approaches, or scope creep | Invoke brainstorming for this unit |

**Unit-level brainstorming trigger:**
```
Unit requirements unclear?
    │
    ├── Yes → Invoke brainstorming skill (unit scope)
    │         Focus on: What does THIS unit accomplish?
    │
    └── No → Proceed to Step 3.1
```

**Unit-level brainstorming focuses on:**
- What exactly should this unit do?
- What are the inputs and expected outputs?
- What are the edge cases?
- What interfaces does it need?

### Step 3.1: PRD Template

```markdown
# PRD: [Unit Name]

## Overview
[What this unit accomplishes]

## Goals
- [Goal 1]
- [Goal 2]

## Quality Gates
These commands must pass for every user story:
- `pnpm typecheck` - Type checking
- `pnpm lint` - Linting

## User Stories

### US-001: [Story Title]
**Description:** As a [user], I want [feature] so that [benefit].

**Acceptance Criteria:**
- [ ] Criterion 1
- [ ] Criterion 2

## Technical Considerations
- [Constraints]
- [Integration points]

## Non-Goals
- [What this unit does NOT do]
```

### Step 3.2: Unit Size Validation

Each unit PRD must be:
- Completable in **one agent session** (~2-4 hours)
- **Independently testable**
- **Smaller than the parent task**

If a unit is too large, return to Phase 2 for further decomposition.

---

## Phase 4: Task List Generation

**Goal:** Convert PRDs to executable task JSON files.

**Reference:** Use `ralph-tui-create-json` skill schema.

### Step 4.1: JSON Task Schema

```json
{
  "name": "[Unit Name]",
  "branchName": "feature/[unit-name-kebab]",
  "description": "[Description from PRD]",
  "userStories": [
    {
      "id": "US-001",
      "title": "[Story Title]",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": [
        "Criterion 1",
        "Criterion 2",
        "pnpm typecheck passes",
        "pnpm lint passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": "",
      "dependsOn": [],
      "estimated_hours": 4,
      "timeout_hours": 8
    }
  ]
}
```

### Step 4.2: Multi-Level Task Files

Organize task files in a nested hierarchy:

```
tasks/
├── master-index.json           # Level 0: Main task index
│
├── T001/                       # Main task directory
│   ├── prd.md                  # T001 PRD (if this level needs design)
│   ├── index.json              # T001 child task index (references T001-1, T001-2, ...)
│   │
│   ├── T001-1/                 # Subtask directory (nested inside parent)
│   │   ├── prd.md              # T001-1 PRD
│   │   └── tasks.json          # T001-1 task list
│   │
│   └── T001-2/                 # Another subtask
│       ├── prd.md
│       ├── tasks.json
│       │
│       └── T001-2-1/           # Deeper nesting if needed
│           ├── prd.md
│           └── tasks.json
│
├── T002/                       # Another main task
│   ├── prd.md
│   └── tasks.json              # T002 has no children, direct tasks
│
└── T003/
    └── ...
```

**Key Principles:**

1. **Parent tasks contain child indexes**: `index.json` lists and tracks child tasks
2. **Children nest inside parents**: T001-1 lives inside T001/
3. **Leaf tasks have task lists**: Only the deepest level has `tasks.json` with user stories
4. **PRD at each decomposable level**: If a task needs decomposition, it has a PRD

### Step 4.3: Index File Schema

Parent task `index.json` acts as child task index:

```json
{
  "id": "T001",
  "title": "Authentication Module",
  "status": "in_progress",
  "estimated_hours": 24,
  "timeout_hours": 48,
  "children": [
    {
      "id": "T001-1",
      "title": "User schema design",
      "path": "T001-1/",
      "status": "completed",
      "passes": true
    },
    {
      "id": "T001-2",
      "title": "Login endpoint",
      "path": "T001-2/",
      "status": "in_progress",
      "passes": false,
      "depends_on": ["T001-1"]
    }
  ],
  "integration_tests": [
    {
      "description": "User can log in with valid credentials",
      "depends_on": ["T001-1", "T001-2"],
      "status": "pending"
    }
  ]
}
```

### Step 4.4: Status Propagation

When child tasks complete, parent status updates:

```
T001-1 completes → T001/index.json updated → T001 status reflects child progress
                    │
                    └── T001 can now run integration_tests for T001-1
```

**Integration tests in parent activate when all dependencies complete:**

```json
// T001/index.json
{
  "integration_tests": [
    {
      "description": "Full auth flow works end-to-end",
      "depends_on": ["T001-1", "T001-2", "T001-3"],
      "status": "ready"  // All deps complete, ready to test
    }
  ]
}
```

---

## Phase 5: Parallel Execution Coordination

**Goal:** Coordinate multiple development agents working in parallel, decoupled from the planning process.

**Reference:** Use `ralph-wiggum:ralph-loop` execution pattern.

### Step 5.1: Decoupled Execution Model

**Key insight:** Phase 5 is completely decoupled from Phase 3-4. Agents interact only with the task list through polling.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     DECOUPLED EXECUTION MODEL                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Phase 3-4 (规划端)                任务列表                Phase 5 (开发端) │
│                                                                              │
│   ┌─────────────┐               ┌─────────────┐              ┌───────────┐  │
│   │ PRD设计     │               │             │              │           │  │
│   │ 任务列表生成 │───写入───→   │ tasks/*.json │←──轮询───   │ Agent 1   │  │
│   │             │               │             │              │           │  │
│   │ (独立运行)   │               │  • T001-1   │              │ Agent 2   │  │
│   │             │               │  • T001-2   │              │           │  │
│   └─────────────┘               │  • T002-1   │              │ Agent 3   │  │
│                                 │  • ...      │              │           │  │
│   无直接通信                      │             │              └───────────┘  │
│   只通过任务列表交互               └─────────────┘                             │
│                                        │                                     │
│                                        │ 轮询间隔                             │
│                                        │ (例如: 30秒)                         │
│                                        ↓                                     │
│                                 ┌─────────────┐                              │
│                                 │ 无可用任务?  │                              │
│                                 │ → 等待      │                              │
│                                 │ → 重试      │                              │
│                                 └─────────────┘                              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Step 5.2: Agent Polling Mechanism

**Agent lifecycle:**

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   启动      │────→│  轮询任务列表 │────→│  获取任务?   │────→│  执行任务   │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
                                              │                     │
                                              │ 否                   │ 完成
                                              ↓                     ↓
                                        ┌─────────────┐     ┌─────────────┐
                                        │  等待       │     │  更新状态   │
                                        │  (N秒后重试) │     │  写入JSON   │
                                        └─────────────┘     └─────────────┘
                                              │                     │
                                              └─────────────────────┘
                                                     ↓
                                              返回轮询
```

**Polling configuration:**

```json
{
  "polling": {
    "interval_seconds": 30,
    "max_retries": -1,
    "exit_condition": "all_tests_pass"
  }
}
```

### Step 5.3: Task Selection Logic

When polling the task list, agents select tasks based on:

1. **Dependency resolution:** Only tasks with all dependencies marked `passes: true`
2. **Priority ordering:** Higher priority (lower number) first
3. **Status check:** Only tasks with `status: pending` or `status: in_progress` (for retry)
4. **Lock mechanism:** Prevent duplicate execution by checking lock status

**Selection pseudocode:**

```python
def select_task(task_list):
    available_tasks = [
        t for t in task_list
        if t.status == "pending"
        and all(dep.passes for dep in t.depends_on)
        and not t.locked
    ]
    if available_tasks:
        return max(available_tasks, key=lambda t: t.priority)
    return None
```

### Step 5.4: Status Synchronization

Task status updates flow upward through the file hierarchy:

```
T001-1-1 完成 → T001-1/index.json 更新 → T001/index.json 更新 → master-index.json 更新
```

**Status propagation rules:**
- Child `passes: true` → Parent can run integration tests
- All children `passes: true` → Parent `status: completed`
- Integration test `passes: true` → Parent `passes: true`

### Step 5.5: Timeout Handling

```python
# Pseudocode for timeout detection
if task.elapsed_hours > task.timeout_hours:
    if task.has_progress():
        extend_timeout(task, additional_hours=4)
    else:
        flag_for_intervention(task)
        # Option: Reassign to another agent
```

---

## Phase 6: Integration & Testing

**Goal:** Assemble units and verify system integrity through hierarchical testing, with feedback loop to development.

### Step 6.1: Hierarchical Testing Model

Testing follows the task hierarchy - each level has its own test requirements:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     HIERARCHICAL TESTING MODEL                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   Level 0 (System Tests)                                                 │
│   ├── End-to-end scenarios                                               │
│   ├── Cross-module integration                                           │
│   └── Depends on: All Level 1 tasks complete                             │
│                                                                          │
│   Level 1 (Module Tests) - e.g., T001/                                   │
│   ├── Module-level integration tests                                     │
│   ├── Interface contract verification                                    │
│   └── Depends on: All Level 2 children (T001-1, T001-2, ...) complete   │
│                                                                          │
│   Level 2 (Component Tests) - e.g., T001-2/                              │
│   ├── Component integration tests                                        │
│   └── Depends on: All Level 3 children (T001-2-1, T001-2-2) complete    │
│                                                                          │
│   Level N (Unit Tests) - Leaf tasks with tasks.json                      │
│   ├── Individual function/class tests                                    │
│   └── Defined in userStories acceptance criteria                         │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Step 6.2: Issue Feedback Loop

When testing finds issues, there are two resolution paths:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     ISSUE RESOLUTION WORKFLOW                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   测试发现问题                                                                │
│        │                                                                     │
│        ↓                                                                     │
│   ┌─────────────────┐                                                        │
│   │ 评估问题严重程度 │                                                        │
│   └─────────────────┘                                                        │
│        │                                                                     │
│        ├──────────────────────────────┬──────────────────────────────┐      │
│        ↓                              ↓                              │      │
│   ┌─────────────┐              ┌─────────────┐                      │      │
│   │ 简单问题    │              │ 复杂问题    │                      │      │
│   │ (直接修复)  │              │ (新增任务)  │                      │      │
│   └─────────────┘              └─────────────┘                      │      │
│        │                              │                              │      │
│        ↓                              ↓                              │      │
│   Agent直接修复                创建新任务                              │      │
│        │                              │                              │      │
│        │                              ↓                              │      │
│        │                       ┌─────────────┐                      │      │
│        │                       │ 添加到任务  │                      │      │
│        │                       │ 队列        │                      │      │
│        │                       └─────────────┘                      │      │
│        │                              │                              │      │
│        └──────────────────────────────┼──────────────────────────────┘      │
│                                       │                                      │
│                                       ↓                                      │
│                                 重新测试                                      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Issue categorization:**

| 类型 | 处理方式 | 示例 |
|------|---------|------|
| **直接修复** | Agent立即修复 | 拼写错误、简单逻辑错误、配置问题 |
| **新增任务** | 加入任务队列 | 功能缺失、需要重构、涉及多个模块 |

**New task creation for issues:**

```json
// 添加到相应父任务的 tasks.json 或 index.json
{
  "id": "BUG-001",
  "title": "Fix login validation edge case",
  "description": "Empty password causes server error",
  "type": "bug",
  "priority": "high",
  "status": "pending",
  "depends_on": [],
  "acceptance_criteria": [
    "Empty password returns proper error message",
    "Server does not crash on edge cases"
  ]
}
```

### Step 6.3: Parent-Level Test Requirements

When child tasks complete, parent-level tests become active:

```json
// Example: T001/index.json
{
  "id": "T001",
  "title": "Authentication Module",
  "children": [
    {"id": "T001-1", "status": "completed", "passes": true},
    {"id": "T001-2", "status": "completed", "passes": true},
    {"id": "T001-3", "status": "completed", "passes": true}
  ],
  "integration_tests": [
    {
      "id": "IT-001",
      "description": "User can register, login, and logout successfully",
      "depends_on": ["T001-1", "T001-2", "T001-3"],
      "acceptance_criteria": [
        "Registration creates valid user record",
        "Login returns valid JWT token",
        "Logout invalidates session"
      ],
      "status": "ready",
      "passes": false
    },
    {
      "id": "IT-002",
      "description": "Password reset flow works end-to-end",
      "depends_on": ["T001-1", "T001-4"],
      "status": "blocked",
      "passes": false
    }
  ]
}
```

### Step 6.4: Test Execution Order

Tests execute in bottom-up order:

```
1. Execute T001-2-1 unit tests (from tasks.json)
2. Execute T001-2-2 unit tests
3. All T001-2 children pass → Run T001-2 integration tests
4. T001-2 passes → Update T001/index.json
5. All T001 children pass → Run T001 integration tests
6. T001 passes → Update master-index.json
7. Continue to next module...
```

### Step 6.5: Integration Checklist

For each integration level:

**Before running integration tests:**
- [ ] All child tasks have `passes: true`
- [ ] All child unit tests pass
- [ ] Interface contracts are implemented
- [ ] Test environment is set up

**After running integration tests:**
- [ ] Integration tests pass
- [ ] Quality gates pass (`typecheck`, `lint`)
- [ ] Documentation updated
- [ ] Parent `index.json` updated with test results

---

## Workflow Decision Tree

```
START
  │
  ├─ Is this a simple fix (< 1 hour)?
  │   └─ YES → Execute directly, skip planning
  │
  ├─ Is this a single feature (< 1 week)?
  │   └─ YES → Phase 1-4, single-level tasks
  │
  ├─ Is this a complex system (> 1 week)?
  │   └─ YES → Full workflow with multi-level decomposition
  │
  └─ Is this ambiguous?
      └─ Ask clarifying questions first
```

---

## Output Files Summary

| Phase | Output | Location | Description |
|-------|--------|----------|-------------|
| Phase 1 | requirements.md | ./docs/requirements/ | Project requirements document |
| Phase 2 | master-index.json | ./tasks/ | Level 0: Main task index |
| Phase 3 | prd.md | ./tasks/T00X/ | Task PRD (at each level) |
| Phase 4 | index.json | ./tasks/T00X/ | Child task index (parent tasks) |
| Phase 4 | tasks.json | ./tasks/T00X/ | Task list with userStories (leaf tasks) |
| Phase 5 | status updates | In JSON files | Real-time status propagation |
| Phase 6 | integration_tests | In index.json | Parent-level test requirements |

### File Structure Reference

```
tasks/
├── master-index.json              # Main task index
│
├── T001/                          # Main task
│   ├── prd.md                     # T001 PRD
│   ├── index.json                 # T001 children index + integration_tests
│   │
│   ├── T001-1/                    # Subtask (nested)
│   │   ├── prd.md
│   │   ├── index.json             # If T001-1 has children
│   │   │
│   │   ├── T001-1-1/              # Deeper nesting
│   │   │   ├── prd.md
│   │   │   └── tasks.json         # Leaf: actual userStories
│   │   │
│   │   └── T001-1-2/
│   │       ├── prd.md
│   │       └── tasks.json
│   │
│   └── T001-2/                    # Another subtask
│       ├── prd.md
│       └── tasks.json             # Leaf: no children
│
├── T002/
│   ├── prd.md
│   └── tasks.json                 # Leaf: no decomposition needed
│
└── T003/
    └── ...
```

---

## Quality Checklist

Before each phase transition:

- [ ] Current phase deliverables complete
- [ ] Stakeholder sign-off obtained (if applicable)
- [ ] No blocking questions remain
- [ ] Next phase inputs are ready

---

## Related Skills

- **brainstorming** - For requirement exploration and divergence
- **task-decomposition** - For breaking down complex tasks
- **ralph-tui-prd** - PRD template reference
- **ralph-tui-create-json** - JSON schema reference
- **ralph-wiggum:ralph-loop** - Execution loop pattern