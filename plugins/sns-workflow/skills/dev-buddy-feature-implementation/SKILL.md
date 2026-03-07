---
name: dev-buddy-feature-implementation
description: Implementation stage for feature pipeline. Executes the plan and generates code.
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, TaskOutput, AskUserQuestion
---

# Implementation Stage

You are the Implementation stage of the feature pipeline. Your job is to execute the implementation plan and produce working code.

## INPUT

- `.vcp/task/user-story/manifest.json` — user story
- `.vcp/task/user-story/acceptance-criteria.json` — AC list
- `.vcp/task/plan/manifest.json` — implementation plan
- `.vcp/task/plan/steps/*.json` — step files

## OUTPUT

- `.vcp/task/impl-result.json` — implementation result with status

## PROCEDURE

### Step 0: Verify Prerequisites

Check that plan exists and is approved:

```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/stage-executor.ts" validate --output "plan/manifest.json" --type planning
```

**If invalid:** STOP. Planning stage must complete first.

Check that all plan-reviews passed:

```bash
bun -e "
  const { readFileSync, readdirSync } = require('fs');
  const dir = '${CLAUDE_PROJECT_DIR}/.vcp/task';
  const reviewFiles = readdirSync(dir).filter(f => f.startsWith('plan-review-') && f.endsWith('.json'));
  const results = reviewFiles.map(f => {
    const data = JSON.parse(readFileSync(\`\${dir}/\${f}\`, 'utf-8'));
    return { file: f, status: data.status };
  });
  const allApproved = results.every(r => r.status === 'approved');
  console.log(JSON.stringify({ allApproved, reviews: results }));
"
```

**If any plan-review is not approved:** STOP. Address reviewer feedback first.

### Step 1: Read Plan

Load the implementation plan:

```bash
bun -e "
  const { readFileSync } = require('fs');
  const { join } = require('path');
  const dir = '${CLAUDE_PROJECT_DIR}/.vcp/task/plan';

  const manifest = JSON.parse(readFileSync(join(dir, 'manifest.json'), 'utf-8'));
  const stepFiles = manifest.sections.steps;
  const steps = stepFiles.map((f, i) => {
    const step = JSON.parse(readFileSync(join(dir, f), 'utf-8'));
    return { index: i + 1, ...step };
  });

  console.log(JSON.stringify({ manifest, steps }, null, 2));
"
```

### Step 2: Get Provider Config

Read stage config for implementation:

```bash
bun -e "
  const { readFileSync } = require('fs');
  const state = JSON.parse(readFileSync('${CLAUDE_PROJECT_DIR}/.vcp/task/pipeline-tasks.json', 'utf-8'));
  const implStage = state.stages.find(s => s.type === 'implementation');
  console.log(JSON.stringify(implStage, null, 2));
"
```

Extract provider, providerType, and model.

### Step 3: Execute Implementation

**Route by providerType:**

#### Subscription Provider

```
Task(
  subagent_type: "dev-buddy:implementer",
  model: "<model>",
  prompt: "Implement the plan for: {title}

    STEPS:
    {steps list with files}

    Read full plan from .vcp/task/plan/
    Read user story from .vcp/task/user-story/

    Implementation rules:
    - Follow the plan steps in order
    - Each step must pass its tests before proceeding
    - Run tests after each change
    - Write output to .vcp/task/impl-result.json

    Output format:
    { status: 'complete'|'partial'|'failed', steps_completed: [...], changes_made: [...] }"
)
```

#### API Provider

Run via api-task-runner with background execution.

#### CLI Provider

Spawn CLI executor with appropriate flags.

### Step 4: Monitor Progress

For long-running implementations, poll the output file:

```bash
# Check implementation status periodically
bun -e "
  const { readFileSync, existsSync } = require('fs');
  const path = '${CLAUDE_PROJECT_DIR}/.vcp/task/impl-result.json';
  if (!existsSync(path)) {
    console.log(JSON.stringify({ status: 'running' }));
  } else {
    const result = JSON.parse(readFileSync(path, 'utf-8'));
    console.log(JSON.stringify(result));
  }
"
```

### Step 5: Validate Output

```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/stage-executor.ts" validate --output "impl-result.json" --type implementation
```

**Validation criteria:**
- `status` is one of: `complete`, `partial`, `failed`
- `changes_made` array exists with file paths

### Step 6: Handle Result

| Status | Action |
|--------|--------|
| `complete` | Return success, proceed to code-review |
| `partial` | Report progress, ask if should continue |
| `failed` | Report error, ask user for guidance |

### Step 7: Return Status

```json
{
  "status": "complete" | "partial" | "failed",
  "message": "Implementation {status}",
  "steps_completed": 5,
  "changes_made": ["path/to/file.ts", ...]
}
```

## ERROR HANDLING

- If implementer fails: Report error with context, ask user to proceed or abort
- If tests fail: Include test output, suggest fixes
- If partial: Show progress, ask to continue or adjust plan

## HOOK ENFORCEMENT

The SubagentStop hook validates:
- impl-result.json exists
- status field is valid
- For complete: at least one change was made