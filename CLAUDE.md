# snsplay-marketplace

Claude Code plugin marketplace for productivity and development workflows.

## Project Structure

```
snsplay-marketplace/
├── .claude-plugin/marketplace.json  # Plugin catalog
├── plugins/sns-workflow/            # Main workflow plugin
│   ├── agents/                      # Agent definitions
│   ├── skills/                      # Skill definitions
│   ├── hooks/                       # Hook configurations
│   └── scripts/                     # Utility scripts
├── skills/                          # Shared skill library (24 skills)
└── tasks/                           # Task management system
```

## Installation

Add marketplace to Claude Code:
```bash
/plugin marketplace add darkphenix2025-hue/snsplay-marketplace
```

Install plugins:
```bash
/plugin install superpowers@snsplay-marketplace
/plugin install sns-workflow@snsplay-marketplace
```

## Available Skills

### Core Workflow
| Skill | Command | Purpose |
|-------|---------|---------|
| Brainstorming | `/brainstorming` | Expand ideas and escape convergent thinking |
| Task Decomposition | `/task-decomposition` | Break requirements into tasks |
| TDD Workflow | `/tdd-workflow` | Test-driven development |
| Commit & PR | `/commit-push-pr` | Git commit and PR workflow |

### Product Design
| Skill | Command | Purpose |
|-------|---------|---------|
| Requirements Analysis | `/requirements-analysis` | Initial requirement gathering |
| Architecture Decomposition | `/architecture-decomposition` | Split into architecture units |
| Technical Design | `/technical-design` | Technical planning |

## Agents (sns-workflow)

- **planner**: Creates implementation plans
- **implementer**: Executes implementation tasks
- **code-reviewer**: Reviews code quality
- **root-cause-analyst**: Bug diagnosis
- **requirements-gatherer**: Collects user requirements

## Task System

Tasks are organized in `tasks/` directory:
- `master-index.json`: Project overview with dependencies
- `T001-T006/`: Individual task folders with `tasks.json`

Task workflow:
1. Check `tasks/master-index.json` for project overview
2. Navigate to task folder for detailed user stories
3. Use `/task-execution` to implement tasks

## Hooks Configuration

Hooks in `plugins/sns-workflow/hooks/hooks.json`:
- **UserPromptSubmit**: Guidance hook for workflow enforcement
- **SubagentStop**: Review validator for subagent outputs

## Development

### Local Development Workflow (Recommended)

Use `--plugin-dir` flag to load plugins locally without marketplace installation:

```bash
# Test sns-workflow plugin
cc --plugin-dir /projects/snsplay-marketplace/plugins/sns-workflow

# Test specific plugin directory
cc --plugin-dir /path/to/plugin-name
```

**Development cycle:**
```
Edit skill/agent files → cc --plugin-dir <path> → Test triggers → Iterate
```

**No need to:**
- Update marketplace.json during development
- Run `/plugin install` after each change
- Push changes to test locally

### Debugging Tips

```bash
# Add debug output in skills/commands
!`echo "Plugin root: ${CLAUDE_PLUGIN_ROOT}"`
!`ls -la ${CLAUDE_PLUGIN_ROOT}/scripts/`

# Test commands from different directories
cd /tmp && claude /command-name
```

### Project Structure Notes

This is a plugin development project. Key files:
- `marketplace.json`: Plugin catalog configuration
- `skills/*/SKILL.md`: Skill definitions
- `plugins/sns-workflow/agents/*.md`: Agent definitions

When ready to publish:
1. Update version in `marketplace.json`
2. Commit and push changes
3. Users can then install via marketplace

## Notes

- Skills use `bun` as runtime for scripts
- Tasks support parallel execution (see `parallel_groups` in master-index)
- Skills are bilingual (Chinese descriptions in skills/README.md)

## Gstack

**IMPORTANT**: For all web browsing tasks, ALWAYS use the `/gstack` skill with the `/browse` command. NEVER use `mcp__claude-in-chrome__*` tools.

**Project Install**: gstack is installed in `.claude/skills/gstack/` for this project. Teammates and collaborators automatically have access to all gstack skills when working in this repo.

**Troubleshooting**: If gstack skills aren't working, run `cd .claude/skills/gstack && ./setup` to rebuild binaries and register skills.

### Available Gstack Skills

| Skill | Command | Purpose |
|-------|---------|---------|
| **Browse** | `/gstack` | QA testing, user flow verification, screenshots, responsive testing |
| **QA** | `/qa` | Full QA testing workflow |
| **QA Only** | `/qa-only` | QA testing only |
| **Investigate** | `/investigate` | Debug and diagnose issues |
| **Autoplan** | `/autoplan` | Automatic full review pipeline |
| **Plan CEO Review** | `/plan-ceo-review` | Scope & strategy review |
| **Plan Eng Review** | `/plan-eng-review` | Architecture & code review (required) |
| **Plan Design Review** | `/plan-design-review` | UI/UX review |
| **Design Consultation** | `/design-consultation` | Design consultation |
| **Design Review** | `/design-review` | Design review |
| **Review** | `/review` | Code review |
| **Codex** | `/codex` | Independent second opinion |
| **Ship** | `/ship` | Ship features |
| **Land and Deploy** | `/land-and-deploy` | Merge and deploy |
| **Canary** | `/canary` | Canary testing |
| **Benchmark** | `/benchmark` | Performance benchmarks |
| **Setup Browser Cookies** | `/setup-browser-cookies` | Configure browser cookies |
| **Setup Deploy** | `/setup-deploy` | Configure deployment |
| **Retro** | `/retro` | Retrospective |
| **Document Release** | `/document-release` | Release documentation |
| **CSO** | `/cso` | CSO related |
| **Office Hours** | `/office-hours` | Office hours |
| **Careful** | `/careful` | Careful mode |
| **Guard** | `/guard` | Guard mode |
| **Freeze** | `/freeze` | Freeze code |
| **Unfreeze** | `/unfreeze` | Unfreeze code |
| **Gstack Upgrade** | `/gstack-upgrade` | Upgrade gstack |