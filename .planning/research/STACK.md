# Stack Research

**Domain:** MCP server plugin with project-local configuration scoping
**Researched:** 2026-03-23
**Confidence:** HIGH

## Context

This is an upgrade to an existing plugin, not a greenfield project. The existing stack is Bun + discord.js + `@modelcontextprotocol/sdk`. The research question is specifically: how does an MCP server plugin discover its host session's project directory, and what patterns apply to project-scoped config?

## Key Finding: How MCP Servers Receive Project Context

Claude Code injects `CLAUDE_PROJECT_DIR` into the environment for hook commands (added in v1.0.58). The same variable is available as `${CLAUDE_PROJECT_DIR}` for substitution in `.mcp.json` `args` and `env` fields — confirmed by the official `stdio-server.json` example in the plugin-dev skill:

```json
{
  "filesystem": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-filesystem", "${CLAUDE_PROJECT_DIR}"]
  }
}
```

**The mechanism for MCP servers:** Pass the project directory as an environment variable via the `env` block in `.mcp.json`. The `${VAR}` substitution is performed by Claude Code before spawning the server process.

```json
{
  "mcpServers": {
    "discord": {
      "command": "bun",
      "args": ["run", "--cwd", "${CLAUDE_PLUGIN_ROOT}", "--shell=bun", "--silent", "start"],
      "env": {
        "DISCORD_PROJECT_DIR": "${CLAUDE_PROJECT_DIR}"
      }
    }
  }
}
```

The server reads `process.env.DISCORD_PROJECT_DIR` at startup. If the variable is absent (e.g., an old Claude Code version), it falls back to global-only behavior — fully backward compatible.

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Bun | existing | Runtime + package manager | Already in use; no justification to change |
| `@modelcontextprotocol/sdk` | existing | MCP stdio server | Already in use; standard SDK |
| discord.js | existing | Discord Gateway client | Already in use |
| Node.js `fs` (sync) | built-in | Read/write access.json at startup | Already used throughout server.ts; synchronous is fine at boot |

### Project-Scoped Config Pattern

The standard pattern for project-local plugin state in Claude Code plugins is `.claude/plugin-name.local.md` (YAML frontmatter + markdown body), documented in the `plugin-settings` skill. However, for this upgrade the existing `access.json` schema should be reused as-is — just in a different path. The `.local.md` pattern is a skill-layer convention; the MCP server itself reads JSON, not YAML.

**Chosen path:** `.claude/channels/discord/access.json` inside the project directory.

Why this path over `.claude/discord.local.json`:
- Mirrors the global path structure (`~/.claude/channels/discord/access.json`)
- The `/discord:access` skill already knows the path shape — adapting it to check the project-local variant is minimal
- Keeps all discord channel state under `channels/discord/`, whether global or local

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Node.js `path` | built-in | Construct local access.json path from `DISCORD_PROJECT_DIR` | Always — already imported |
| Node.js `fs.existsSync` | built-in | Check if local access.json exists before reading | At startup to determine active config |

No new dependencies required.

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `bun run --cwd ${CLAUDE_PLUGIN_ROOT} start` | Existing launch command | Do not change; the `--cwd` sets the server's working directory to the plugin root, not the project dir — this is why env var injection is necessary |

## Installation

No new packages. The change is purely:
1. One `env` field added to `.mcp.json`
2. ~10 lines added to `server.ts` startup to resolve the active access file path
3. Updated `/discord:access` SKILL.md to handle both global and local paths

## How to Modify `.mcp.json` to Pass Project Directory

**Current** (both 0.0.1 and 0.0.2 are identical):
```json
{
  "mcpServers": {
    "discord": {
      "command": "bun",
      "args": ["run", "--cwd", "${CLAUDE_PLUGIN_ROOT}", "--shell=bun", "--silent", "start"]
    }
  }
}
```

**Updated:**
```json
{
  "mcpServers": {
    "discord": {
      "command": "bun",
      "args": ["run", "--cwd", "${CLAUDE_PLUGIN_ROOT}", "--shell=bun", "--silent", "start"],
      "env": {
        "DISCORD_PROJECT_DIR": "${CLAUDE_PROJECT_DIR}"
      }
    }
  }
}
```

`${CLAUDE_PROJECT_DIR}` expands to the directory Claude Code was launched from (the project root). The MCP server process receives it as `process.env.DISCORD_PROJECT_DIR`.

## Server.ts Startup Logic

The server should resolve the active access file path once at startup:

```typescript
// Resolve active access.json: project-local overrides global.
// DISCORD_PROJECT_DIR is injected by Claude Code via .mcp.json env block.
const PROJECT_DIR = process.env.DISCORD_PROJECT_DIR
const LOCAL_ACCESS_FILE = PROJECT_DIR
  ? join(PROJECT_DIR, '.claude', 'channels', 'discord', 'access.json')
  : null

const ACTIVE_ACCESS_FILE = (() => {
  if (LOCAL_ACCESS_FILE) {
    try {
      statSync(LOCAL_ACCESS_FILE)  // throws if absent
      return LOCAL_ACCESS_FILE     // local wins
    } catch {}
  }
  return ACCESS_FILE               // global fallback
})()
```

