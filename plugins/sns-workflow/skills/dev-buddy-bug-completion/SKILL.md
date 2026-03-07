---
name: dev-buddy-bug-completion
description: Completion stage for bug-fix pipeline. Finalizes fix, runs verification, generates report.
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, TeamDelete, AskUserQuestion
---

# Bug-Fix Completion Stage

You are the Completion stage of the bug-fix pipeline. Your job is to verify the fix, clean up, and generate a summary.

## INPUT

- `.vcp/task/pipeline-tasks.json` — final state
- `.vcp/task/impl-result.json` — implementation result
- All code review outputs

## OUTPUT

- Final verification report
- Pipeline cleanup

## PROCEDURE

### Step 0: Verify All Stages Complete

Check that all reviews are approved:

```bash
bun -e "
  const { readFileSync, readdirSync } = require('fs');
  const dir = '${CLAUDE_PROJECT_DIR}/.vcp/task';

  const codeReviews = readdirSync(dir)
    .filter(f => f.startsWith('code-review-') && f.endsWith('.json'))
    .map(f => JSON.parse(readFileSync(\`\${dir}/\${f}\`, 'utf-8')));

  const allApproved = codeReviews.every(r => r.status === 'approved');
  console.log(JSON.stringify({ allApproved, code_reviews: codeReviews.length }));
"
```

### Step 1: Run Final Verification

Execute full test suite:

```bash
npm test
```

**If tests fail:** Report and ask user to proceed or fix.

### Step 2: Generate Summary

```bash
bun -e "
  const { readFileSync } = require('fs');
  const { join } = require('path');
  const dir = '${CLAUDE_PROJECT_DIR}/.vcp/task';

  const userStory = JSON.parse(readFileSync(join(dir, 'user-story', 'manifest.json'), 'utf-8'));
  const requirements = JSON.parse(readFileSync(join(dir, 'user-story', 'requirements.json'), 'utf-8'));
  const plan = JSON.parse(readFileSync(join(dir, 'plan', 'manifest.json'), 'utf-8'));
  const impl = JSON.parse(readFileSync(join(dir, 'impl-result.json'), 'utf-8'));

  const summary = {
    pipeline_type: 'bug-fix',
    bug: {
      title: userStory.title,
      root_cause: requirements.root_cause,
      root_file: requirements.root_file,
      root_line: requirements.root_line
    },
    fix: {
      step_count: plan.step_count,
      files_changed: impl.changes_made?.length || 0,
      tests_passed: impl.tests_passed
    },
    timestamp: new Date().toISOString()
  };

  console.log(JSON.stringify(summary, null, 2));
"
```

### Step 3: Display Summary

```
## Bug Fix Complete

**Issue:** {title}
**Root Cause:** {root_cause}
**Location:** {root_file}:{root_line}

### Fix Summary
- Steps: {step_count}
- Files Changed: {files_changed}
- Tests: {passed/failed}

### Verification
- All code reviews approved
- Test suite passed

### Next Steps
- Review the fix: git diff
- Commit: git add . && git commit -m "fix: {description}"
- Consider adding regression test to CI
```

### Step 4: Write Final Report

```bash
# Write pipeline-complete.json
bun -e "
  const { writeFileSync } = require('fs');
  const report = { ...summary };
  writeFileSync('${CLAUDE_PROJECT_DIR}/.vcp/task/pipeline-complete.json', JSON.stringify(report, null, 2));
"
```

### Step 5: Cleanup Team

```
TeamDelete(team_name: "<team_name>")
```

### Step 6: Return Status

```json
{
  "status": "complete",
  "message": "Bug fix verified and complete",
  "root_cause": "{root_cause}",
  "tests_passed": true
}
```

## VERIFICATION CHECKLIST

- [ ] Root cause fixed
- [ ] Regression test passes
- [ ] All existing tests pass
- [ ] Code reviews approved
- [ ] No new issues introduced

## ERROR HANDLING

- If tests fail: Report failure, suggest fix
- If TeamDelete fails: Log warning, continue
- If verification fails: Report details to user