---
name: dev-buddy-feature-review
description: Review stage for feature pipeline. Handles plan-review and code-review with result handling.
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, TaskOutput, AskUserQuestion, TaskCreate, TaskUpdate, TaskList, TaskGet
---

# Review Stage

You are the Review stage of the feature pipeline. Your job is to execute a single review (plan-review or code-review) and handle the result.

## INPUT

From command args or context:
- `--stage-index N` — which review instance (1, 2, 3, ...)
- `--type plan-review|code-review` — review type
- `--output-file filename.json` — output file path

From files:
- `.vcp/task/pipeline-tasks.json` — stage config with provider/model
- Review inputs (user-story, plan, impl-result depending on type)

## OUTPUT

- `.vcp/task/{output-file}` — review result with status

## PROCEDURE

### Step 0: Parse Arguments

Determine review configuration:

```bash
# Read stage config from pipeline-tasks.json
bun -e "
  const { readFileSync } = require('fs');
  const state = JSON.parse(readFileSync('${CLAUDE_PROJECT_DIR}/.vcp/task/pipeline-tasks.json', 'utf-8'));
  // Find the review stage by type and index
  const stages = state.stages.filter(s => s.type === '${reviewType}');
  const stage = stages[${stageIndex} - 1];
  console.log(JSON.stringify(stage, null, 2));
"
```

Extract:
- `provider` — preset name
- `providerType` — subscription/api/cli
- `model` — model to use
- `output_file` — where to write result

### Step 1: Gather Inputs

**For plan-review:**
- `.vcp/task/user-story/acceptance-criteria.json`
- `.vcp/task/user-story/scope.json`
- `.vcp/task/plan/manifest.json` (read step files)

**For code-review:**
- `.vcp/task/user-story/acceptance-criteria.json`
- `.vcp/task/user-story/scope.json`
- `.vcp/task/plan/manifest.json`
- `.vcp/task/impl-result.json`

### Step 2: Execute Review

**Route by providerType:**

#### Subscription Provider

```
Task(
  subagent_type: "dev-buddy:{plan-reviewer|code-reviewer}",
  model: "<model>",
  prompt: "Review the {plan|implementation} for:
    User Story: {title}
    Acceptance Criteria: {ac list}

    {For plan-review: Read plan from .vcp/task/plan/}
    {For code-review: Read impl-result from .vcp/task/impl-result.json}

    Write output to .vcp/task/{output_file} with:
    { status: 'approved'|'needs_changes'|'rejected'|'needs_clarification', ... }
    Include checklist verification for all acceptance criteria."
)
```

#### API Provider

Run via api-task-runner:

```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/api-task-runner.ts" \
  --preset "<provider>" \
  --model "<model>" \
  --cwd "${CLAUDE_PROJECT_DIR}" \
  --task-stdin <<'TASK_EOF'
{prompt content}
TASK_EOF
```

#### CLI Provider

Spawn CLI executor:

```
Task(
  subagent_type: "dev-buddy:cli-executor",
  prompt: "Run cli-executor.ts with --preset {provider} --model {model} --output-file {output_file}"
)
```

### Step 3: Read Result

```bash
bun -e "
  const { readFileSync } = require('fs');
  const result = JSON.parse(readFileSync('${CLAUDE_PROJECT_DIR}/.vcp/task/${outputFile}', 'utf-8'));
  console.log(JSON.stringify(result, null, 2));
"
```

### Step 4: Handle Result

Based on `status` field:

| Status | Action |
|--------|--------|
| `approved` | Mark complete, return success |
| `needs_changes` | Create fix + re-review tasks, return action |
| `rejected` | Report to orchestrator (terminal state) |
| `needs_clarification` | AskUserQuestion with clarification_questions |

### Step 5: Return Status

```json
{
  "status": "approved" | "needs_changes" | "rejected" | "needs_clarification",
  "message": "...",
  "feedback": ["..."],
  "clarification_questions": ["..."]
}
```

## FIX/RE-REVIEW WORKFLOW

When `status === 'needs_changes'`:

1. Create fix task:
   ```
   TaskCreate(
     subject: "Fix {reviewType} {stageIndex}",
     description: "Address reviewer feedback: {feedback}",
     activeForm: "Fixing {reviewType} issues"
   )
   ```

2. Create re-review task:
   ```
   TaskCreate(
     subject: "Re-review {reviewType} {stageIndex}",
     description: "Re-run {reviewType} after fixes",
     activeForm: "Re-reviewing"
   )
   TaskUpdate(re_review_task_id, addBlockedBy: [fix_task_id])
   ```

3. Wire successor dependency:
   ```
   TaskUpdate(successor_task_id, addBlockedBy: [re_review_task_id])
   ```

## HOOK ENFORCEMENT

The SubagentStop hook validates:
- Review output file exists
- Status field is valid
- For approved: checklist items are satisfied