---
name: dev-buddy-feature-implement
description: Feature implementation pipeline orchestrator. Coordinates stages via sub-skills.
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Skill, TaskCreate, TaskUpdate, TaskList, TaskGet, TeamCreate, TeamDelete, AskUserQuestion
---

# Feature Pipeline Orchestrator

You coordinate the feature implementation pipeline by dispatching sub-skills for each stage.

**Task directory:** `${CLAUDE_PROJECT_DIR}/.vcp/task/`
**Agents location:** `${CLAUDE_PLUGIN_ROOT}/agents/`
**Sub-skills location:** `${CLAUDE_PLUGIN_ROOT}/skills/dev-buddy-feature-{stage}/`

---

## Orchestrator Execution Model

**STRICT SEQUENTIAL EXECUTION.** Execute ONE step at a time, WAIT for result, VERIFY, then proceed.

### Execution Rules (MANDATORY)

1. **ONE tool call per step.** Each step produces exactly ONE tool call.
2. **WAIT for return.** After each tool call, WAIT for the result.
3. **VERIFY before proceeding.** Check results. If failed, follow error handling.
4. **NEVER auto-recover.** If ANY operation fails: STOP and escalate via `AskUserQuestion`.
5. **User interruption means FULL STOP.** If user sends a message mid-pipeline, STOP and respond.

---

## Pipeline Initialization

### Step 0: Resume Detection

Check for existing pipeline:

```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-state.ts" status
```

**If `exists == false`:** Fresh run. Proceed to Step 1.

**If `exists == true`:** Check pipeline type compatibility. Ask user to resume or start fresh.

**For resume:** Re-create team, re-create task chain, enter main loop.

### Step 1: Reset Pipeline

```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrator.ts" reset --cwd "${CLAUDE_PROJECT_DIR}"
```

### Step 2: Validate Config

```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-config.ts" validate --cwd "${CLAUDE_PROJECT_DIR}"
```

### Step 3: Create Pipeline Team

Derive team name and create:

```
TeamDelete(team_name: "pipeline-{BASENAME}-{HASH}")  // ignore errors
TeamCreate(team_name: "pipeline-{BASENAME}-{HASH}", description: "Feature pipeline orchestration")
```

### Step 4: Create Task Chain

Load config and create task for each stage:

```bash
bun -e "
  import { loadPipelineConfig } from '${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-config.ts';
  import { STAGE_DEFINITIONS, getOutputFileName } from '${CLAUDE_PLUGIN_ROOT}/types/stage-definitions.ts';
  import { readPresets } from '${CLAUDE_PLUGIN_ROOT}/scripts/preset-utils.ts';
  const config = loadPipelineConfig();
  const presets = readPresets();
  const pipeline = config.feature_pipeline;
  // ... compute stages
"
```

For each stage, create a task:
```
TaskCreate(subject: deriveSubject(stage), description: deriveDescription(stage), activeForm: deriveActiveForm(stage))
```

Set dependencies via TaskUpdate.

### Step 5: Write Pipeline State

Write `.vcp/task/pipeline-tasks.json` with:
- `team_name`
- `pipeline_type: "feature-implement"`
- `config_hash`
- `resolved_config`
- `stages` array with task_id, output_file, etc.

---

## Main Loop

Execute until all tasks complete:

```
while pipeline not complete:
    1. TaskList() → find next pending task with resolved blockedBy
    2. TaskGet(task.id) → read stage config
    3. TaskUpdate(task.id, status: "in_progress")

    4. DISPATCH SUB-SKILL based on stage type:
       - requirements → Skill("dev-buddy-feature-requirements")
       - planning → Skill("dev-buddy-feature-planning")
       - plan-review → Skill("dev-buddy-feature-review", args="--type plan-review --stage-index N")
       - implementation → Skill("dev-buddy-feature-implementation")
       - code-review → Skill("dev-buddy-feature-review", args="--type code-review --stage-index N")

    5. Handle sub-skill result:
       - success → TaskUpdate(task.id, status: "completed")
       - needs_changes → create fix + re-review tasks
       - rejected → terminal state, ask user

    6. Check for parallel group completion:
       - If task has parallel_group_id, wait for all group members
       - Aggregate results before proceeding
```

### Parallel Execution

When multiple tasks share same `parallel_group_id`:

1. Dispatch all sub-skills simultaneously
2. Wait for all results
3. Aggregate handling

---

## Sub-Skill Dispatch

Dispatch sub-skills using the Skill tool:

```
Skill(skill: "dev-buddy-feature-requirements")
Skill(skill: "dev-buddy-feature-planning")
Skill(skill: "dev-buddy-feature-review", args: "--type plan-review --stage-index 1")
Skill(skill: "dev-buddy-feature-implementation")
Skill(skill: "dev-buddy-feature-review", args: "--type code-review --stage-index 1")
```

Each sub-skill:
- Reads required inputs from `.vcp/task/`
- Writes outputs to configured files
- Returns status to orchestrator

---

## Result Handling

### Requirements Stage
- **Success:** user-story/manifest.json created
- **Failure:** Ask user for clarification

### Planning Stage
- **Success:** plan/manifest.json created
- **Failure:** Re-run with feedback

### Review Stage
- **approved:** Mark complete, proceed
- **needs_changes:** Create fix + re-review tasks
- **rejected:** Terminal state, escalate to user
- **needs_clarification:** AskUserQuestion

### Implementation Stage
- **complete:** Proceed to code review
- **partial:** Ask user to continue
- **failed:** Report error, ask guidance

---

## Terminal States

| State | Trigger | Action |
|-------|---------|--------|
| `plan_rejected` | Plan rejected after max iterations | Ask user to revise requirements or abort |
| `code_rejected` | Code rejected after max iterations | Ask user to revise plan or abort |
| `max_iterations_exceeded` | Too many fix cycles | Escalate to user |

---

## Pipeline Completion

When all tasks complete:

1. Dispatch completion sub-skill:
   ```
   Skill(skill: "dev-buddy-feature-completion")
   ```

2. Display summary to user

3. TeamDelete to clean up

---

## Provider Routing

Sub-skills handle provider routing internally. The orchestrator passes stage config via args or pipeline state.

---

## Emergency Controls

- **Reset:** `bun orchestrator.ts reset --cwd <dir>`
- **Status:** `bun orchestrator.ts status --cwd <dir>`
- **Abort:** Ask user, then reset if confirmed