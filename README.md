# Anytype Mind

> **A knowledge base that makes AI remember everything.** Built on Anytype, works with opencode, Claude Code, Codex, and Cursor.

[![Anytype](https://img.shields.io/badge/anytype-required-blue)](https://anytype.io)
[![MCP](https://img.shields.io/badge/anytype%20mcp-2025--11--08-green)](https://developers.anytype.io/docs/examples/featured/mcp)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

This repo is heavily inspired by <https://github.com/breferrari/obsidian-mind>.
And edited <https://github.com/imcvampire/anytype-mind> to work with opencode
---

## The Problem

AI assistants forget. Every session starts from zero -- no context on your goals, team, patterns, or wins. Knowledge never compounds.

## The Solution

Give the AI a structured brain in Anytype. Start a session, talk about your day, and the AI handles the rest -- typed objects, relations, performance tracking. Every conversation builds on the last.

---

## Quick Start

### 1. Set Up Anytype

1. Install and open [Anytype](https://anytype.io)
2. Create an API key: Settings > API Keys > Create new

### 2. Bootstrap the Space

```bash
ANYTYPE_API_KEY="your-key" bash setup/bootstrap.sh
```

This creates all types, properties, tags, and collections in your Anytype space.

### 3. Configure Your AI Tool

**opencode:**

```bash
# Edit opencode.json — replace <YOUR_API_KEY> with your Anytype API key
# AGENTS.md is already in place — opencode loads it automatically
opencode
```

Or add the MCP server to your global opencode config (`~/.config/opencode/opencode.json`):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "anytype": {
      "type": "local",
      "enabled": true,
      "command": ["npx", "-y", "@anyproto/anytype-mcp"],
      "environment": {
        "OPENAPI_MCP_HEADERS": "{\"Authorization\":\"Bearer <YOUR_API_KEY>\", \"Anytype-Version\":\"2025-11-08\"}"
      }
    }
  }
}
```

**Claude Code:**

```bash
cp SKILL.md CLAUDE.md
claude mcp add anytype -e OPENAPI_MCP_HEADERS='{"Authorization":"Bearer <KEY>", "Anytype-Version":"2025-11-08"}' -s user -- npx -y @anyproto/anytype-mcp
```

**Codex:**

```bash
cp SKILL.md AGENTS.md
# Add Anytype MCP to Codex settings (see setup/anytype-mcp-config.json)
```

**Cursor:**
Add to `.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "anytype": {
      "command": "npx",
      "args": ["-y", "@anyproto/anytype-mcp"],
      "env": {
        "OPENAPI_MCP_HEADERS": "{\"Authorization\":\"Bearer <KEY>\", \"Anytype-Version\":\"2025-11-08\"}"
      }
    }
  }
}
```

### 4. Start Using

```
/standup          # Morning kickoff
/dump <anything>  # Capture freeform info
wrap up           # End of session review
```

---

## Requirements

- [Anytype](https://anytype.io) desktop app (must be running for API access)
- One of: [opencode](https://opencode.ai), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://openai.com/codex), or [Cursor](https://cursor.com)
- Python 3 (for hook scripts)
- Node.js / npx (for Anytype MCP server)

---

## How It Works

All data lives as **typed Anytype objects** with properties and relations. AI agents interact via the **Anytype MCP server**, which exposes the Anytype API as MCP tools.

**12 object types** map your work: work notes, incidents, 1:1s, decisions, people, teams, competencies, PR analyses, review briefs, brain notes, brag entries, and thinking notes.

**Relations** connect everything: work notes link to people, teams, and competencies. When review season arrives, the relations on each competency are already the evidence trail.

**Lifecycle hooks** handle routing automatically:

| Hook | opencode | Claude Code |
|------|----------|-------------|
| Session start | `session.created` plugin event | `SessionStart` hook |
| Content routing | AGENTS.md classification table | `UserPromptSubmit` hook |
| Validate objects | `tool.execute.before` plugin event | `PostToolUse` hook |
| Backup transcript | `session.compacted` plugin event | `PreCompact` hook |
| End-of-session checklist | `session.idle` plugin event | `Stop` hook |

---

## Commands

14 slash commands in `.opencode/commands/` (also available in `.claude/commands/` for Claude Code/Cursor):

| Command | Purpose |
|---------|---------|
| `/standup` | Morning kickoff -- loads context, suggests priorities |
| `/dump` | Freeform capture -- routes everything to the right objects |
| `/wrap-up` | Session review -- verify objects, relations, spot wins |
| `/humanize` | Voice-calibrated editing |
| `/weekly` | Weekly synthesis -- patterns, North Star alignment |
| `/capture-1on1` | Capture 1:1 transcript into structured object |
| `/incident-capture` | Capture incident from Slack into objects |
| `/slack-scan` | Deep scan Slack for evidence |
| `/peer-scan` | Deep scan GitHub PRs for review prep |
| `/review-brief` | Generate review brief |
| `/self-review` | Write self-assessment |
| `/review-peer` | Write peer review |
| `/vault-audit` | Audit object integrity and relations |
| `/project-archive` | Mark project as completed |

---

## Subagents

8 specialized agents in `.opencode/agents/` (also in `.claude/agents/` for Claude Code/Cursor):

| Agent | Purpose |
|-------|---------|
| `brag-spotter` | Finds uncaptured wins |
| `context-loader` | Loads all context about a topic |
| `cross-linker` | Finds objects missing relations |
| `people-profiler` | Creates person objects from Slack |
| `review-prep` | Aggregates review evidence |
| `slack-archaeologist` | Full Slack reconstruction |
| `vault-librarian` | Object integrity maintenance |
| `review-fact-checker` | Verifies review claims |

---

## Project Structure

```
AGENTS.md             # opencode instructions (auto-loaded)
SKILL.md              # Master instructions (copy to CLAUDE.md for Claude Code)
README.md             # This file
opencode.json         # opencode: MCP config, plugin, permissions
vault-manifest.json   # Type/property schema
references/           # Shared reference docs
  anytype-mcp.md      # MCP tool reference
  type-schema.md      # Full type/property definitions
  markdown-conventions.md
  collection-views.md
  defuddle.md
setup/                # One-time setup
  bootstrap.sh        # Creates Anytype space schema
  anytype-mcp-config.json
.opencode/            # opencode integration
  agents/             # 8 subagents
  commands/           # 14 slash commands
  plugins/            # anytype-mind.js (hook equivalents)
  scripts/            # Hook scripts
.claude/              # Claude Code / Cursor integration
  settings.json       # Hooks configuration
  commands/           # 14 slash commands (same as .opencode/commands/)
  agents/             # 8 subagents (same as .opencode/agents/)
  scripts/            # Hook scripts (same as .opencode/scripts/)
```

---

## License

MIT
