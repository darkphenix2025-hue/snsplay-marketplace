---
name: dev-buddy-bug-planning
description: Planning stage for bug-fix pipeline. Creates fix plan from RCA findings.
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, TaskOutput, AskUserQuestion
---

# Bug-Fix Planning Stage

You are the Planning stage of the bug-fix pipeline. Your job is to consolidate RCA findings and create a fix plan.

## INPUT

- `.vcp/task/rca-*.json` — RCA analysis results
- Bug description from conversation

## OUTPUT

- `.vcp/task/user-story/manifest.json` — bug-fix user story
- `.vcp/task/plan/manifest.json` — fix plan

## PROCEDURE

### Step 0: Verify RCA Complete

Check that all RCA stages are complete:

```bash
bun -e "
  const { readFileSync, readdirSync } = require('fs');
  const dir = '${CLAUDE_PROJECT_DIR}/.vcp/task';
  const rcaFiles = readdirSync(dir).filter(f => f.startsWith('rca-') && f.endsWith('.json'));
  const results = rcaFiles.map(f => {
    const data = JSON.parse(readFileSync(\`\${dir}/\${f}\`, 'utf-8'));
    return { file: f, status: data.status };
  });
  const allComplete = results.every(r => r.status === 'complete');
  console.log(JSON.stringify({ allComplete, rca_count: rcaFiles.length, results }));
"
```

**If not all complete:** STOP. Wait for RCA stages to finish.

### Step 1: Read All RCA Outputs

```bash
bun -e "
  const { readFileSync, readdirSync } = require('fs');
  const { join } = require('path');
  const dir = '${CLAUDE_PROJECT_DIR}/.vcp/task';
  const rcaFiles = readdirSync(dir).filter(f => f.startsWith('rca-') && f.endsWith('.json'));
  const rcaData = rcaFiles.map(f => ({
    file: f,
    ...JSON.parse(readFileSync(join(dir, f), 'utf-8'))
  }));
  console.log(JSON.stringify(rcaData, null, 2));
"
```

### Step 2: Consolidate Findings

**If all RCAs agree on root cause:**
- Use the shared diagnosis
- Take the most detailed explanation
- Merge affected files and constraints

**If RCAs disagree:**
- Present to user via AskUserQuestion
- Let user choose the correct diagnosis
- Or select "all contributing factors"

### Step 3: Write User Story

Create bug-fix user story:

```bash
# Write user-story sections
bun -e "
  const { writeFileSync, mkdirSync } = require('fs');
  const { join } = require('path');
  const dir = '${CLAUDE_PROJECT_DIR}/.vcp/task/user-story';
  mkdirSync(dir, { recursive: true });

  // meta.json
  writeFileSync(join(dir, 'meta.json'), JSON.stringify({
    id: 'story-' + Date.now(),
    title: 'Fix: {bug title}',
    pipeline_type: 'bug-fix'
  }, null, 2));

  // requirements.json
  writeFileSync(join(dir, 'requirements.json'), JSON.stringify({
    root_cause: '{consolidated root cause}',
    root_file: '{path/to/file}',
    root_line: 42
  }, null, 2));

  // acceptance-criteria.json
  writeFileSync(join(dir, 'acceptance-criteria.json'), JSON.stringify([
    { id: 'AC1', description: 'Bug is resolved — expected behavior restored' },
    { id: 'AC2', description: 'Regression test covers the exact bug scenario' },
    { id: 'AC3', description: 'No existing tests broken by the fix' },
    { id: 'AC4', description: 'Root cause addressed, not just symptoms patched' }
  ], null, 2));

  // scope.json
  writeFileSync(join(dir, 'scope.json'), JSON.stringify({
    affected_files: ['{merged from all RCAs}'],
    blast_radius: '{from RCA}',
    fix_constraints: {
      must_preserve: ['{merged constraints}'],
      safe_to_change: ['{merged safe changes}']
    }
  }, null, 2));

  // manifest.json (write LAST)
  writeFileSync(join(dir, 'manifest.json'), JSON.stringify({
    id: 'story-' + Date.now(),
    title: 'Fix: {bug title}',
    pipeline_type: 'bug-fix',
    artifact: 'user-story',
    ac_count: 4,
    sections: {
      meta: 'meta.json',
      requirements: 'requirements.json',
      acceptance_criteria: 'acceptance-criteria.json',
      scope: 'scope.json'
    }
  }, null, 2));
"
```

### Step 4: Write Fix Plan

Create minimal fix plan:

```bash
bun -e "
  const { writeFileSync, mkdirSync } = require('fs');
  const { join } = require('path');
  const planDir = '${CLAUDE_PROJECT_DIR}/.vcp/task/plan';
  const stepsDir = join(planDir, 'steps');
  mkdirSync(stepsDir, { recursive: true });

  // Step 1: Regression test
  writeFileSync(join(stepsDir, '1.json'), JSON.stringify({
    description: 'Write regression test that reproduces the bug',
    files: ['path/to/test.ts']
  }, null, 2));

  // Step 2: Apply fix
  writeFileSync(join(stepsDir, '2.json'), JSON.stringify({
    description: 'Apply minimal fix to {root_file} at line {root_line}',
    files: ['{root_file}']
  }, null, 2));

  // Step 3: Verify
  writeFileSync(join(stepsDir, '3.json'), JSON.stringify({
    description: 'Verify regression test passes, all existing tests pass',
    files: []
  }, null, 2));

  // Other plan sections...
  // test-plan.json, risk-assessment.json, dependencies.json, files.json

  // manifest.json (write LAST)
  writeFileSync(join(planDir, 'manifest.json'), JSON.stringify({
    id: 'plan-' + Date.now(),
    title: 'Fix: {bug title}',
    pipeline_type: 'bug-fix',
    artifact: 'plan',
    step_count: 3,
    sections: {
      meta: 'meta.json',
      steps: ['steps/1.json', 'steps/2.json', 'steps/3.json'],
      test_plan: 'test-plan.json',
      risk_assessment: 'risk-assessment.json',
      dependencies: 'dependencies.json',
      files: 'files.json'
    }
  }, null, 2));
"
```

### Step 5: Validate Output

```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/stage-executor.ts" validate --output "user-story/manifest.json" --type requirements
bun "${CLAUDE_PLUGIN_ROOT}/scripts/stage-executor.ts" validate --output "plan/manifest.json" --type planning
```

### Step 6: Return Status

```json
{
  "status": "complete",
  "message": "Fix plan created with {step_count} steps",
  "root_cause": "{consolidated root cause}",
  "root_file": "{path/to/file}"
}
```

## KEY PRINCIPLE

The fix plan must be the **smallest possible change** that addresses the root cause:
- No refactoring
- No cleanup beyond the fix itself
- Focus on the specific root cause identified

## ERROR HANDLING

- If RCAs conflict significantly: Escalate to user for decision
- If plan validation fails: Re-generate with specific guidance
- If user rejects plan: Iterate based on feedback