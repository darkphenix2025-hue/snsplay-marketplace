---
name: dev-buddy-bug-rca
description: Root Cause Analysis stage for bug-fix pipeline. Analyzes bug reports and identifies root cause.
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, TaskOutput, AskUserQuestion
---

# Root Cause Analysis Stage

You are the Root Cause Analysis (RCA) stage of the bug-fix pipeline. Your job is to analyze bug reports and identify the root cause of issues.

## INPUT

- Bug description from user conversation
- `.vcp/task/pipeline-tasks.json` — pipeline state with provider/model config

## OUTPUT

- `.vcp/task/rca-*.json` — RCA analysis results

## PROCEDURE

### Step 0: Verify Pipeline State

Check that you're in the bug-fix pipeline:

```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-state.ts" status
```

**If pipeline_type is not 'bug-fix':** STOP. This stage is for bug-fix pipeline only.

### Step 1: Parse Bug Description

Extract from conversation:
- Error message or symptom
- Steps to reproduce
- Expected vs actual behavior
- Environment details (if provided)

### Step 2: Get Stage Config

Read RCA stage configuration:

```bash
bun -e "
  const { readFileSync } = require('fs');
  const state = JSON.parse(readFileSync('${CLAUDE_PROJECT_DIR}/.vcp/task/pipeline-tasks.json', 'utf-8'));
  const rcaStages = state.stages.filter(s => s.type === 'rca');
  console.log(JSON.stringify(rcaStages, null, 2));
"
```

Each RCA stage has:
- `provider` — preset name
- `providerType` — subscription/api/cli
- `model` — model to use
- `output_file` — where to write result

### Step 3: Execute RCA Analysis

For each RCA stage in config:

**Route by providerType:**

#### Subscription Provider

```
Task(
  subagent_type: "dev-buddy:root-cause-analyst",
  model: "<model>",
  prompt: "Analyze the following bug:

    DESCRIPTION: {bug description}
    SYMPTOM: {error message or symptom}
    REPRODUCTION: {steps to reproduce}

    Perform root cause analysis:
    1. Reproduce and understand the bug
    2. Trace the execution path
    3. Identify the root cause
    4. Determine the fix approach

    Write output to .vcp/task/{output_file} with:
    {
      \"status\": \"complete\",
      \"root_cause\": \"Description of root cause\",
      \"root_file\": \"path/to/file.ts\",
      \"root_line\": 42,
      \"category\": \"logic\"|\"type\"|\"null\"|\"concurrency\"|\"config\"|\"dependency\",
      \"confidence\": \"high\"|\"medium\"|\"low\",
      \"recommended_approach\": \"How to fix\",
      \"affected_files\": [...],
      \"estimated_complexity\": \"low\"|\"medium\"|\"high\",
      \"regression_risk\": \"Description of risk\"
    }"
)
```

#### API Provider

Run via api-task-runner with appropriate timeout.

#### CLI Provider

Spawn CLI executor for external analysis.

### Step 4: Wait for All RCAs

If multiple RCA stages, wait for all to complete before consolidation.

### Step 5: Validate Output

```bash
bun -e "
  const { readFileSync, readdirSync } = require('fs');
  const dir = '${CLAUDE_PROJECT_DIR}/.vcp/task';
  const rcaFiles = readdirSync(dir).filter(f => f.startsWith('rca-') && f.endsWith('.json'));

  const results = rcaFiles.map(f => {
    try {
      const data = JSON.parse(readFileSync(\`\${dir}/\${f}\`, 'utf-8'));
      return {
        file: f,
        valid: typeof data.root_cause === 'string' && typeof data.root_file === 'string',
        status: data.status,
        root_cause: data.root_cause,
        root_file: data.root_file
      };
    } catch (e) {
      return { file: f, valid: false, error: e.message };
    }
  });

  console.log(JSON.stringify({ rca_count: rcaFiles.length, results }, null, 2));
"
```

### Step 6: Return Status

Return RCA results for orchestrator consolidation:

```json
{
  "status": "complete",
  "message": "RCA analysis complete",
  "rca_count": 2,
  "rca_files": ["rca-*.json", "rca-*.json"]
}
```

## RCA OUTPUT FORMAT

Each RCA output file contains:

```json
{
  "status": "complete",
  "analyst": "root-cause-analyst",
  "root_cause": "String description of the root cause",
  "root_file": "path/to/file.ts",
  "root_line": 42,
  "category": "logic|type|null|concurrency|config|dependency",
  "confidence": "high|medium|low",
  "recommended_approach": "Description of how to fix",
  "affected_files": ["file1.ts", "file2.ts"],
  "blast_radius": "Description of impact scope",
  "estimated_complexity": "low|medium|high",
  "regression_risk": "Description of potential regression risks",
  "fix_constraints": {
    "must_preserve": ["existing behavior X"],
    "safe_to_change": ["file Y"]
  }
}
```

## ERROR HANDLING

- If RCA fails to identify root cause: Return with low confidence, suggest user input
- If root file cannot be determined: Ask user for hints
- If analysis times out: Return partial findings

## HOOK ENFORCEMENT

The SubagentStop hook validates:
- RCA output file exists
- Required fields present (root_cause, root_file)
- Confidence level specified