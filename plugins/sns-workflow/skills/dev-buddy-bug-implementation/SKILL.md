---
name: dev-buddy-bug-implementation
description: Implementation stage for bug-fix pipeline. Applies minimal fix and regression test.
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, TaskOutput, AskUserQuestion
---

# Bug-Fix Implementation Stage

You are the Implementation stage of the bug-fix pipeline. Your job is to apply the minimal fix and create a regression test.

## INPUT

- `.vcp/task/user-story/requirements.json` — root cause
- `.vcp/task/user-story/acceptance-criteria.json` — AC list
- `.vcp/task/plan/manifest.json` — fix plan

## OUTPUT

- `.vcp/task/impl-result.json` — implementation result

## PROCEDURE

### Step 0: Verify Prerequisites

Check that plan is approved:

```bash
bun -e "
  const { readFileSync, readdirSync } = require('fs');
  const dir = '${CLAUDE_PROJECT_DIR}/.vcp/task';
  const planReviews = readdirSync(dir).filter(f => f.startsWith('plan-review-') && f.endsWith('.json'));
  const results = planReviews.map(f => JSON.parse(readFileSync(\`\${dir}/\${f}\`, 'utf-8')));
  const allApproved = results.every(r => r.status === 'approved');
  console.log(JSON.stringify({ allApproved, reviews: results }));
"
```

### Step 1: Read Root Cause

```bash
bun -e "
  const { readFileSync } = require('fs');
  const req = JSON.parse(readFileSync('${CLAUDE_PROJECT_DIR}/.vcp/task/user-story/requirements.json', 'utf-8'));
  console.log(JSON.stringify(req, null, 2));
"
```

Key fields:
- `root_cause` — description
- `root_file` — file to fix
- `root_line` — line number

### Step 2: Read Fix Plan

Load the minimal fix plan.

### Step 3: Execute Implementation

**Route by providerType:**

```
Task(
  subagent_type: "dev-buddy:implementer",
  model: "<model>",
  prompt: "Apply the bug fix for:

    ROOT CAUSE: {root_cause}
    ROOT FILE: {root_file}:{root_line}

    PLAN STEPS:
    {steps}

    Implementation rules for bug fix:
    1. Apply MINIMAL change to address root cause
    2. First write a regression test that reproduces the bug
    3. Verify the test fails before the fix
    4. Apply the fix
    5. Verify the test passes after the fix
    6. Run ALL tests to ensure no regression

    Write output to .vcp/task/impl-result.json with:
    { status: 'complete', changes_made: [...], tests_passed: true }"
)
```

### Step 4: Validate Output

Check implementation result:

```bash
bun -e "
  const { readFileSync } = require('fs');
  const result = JSON.parse(readFileSync('${CLAUDE_PROJECT_DIR}/.vcp/task/impl-result.json', 'utf-8'));
  console.log(JSON.stringify(result, null, 2));
"
```

Required fields:
- `status`: complete/partial/failed
- `changes_made`: array of files
- `tests_passed`: boolean

### Step 5: Verify Tests

Run test suite:

```bash
npm test  # or appropriate test command
```

**If tests fail:** Report in impl-result with failure details.

### Step 6: Return Status

```json
{
  "status": "complete",
  "message": "Bug fix applied",
  "root_file": "{path/to/file}",
  "changes_made": ["..."],
  "tests_passed": true
}
```

## BUG-FIX IMPLEMENTATION RULES

1. **Minimal Change:** Only modify what's necessary to fix the root cause
2. **Regression Test First:** Write test that reproduces bug before fixing
3. **Preserve Behavior:** Don't change unrelated behavior
4. **No Refactoring:** Don't clean up surrounding code
5. **Test Everything:** Run full test suite after fix

## ERROR HANDLING

- If fix doesn't resolve bug: Report with details
- If tests fail: Include test output
- If regression test can't be written: Document why

## HOOK ENFORCEMENT

The SubagentStop hook validates:
- impl-result.json exists
- `tests_passed` is true (or documented why not)
- `changes_made` includes the root file