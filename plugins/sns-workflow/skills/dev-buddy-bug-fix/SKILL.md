---
name: dev-buddy-bug-fix
description: Bug-fix pipeline orchestrator. Coordinates RCA, consolidation, and fix stages via sub-skills.
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Skill, TaskCreate, TaskUpdate, TaskList, TaskGet, TeamCreate, TeamDelete, AskUserQuestion
---

# Bug-Fix Pipeline Orchestrator

You coordinate the bug-fix pipeline by dispatching sub-skills for each stage. The bug-fix pipeline differs from feature: RCA stages run first, followed by orchestrator consolidation, then reviews and implementation.

**Task directory:** `${CLAUDE_PROJECT_DIR}/.vcp/task/`
**Agents location:** `${CLAUDE_PLUGIN_ROOT}/agents/`
**Sub-skills location:** `${CLAUDE_PLUGIN_ROOT}/skills/dev-buddy-bug-{stage}/`

---

## Architecture: Tasks + Hook Enforcement

| Component | Role |
|-----------|------|
| **Tasks** | Structural enforcement via `blockedBy`, user visibility, audit trail |
| **Sub-skills** | Stage-specific logic (RCA, planning, review, implementation, completion) |
| **Orchestrator** | Consolidation (inline after RCA), user input, dynamic tasks |

**Key insight:** `blockedBy` is *data*, not an instruction. Only claim tasks where blockedBy is empty or all dependencies completed.

---

## Pipeline Initialization

### Step 0: Resume Detection

```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-state.ts" status
```

**If `exists == false`:** Fresh run. Proceed to Step 1.

**If `exists == true` and `pipeline_type != "bug-fix"`:** Ask user to start fresh or use correct pipeline.

**For resume:** Re-create team and task chain, skip completed stages.

### Step 1: Reset & Validate

```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrator.ts" reset --cwd "${CLAUDE_PROJECT_DIR}"
bun "${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-config.ts" validate --cwd "${CLAUDE_PROJECT_DIR}"
```

### Step 2: Create Pipeline Team

```
TeamDelete(team_name: "pipeline-{BASENAME}-{HASH}")
TeamCreate(team_name: "pipeline-{BASENAME}-{HASH}", description: "Bug-fix pipeline")
```

### Step 3: Create Task Chain

Load bugfix_pipeline config and create tasks:

```bash
bun -e "
  import { loadPipelineConfig } from '${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-config.ts';
  const config = loadPipelineConfig();
  const pipeline = config.bugfix_pipeline;
  // ... compute stages with RCA, plan-review, implementation, code-review
"
```

### Step 4: Write Pipeline State

Write `.vcp/task/pipeline-tasks.json` with:
- `pipeline_type: "bug-fix"`
- `stages` array including RCA stages

---

## Main Loop

Execute until all tasks complete:

```
while pipeline not complete:
    1. TaskList() → find next pending task
    2. TaskGet(task.id) → read stage config
    3. TaskUpdate(task.id, status: "in_progress")

    4. DISPATCH SUB-SKILL based on stage type:
       - rca → Skill("dev-buddy-bug-rca")
       - plan-review → Skill("dev-buddy-bug-review", args="--type plan-review")
       - implementation → Skill("dev-buddy-bug-implementation")
       - code-review → Skill("dev-buddy-bug-review", args="--type code-review")

    5. RCA CONSOLIDATION CHECK:
       After RCA task completes, check if next stage is NOT rca:
       If true → Run consolidation BEFORE next task

    6. Handle result:
       - success → TaskUpdate(completed)
       - needs_changes → create fix + re-review
       - rejected → terminal state
```

---

## RCA Consolidation (Inline, NOT a Task)

**Trigger:** After completing an RCA task, check if it's the last consecutive RCA:

```
completedStageIndex = find index in stages where task_id matches
completedStage = stages[completedStageIndex]
nextStage = stages[completedStageIndex + 1]

if completedStage.type === 'rca' AND (nextStage === null OR nextStage.type !== 'rca'):
    → Run consolidation NOW
```

### Consolidation Steps

1. **Read All RCA Outputs:**
   ```
   rcaFiles = stages.filter(s => s.type === 'rca').map(s => s.output_file)
   Read each from .vcp/task/
   ```

2. **Merge Findings:**
   - If RCAs agree: use shared diagnosis
   - If RCAs disagree: AskUserQuestion for user choice

3. **Write user-story/ artifact:**
   - meta.json
   - requirements.json (with root_cause, root_file, root_line)
   - acceptance-criteria.json
   - scope.json
   - manifest.json

4. **Write plan/ artifact:**
   - Steps for: regression test, apply fix, verify
   - manifest.json

---

## Sub-Skill Dispatch

Dispatch sub-skills based on stage type:

| Stage Type | Sub-Skill |
|-----------|-----------|
| `rca` | `dev-buddy-bug-rca` |
| `plan-review` | `dev-buddy-bug-review --type plan-review --stage-index N` |
| `implementation` | `dev-buddy-bug-implementation` |
| `code-review` | `dev-buddy-bug-review --type code-review --stage-index N` |

After all stages complete:
```
Skill(skill: "dev-buddy-bug-completion")
```

---

## Result Handling

### RCA Stage
- **complete:** Continue to next RCA or consolidation
- **failed:** Report error, ask user for hints

### Plan Review
- **approved:** Proceed to implementation
- **needs_changes:** Fix plan and re-review

### Implementation
- **complete:** Proceed to code review
- **failed:** Report error, ask guidance

### Code Review
- **approved:** Pipeline complete
- **needs_changes:** Create fix + re-review tasks
- **rejected:** Terminal state

---

## Terminal States

| State | Action |
|-------|--------|
| `plan_rejected` | Ask user to revise RCA or abort |
| `code_rejected` | Ask user to revise fix or abort |
| `max_iterations_exceeded` | Escalate to user |

---

## Pipeline Completion

1. Dispatch completion sub-skill:
   ```
   Skill(skill: "dev-buddy-bug-completion")
   ```

2. Verify tests pass

3. Display summary

4. TeamDelete

---

## Key Differences from Feature Pipeline

1. **No requirements-gatherer:** Bug-fix uses RCA instead
2. **No planner:** Orchestrator consolidates RCA findings into plan
3. **Inline consolidation:** Not a sub-skill, orchestrator action
4. **Minimal fix principle:** Smallest possible change to address root cause

---

## Emergency Controls

- **Reset:** `bun orchestrator.ts reset --cwd <dir>`
- **Status:** `bun orchestrator.ts status --cwd <dir>`
- **Abort:** Ask user, then reset if confirmed