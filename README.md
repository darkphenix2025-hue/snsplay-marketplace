# snsplay-marketplace

Curated Claude Code plugins for productivity and development workflows.

## Installation

Add this marketplace to Claude Code:

```bash
/plugin marketplace add darkphenix2025-hue/snsplay-marketplace
```

## Available Plugins

### Superpowers (Core)

**Description:** Core skills library with TDD, debugging, collaboration patterns, and proven techniques

**Categories:** Testing, Debugging, Collaboration, Meta

**Install:**
```bash
/plugin install superpowers@snsplay-marketplace
```

**What you get:**
- 20+ battle-tested skills
- `/brainstorm`, `/write-plan`, `/execute-plan` commands
- Skills-search tool for discovery
- SessionStart context injection

**Repository:** https://github.com/obra/superpowers

---

## Marketplace Structure

```
snsplay-marketplace/
├── .claude-plugin/
│   └── marketplace.json       # Plugin catalog
└── README.md                  # This file
```

## Adding New Plugins

To add a new plugin to this marketplace:

1. Fork this repository
2. Edit `.claude-plugin/marketplace.json` and add your plugin entry
3. Update `README.md` with the plugin description
4. Submit a pull request

### Plugin Entry Format

```json
{
  "name": "your-plugin-name",
  "source": {
    "source": "url",
    "url": "https://github.com/yourusername/your-repo.git"
  },
  "description": "Brief description of your plugin",
  "version": "1.0.0",
  "strict": true
}
```

## Support

- **Issues**: https://github.com/darkphenix2025-hue/snsplay-marketplace/issues

## License

Marketplace metadata: MIT License

Individual plugins: See respective plugin licenses
