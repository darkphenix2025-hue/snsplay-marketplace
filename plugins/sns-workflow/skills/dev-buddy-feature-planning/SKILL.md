---
name: dev-buddy-feature-planning
description: Planning stage for feature pipeline. Creates implementation plan from user story.
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, TaskOutput, AskUserQuestion
---

# Planning Stage

You are the Planning stage of the feature pipeline. Your job is to create a detailed implementation plan from the user story.

## INPUT

- `.vcp/task/user-story/manifest.json` — user story manifest
- `.vcp/task/user-story/acceptance-criteria.json` — acceptance criteria
- `.vcp/task/user-story/scope.json` — scope and affected files

## OUTPUT

- `.vcp/task/plan/manifest.json` — plan manifest with step count
- `.vcp/task/plan/steps/*.json` — individual step files

## PROCEDURE

### Step 0: Verify Prerequisites

Check that user story exists:

```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/stage-executor.ts" validate --output "user-story/manifest.json" --type requirements
```

**If invalid:** STOP. Requirements stage must complete first.

### Step 1: Read User Story

Read the user story multi-file artifact:

```bash
bun -e "
  const { readFileSync } = require('fs');
  const { join } = require('path');
  const dir = '${CLAUDE_PROJECT_DIR}/.vcp/task/user-story';

  const manifest = JSON.parse(readFileSync(join(dir, 'manifest.json'), 'utf-8'));
  const ac = JSON.parse(readFileSync(join(dir, 'acceptance-criteria.json'), 'utf-8'));
  const scope = JSON.parse(readFileSync(join(dir, 'scope.json'), 'utf-8'));

  console.log(JSON.stringify({ manifest, ac, scope }, null, 2));
"
```

### Step 2: Analyze Scope

Review the scope to understand:

1. Affected files and directories
2. Technical constraints
3. Dependencies to consider
4. Blast radius of changes

### Step 3: Spawn Planner Agent

Execute the planner agent:

```
Task(
  subagent_type: "dev-buddy:planner",
  model: "opus",
  prompt: "Create implementation plan for: {title}

    ACCEPTANCE CRITERIA:
    {paste acceptance_criteria.json}

    SCOPE:
    {paste scope.json}

    Read the full user story from .vcp/task/user-story/
    Write plan multi-file artifact to .vcp/task/plan/

    Requirements:
    - Each step must be atomic and testable
    - Steps should be ordered for incremental progress
    - Include test commands for verification
    - Identify files to modify per step"
)
```

### Step 4: Validate Output

Check the plan manifest:

```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/stage-executor.ts" validate --output "plan/manifest.json" --type planning
```

**Validation criteria:**
- `step_count` > 0
- Each step file exists with valid structure
- `completion_promise` is defined

### Step 5: Return Status

```
{ "status": "complete", "message": "Plan created with {step_count} steps" }
```

## ERROR HANDLING

- If planner fails: Report error and ask user for guidance
- If validation fails: Re-run planner with specific feedback

## OUTPUT FORMAT

The plan/manifest.json structure:

```json
{
  "id": "plan-YYYYMMDD-HHMMSS",
  "title": "Plan title",
  "artifact": "plan",
  "step_count": 5,
  "sections": {
    "meta": "meta.json",
    "steps": ["steps/1.json", "steps/2.json", ...],
    "test_plan": "test-plan.json",
    "risk_assessment": "risk-assessment.json",
    "dependencies": "dependencies.json",
    "files": "files.json"
  }
}
```