---
name: dev-buddy-feature-requirements
description: Requirements gathering stage for feature pipeline. Spawns specialist team, collects analysis, synthesizes user story.
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, TaskOutput, SendMessage, AskUserQuestion, TaskCreate, TaskUpdate, TaskList, TaskGet
---

# Requirements Gathering Stage

You are the Requirements Gathering stage of the feature pipeline. Your job is to coordinate specialist teammates, collect their analysis, and synthesize a user story.

## INPUT

- `.vcp/task/pipeline-tasks.json` — pipeline state with `team_name`
- `.vcp/task/pipeline-state.json` — current phase info
- User's initial request (from conversation context)

## OUTPUT

- `.vcp/task/user-story/manifest.json` — user story manifest with AC count
- `.vcp/task/analysis-*.json` — specialist analysis files

## PROCEDURE

### Step 0: Verify Pipeline State

Check that pipeline state exists and you're in the correct phase:

```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-state.ts" status
```

**If no state exists:** STOP. The main orchestrator should have initialized the pipeline.

**If phase is not `requirements_gathering` or `requirements_team_pending`:** Report to user that this stage was invoked at the wrong time.

### Step 1: Analyze the Request

Review the user's feature request from the conversation. Determine scope:

1. What is the core functionality being requested?
2. What areas of the codebase are likely affected?
3. Are there any domain-specific concerns (security, performance, UX)?

### Step 2: VCP Detection

Detect whether VCP is configured for security analyst:

```bash
bun -e "
  const fs = require('fs');
  const path = require('path');
  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();

  // Try .vcp/config.json first
  let configPath = path.join(projectDir, '.vcp', 'config.json');
  if (!fs.existsSync(configPath)) {
    configPath = path.join(projectDir, '.vcp.json'); // legacy fallback
  }

  if (!fs.existsSync(configPath)) {
    console.log(JSON.stringify({ vcp_detected: false }));
    process.exit(0);
  }

  try {
    const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
    const pluginRoot = config.pluginRoot;

    if (!pluginRoot) {
      console.log(JSON.stringify({ vcp_detected: false }));
      process.exit(0);
    }

    // Validate pluginRoot path
    if (!pluginRoot.includes('/.claude/') && !pluginRoot.includes('\\\\.claude\\\\')) {
      console.log(JSON.stringify({ vcp_detected: false }));
      process.exit(0);
    }

    // Check for vcp-context-core.ts
    const corePath = path.join(pluginRoot, 'lib', 'vcp-context-core.ts');
    if (!fs.existsSync(corePath)) {
      console.log(JSON.stringify({ vcp_detected: false }));
      process.exit(0);
    }

    // Run VCP context CLI
    const { execSync } = require('child_process');
    const output = execSync(\`bun \"\${pluginRoot}/lib/generate-context.ts\" \"\${projectDir}\"\`, { encoding: 'utf-8' });

    if (output.startsWith('## VCP Standards Context')) {
      console.log(JSON.stringify({ vcp_detected: true, vcp_context: output }));
    } else {
      console.log(JSON.stringify({ vcp_detected: false }));
    }
  } catch (e) {
    console.log(JSON.stringify({ vcp_detected: false, error: e.message }));
  }
"
```

Store `vcp_detected` and `vcp_context` (if available) for the Security Analyst prompt.

### Step 3: Spawn Specialist Teammates [PARALLEL OK]

Read `team_name` from `.vcp/task/pipeline-tasks.json` and spawn all 5 core specialists simultaneously:

| Specialist | Output File |
|-----------|-------------|
| Technical Analyst | `analysis-technical.json` |
| UX/Domain Analyst | `analysis-ux-domain.json` |
| Security Analyst | `analysis-security.json` |
| Performance Analyst | `analysis-performance.json` |
| Architecture Analyst | `analysis-architecture.json` |

Spawn each specialist using Task tool:

```
Task(
  name: "technical-analyst",
  team_name: <team_name>,
  subagent_type: "general-purpose",
  model: "opus",
  prompt: "You are a Technical Analyst. Explore the codebase for [feature].
           Focus on: existing code, patterns, constraints, dependencies, files to change.
           Write findings to .vcp/task/analysis-technical.json with format:
           { \"specialist\": \"technical\", \"findings\": [...], \"constraints\": [...], \"questions_for_user\": [...] }
           Message key findings to the lead as you discover them."
)
```