Replace `ACCESS_FILE` with `ACTIVE_ACCESS_FILE` in all `readAccessFile()` / `saveAccess()` calls.

The server also needs to communicate which file is active so the `/discord:access` skill can display it and write to the right location.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `env` block in `.mcp.json` | Pass as CLI arg (`--project-dir`) | If the server accepted named CLI args — it doesn't; `bun run start` doesn't forward extra args to server.ts |
| `env` block in `.mcp.json` | Read from process.cwd() | Never — cwd is explicitly set to `CLAUDE_PLUGIN_ROOT` via `--cwd`, not the project directory |
| `env` block in `.mcp.json` | Use `CLAUDE_PROJECT_DIR` directly (no rename) | Works, but `DISCORD_PROJECT_DIR` is clearer and avoids shadowing the Claude-injected var if the name space changes |
| `.claude/channels/discord/access.json` (local) | `.claude/discord.local.json` | Use the `.local.json` path if you want the `plugin-settings` skill convention; costs nothing but changes the mental model |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `process.cwd()` to find project dir | The server's cwd is always `CLAUDE_PLUGIN_ROOT` (set by `--cwd` in `.mcp.json`), not the project | `process.env.DISCORD_PROJECT_DIR` |
| Merging local + global access.json | Merging creates ambiguous precedence and split-brain state — if a channel is in global but removed from local, which wins? | Full replacement: local file completely overrides global |
| Hot-reloading the active file selection at runtime | The file selection (local vs global) is a boot-time decision based on whether the local file exists at startup | Decide once at boot; restart required if user creates/removes local file |
| Writing local access.json from the MCP server process | The server knows `DISCORD_PROJECT_DIR` but should not write project files autonomously | The `/discord:access` skill (prompt-driven, user-invoked) writes the file; server only reads it |
| Committing `.claude/channels/discord/access.json` to project git | Contains Discord user IDs and channel IDs — sensitive, project-local | Add to `.gitignore` |

## Skill Layer Changes

The `/discord:access` SKILL.md must be updated in parallel with server.ts. The skill needs to:

1. Detect whether `DISCORD_PROJECT_DIR` is set (it is available in the skill's environment if Claude Code sets it in the session env — LOW confidence; needs testing)
2. Alternatively: the skill always operates on `./.claude/channels/discord/access.json` for "local" scope and `~/.claude/channels/discord/access.json` for "global" scope, chosen by user when running `group add`

**Safer approach for the skill:** The skill is prompt-driven and runs in the same Claude Code session that has a project directory. The skill can use `Bash(pwd)` or read the session's cwd to determine the project root — it does not need an env var; it can construct the local path from the working directory.

## Plugin Cache Resilience

Files in `~/.claude/plugins/cache/` are overwritten on plugin updates. The `.mcp.json` modification must be applied to the **local override** of the plugin, not the cache copy.

Claude Code plugin system supports local overrides in `~/.claude/plugins/local/` (or equivalent). If no such override path exists, changes to `~/.claude/plugins/cache/.../.mcp.json` will be wiped on updates. **This must be resolved during implementation** — either upstream the change or find the override mechanism.

Confidence on local override path: LOW — needs verification against current Claude Code plugin architecture.

## Version Compatibility

| Requirement | Version | Notes |
|-------------|---------|-------|
| `CLAUDE_PROJECT_DIR` env var | Claude Code v1.0.58+ | Added in changelog entry "Hooks: Added CLAUDE_PROJECT_DIR env var for hook commands"; behavior in MCP env block confirmed by stdlib example |
| `${CLAUDE_PROJECT_DIR}` in `.mcp.json` `env` | Same as above | The `env` block substitution follows the same expansion rules as `args` |
| `${CLAUDE_PLUGIN_DATA}` (alternative) | Claude Code v2.1.78+ | For data that should survive plugin updates — not needed here since state lives in the project dir |

## Sources

- `/Users/haocheng_mini/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/mcp-integration/examples/stdio-server.json` — Confirms `${CLAUDE_PROJECT_DIR}` in args; HIGH confidence (official plugin-dev skill example)
- `/Users/haocheng_mini/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/mcp-integration/SKILL.md` — Documents env var substitution in all `.mcp.json` fields; HIGH confidence (official docs)
- `/Users/haocheng_mini/.claude/cache/changelog.md` line 1989 — v1.0.58 changelog confirms `CLAUDE_PROJECT_DIR` env var for hook commands; HIGH confidence (first-party changelog)
- `/Users/haocheng_mini/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/hook-development/examples/load-context.sh` — Shows `$CLAUDE_PROJECT_DIR` used in hook scripts; HIGH confidence
- `/Users/haocheng_mini/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/plugin-settings/SKILL.md` — Documents `.claude/plugin-name.local.md` pattern; HIGH confidence
- `/Users/haocheng_mini/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/server.ts` — Existing server; confirms `STATE_DIR` and `ACCESS_FILE` pattern; direct inspection

---
*Stack research for: MCP server plugin project-scoped configuration*
*Researched: 2026-03-23*
