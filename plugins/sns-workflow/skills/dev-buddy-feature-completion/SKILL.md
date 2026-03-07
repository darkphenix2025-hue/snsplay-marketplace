---
name: dev-buddy-feature-completion
description: Completion stage for feature pipeline. Cleans up resources, generates final report.
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, TeamDelete, AskUserQuestion
---

# Completion Stage

You are the Completion stage of the feature pipeline. Your job is to finalize the pipeline, clean up resources, and generate a summary report.

## INPUT

- `.vcp/task/pipeline-tasks.json` — final pipeline state
- All stage output files

## OUTPUT

- Pipeline summary report
- Cleanup of team resources

## PROCEDURE

### Step 0: Verify All Stages Complete

Check that all stages have approved/complete status:

```bash
bun -e "
  const { readFileSync } = require('fs');
  const state = JSON.parse(readFileSync('${CLAUDE_PROJECT_DIR}/.vcp/task/pipeline-tasks.json', 'utf-8'));

  const results = state.stages.map(s => {
    const outputPath = '${CLAUDE_PROJECT_DIR}/.vcp/task/' + s.output_file;
    try {
      const data = JSON.parse(readFileSync(outputPath, 'utf-8'));
      return { type: s.type, status: data.status || 'unknown' };
    } catch {
      return { type: s.type, status: 'missing' };
    }
  });

  const allComplete = results.every(r =>
    r.status === 'approved' || r.status === 'complete'
  );

  console.log(JSON.stringify({ allComplete, stages: results }));
"
```

**If not all complete:** Report incomplete stages, ask user to proceed or continue pipeline.

### Step 1: Generate Summary Report

Collect all artifacts and create summary:

```bash
bun -e "
  const { readFileSync, readdirSync } = require('fs');
  const { join } = require('path');
  const dir = '${CLAUDE_PROJECT_DIR}/.vcp/task';

  // Read user story
  const userStory = JSON.parse(readFileSync(join(dir, 'user-story', 'manifest.json'), 'utf-8'));

  // Read plan
  const plan = JSON.parse(readFileSync(join(dir, 'plan', 'manifest.json'), 'utf-8'));

  // Read implementation result
  const impl = JSON.parse(readFileSync(join(dir, 'impl-result.json'), 'utf-8'));

  // Count code reviews
  const codeReviews = readdirSync(dir)
    .filter(f => f.startsWith('code-review-') && f.endsWith('.json'))
    .map(f => JSON.parse(readFileSync(join(dir, f), 'utf-8')));

  const summary = {
    pipeline_type: 'feature-implement',
    user_story: { title: userStory.title, ac_count: userStory.ac_count },
    plan: { step_count: plan.step_count },
    implementation: {
      status: impl.status,
      files_changed: impl.changes_made?.length || 0
    },
    code_reviews: {
      count: codeReviews.length,
      all_approved: codeReviews.every(r => r.status === 'approved')
    },
    timestamp: new Date().toISOString()
  };

  console.log(JSON.stringify(summary, null, 2));
"
```

### Step 2: Write Final Report

Create completion report:

```bash
# Write to .vcp/task/pipeline-complete.json
bun -e "
  const { writeFileSync } = require('fs');
  const report = ${summary JSON};
  writeFileSync('${CLAUDE_PROJECT_DIR}/.vcp/task/pipeline-complete.json', JSON.stringify(report, null, 2));
"
```

### Step 3: Display Summary

Show user the completion summary:

```
## Pipeline Complete

**Feature:** {title}
**Acceptance Criteria:** {ac_count} items
**Implementation Steps:** {step_count} steps
**Files Changed:** {files_changed}

### Code Reviews
- {count} reviews completed
- All approved: {all_approved}

### Next Steps
- Run full test suite: npm test
- Review changes: git diff
- Commit: git add . && git commit
```

### Step 4: Cleanup Team

Delete the pipeline team:

```
TeamDelete(team_name: "<team_name>")
```

**Ignore errors:** Team may already be cleaned up if session ended.

### Step 5: Return Status

```json
{
  "status": "complete",
  "message": "Pipeline completed successfully",
  "summary": { ... }
}
```

## CLEANUP ACTIONS

The completion stage ensures:

1. **Team cleanup:** TeamDelete removes all teammate processes
2. **State preservation:** `.vcp/task/` directory is preserved for reference
3. **Report generation:** `pipeline-complete.json` provides audit trail

## ERROR HANDLING

- If TeamDelete fails: Log warning, continue (non-critical)
- If summary generation fails: Create minimal report with error note

## MANUAL CLEANUP

If the pipeline needs to be reset:

```bash
bun "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrator.ts" reset --cwd "${CLAUDE_PROJECT_DIR}"
```