**Security Analyst (VCP-aware):** If `vcp_detected == true`, include VCP standards in prompt.

### Step 4: Spawn Verification Gate

After ALL Task calls return:

1. Build `spawned_specialists` list (successful spawns)
2. Build `failed_specialists` list (failed spawns)

**If ANY failed:** STOP and escalate:

```
AskUserQuestion:
  "{N} of {TOTAL} specialists failed to spawn: {failed names}.
   Options:
   1. Retry the failed specialists
   2. Continue with remaining specialists
   3. Abort requirements gathering"
```

### Step 5: Interactive Loop [INTERACTIVE LOOP]

Relay messages between specialists and the user:

1. Receive incoming messages from specialists (automatic)
2. Summarize specialist questions → call `AskUserQuestion`
3. **WAIT** for user's answer
4. Call `SendMessage` to relay answer to relevant specialist(s)
5. Repeat until specialists stop sending new messages

**Exit condition:** All analysis files are present OR specialists have gone idle.

### Step 6: Validate Analysis Files

Check for all analysis files:

```bash
bun -e "
  const { readdirSync, readFileSync } = require('fs');
  const { join } = require('path');
  const dir = '${CLAUDE_PROJECT_DIR}/.vcp/task';
  const files = readdirSync(dir).filter(f => f.startsWith('analysis-') && f.endsWith('.json'));
  const results = files.map(f => {
    try {
      const data = JSON.parse(readFileSync(join(dir, f), 'utf-8'));
      const valid = typeof data.specialist === 'string' && Array.isArray(data.findings);
      return { file: f, valid, specialist: data.specialist, findings_count: data.findings?.length ?? 0 };
    } catch (e) { return { file: f, valid: false, error: e.message }; }
  });
  console.log(JSON.stringify({ found: files, validated: results }, null, 2));
"
```

### Step 7: Synthesize via Requirements Gatherer

Spawn the requirements-gatherer agent to synthesize:

```
Task(
  subagent_type: "dev-buddy:requirements-gatherer",
  model: "opus",
  prompt: "Synthesis mode.
    APPROVED SPECIALISTS: {list from Step 4}
    VALIDATED ANALYSIS FILES: {paste validation output}

    Read the analysis files from .vcp/task/.
    Validate scope with user via AskUserQuestion.
    Write user-story multi-file artifact to .vcp/task/user-story/
    Get explicit approval before finalizing."
)
```

### Step 8: Verify Output

Validate the user-story manifest:

```bash
bun -e "
  const { readFileSync } = require('fs');
  const data = JSON.parse(readFileSync('${CLAUDE_PROJECT_DIR}/.vcp/task/user-story/manifest.json', 'utf-8'));
  const valid = typeof data.title === 'string' && typeof data.ac_count === 'number' && data.ac_count > 0;
  console.log(JSON.stringify({ valid, title: data.title, ac_count: data.ac_count }));
"
```

### Step 9: Shutdown Specialists

Send shutdown_request to all specialist teammates:

```
SendMessage(type: "shutdown_request", recipient: "technical-analyst", content: "Requirements complete")
SendMessage(type: "shutdown_request", recipient: "ux-domain-analyst", content: "Requirements complete")
SendMessage(type: "shutdown_request", recipient: "security-analyst", content: "Requirements complete")
SendMessage(type: "shutdown_request", recipient: "performance-analyst", content: "Requirements complete")
SendMessage(type: "shutdown_request", recipient: "architecture-analyst", content: "Requirements complete")
```

Wait ~60 seconds for confirmations. If any specialist is unresponsive after retry, proceed anyway.

### Step 10: Mark Complete

Return status to orchestrator:

```
{ "status": "complete", "message": "User story created with {ac_count} acceptance criteria" }
```

## ERROR HANDLING

- If synthesis fails: STOP and escalate to user
- If user-story validation fails: STOP and ask user to clarify requirements
- If specialists timeout: Report to user with partial findings

## HOOK ENFORCEMENT

The SubagentStop hook validates that `user-story/manifest.json` exists with valid structure before allowing the stage to complete.