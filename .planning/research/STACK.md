# Technology Stack

**Project:** Claude Code Channels -- Project-Local Discord Access
**Researched:** 2026-03-25
**Milestone context:** Milestone 2 -- modular install/uninstall, env var delivery fix, new features

## Context

This is a patch-based extension of an existing Claude Code plugin (Discord, now at v0.0.4). The stack is fixed: Bun + discord.js + `@modelcontextprotocol/sdk`. This research focuses on three operational questions:

1. How to reliably pass `DISCORD_PROJECT_DIR` to the MCP server process
2. How to build modular, idempotent bash install/uninstall scripts for plugin patching
3. What Claude Code plugin infrastructure is available and what to avoid

## Env Var Delivery: The Core Problem

### What's Broken

The current `.mcp.json` uses an `sh -c` wrapper to capture `$PWD` before `--cwd` changes it:

```json
{
  "command": "sh",
  "args": ["-c", "DISCORD_PROJECT_DIR=$PWD exec bun run --cwd '${CLAUDE_PLUGIN_ROOT}' --shell=bun --silent start"]
}
```

**Problem:** `$PWD` at the time `sh -c` runs is not guaranteed to be the project directory. Claude Code sets the MCP server's working directory to `CLAUDE_PLUGIN_ROOT` before spawning the process. The `$PWD` the shell sees may already be the plugin root, not the project directory. This is why `DISCORD_PROJECT_DIR` is empty/wrong at runtime.

### Recommended Fix: `env` Block with `${CLAUDE_PROJECT_DIR}`

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

**Why this works:**
- `${CLAUDE_PROJECT_DIR}` is expanded by Claude Code *before* spawning the subprocess (same expansion engine as `args`)
- The official MCP integration docs state: "All MCP configurations support environment variable substitution"
- `${CLAUDE_PROJECT_DIR}` in `args` is confirmed working by the official `stdio-server.json` example
- The `env` block uses the same `${VAR}` expansion mechanism as `args`

**Confidence:** MEDIUM -- `${CLAUDE_PROJECT_DIR}` in `args` is HIGH confidence (official example). In `env` block specifically, there is no official example showing `CLAUDE_PROJECT_DIR` in `env`, only in `args`. The docs claim uniform expansion across all fields. Needs empirical verification during implementation.

**Fallback if `env` block expansion fails:** Use a hook-based approach. A `SessionStart` hook can write `DISCORD_PROJECT_DIR` to the plugin's env file (`$CLAUDE_ENV_FILE`), which persists env vars into the MCP server's environment. This is the documented pattern for hook-to-server env propagation.

### What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `sh -c` wrapper with `$PWD` | `$PWD` is unreliable -- Claude Code may set cwd before shell launches | `env` block with `${CLAUDE_PROJECT_DIR}` |
| `process.cwd()` in server.ts | Server cwd is always `CLAUDE_PLUGIN_ROOT` (set by `--cwd`) | `process.env.DISCORD_PROJECT_DIR` |
| Reading `CLAUDE_PROJECT_DIR` directly (no rename) | Works but risks namespace collision if Claude Code changes the var | Rename to `DISCORD_PROJECT_DIR` at the boundary |
| Merging local + global access.json | Ambiguous precedence, split-brain state | Full replacement: local overrides global entirely |

## Recommended Stack

### Core Technologies (Unchanged)

| Technology | Version | Purpose | Confidence |
|------------|---------|---------|------------|
| Bun | 1.3.11 (installed) | Runtime + package manager | HIGH -- already in use |
| `@modelcontextprotocol/sdk` | existing | MCP stdio server | HIGH -- standard SDK |
| discord.js | existing | Discord Gateway client | HIGH -- already in use |
| Node.js `fs` (sync) | built-in | Read/write access.json at startup | HIGH -- already used throughout server.ts |

### Plugin Patching Stack

| Technology | Purpose | Why |
|------------|---------|-----|
| Bash (POSIX-compatible) | Install/uninstall scripts | Already established; no justification for Python/Node scripts |
| `bun -e` inline scripts | TypeScript/JSON manipulation in patches | Already used in apply-discord-patch.sh; handles JSON and regex transforms that sed cannot do safely |
| `grep -qF` marker detection | Idempotency checks | Simple, portable, already established pattern |
| Unified diff patches | NOT recommended for this project | Plugin versions change frequently (now 0.0.4, was 0.0.1); line offsets shift and patches fail silently |

### Claude Code Plugin Infrastructure

| Variable/Feature | Available Since | Purpose | Confidence |
|------------------|----------------|---------|------------|
| `${CLAUDE_PLUGIN_ROOT}` | Early versions | Plugin directory path in `.mcp.json` | HIGH -- used everywhere |
| `${CLAUDE_PROJECT_DIR}` | v1.0.58+ | Project directory in `.mcp.json` args | HIGH -- official example exists |
| `${CLAUDE_PROJECT_DIR}` in `env` block | v1.0.58+ (assumed) | Project directory as env var | MEDIUM -- docs say all fields support expansion, but no official `env` example |
| `${CLAUDE_PLUGIN_DATA}` | v2.1.78+ | Persistent plugin data dir (survives updates) | HIGH -- changelog confirmed |
| `$CLAUDE_ENV_FILE` | Early versions | SessionStart hooks can write env vars here | HIGH -- documented in hook-development skill |
| SessionStart hooks | Early versions | Run scripts when Claude Code starts | HIGH -- already used by this project |

## Modular Bash Install/Uninstall Architecture

### Design Principles

**Use a component-based architecture.** Each feature is a self-contained patch module with `apply` and `revert` functions. The install script orchestrates them.

```
scripts/
  install.sh          # Orchestrator: discovers plugin, runs components in order
  uninstall.sh        # Orchestrator: reverts components in reverse order
  components/
    00-mcp-json.sh    # Patch .mcp.json (env var delivery)
    10-local-scoping.sh  # Patch server.ts (resolveAccessFile)
    20-skill-access.sh   # Patch SKILL.md (scope-aware access skill)
    30-greeting.sh       # Patch server.ts (session greeting)
    40-strip-media.sh    # Patch server.ts (remove rich media)
```

### Bash Best Practices for This Project

| Practice | Why | How |
|----------|-----|-----|
| `set -euo pipefail` | Fail fast on any error | Already used in current scripts |
| Marker-based idempotency | Safe to re-run; SessionStart hook calls install on every session | `grep -qF "MARKER" file && return 0` |
| Component exit codes | Orchestrator needs per-component status | 0=applied, 1=error, 2=already-applied, 3=skipped (anchor missing) |
| `sort -V` for version discovery | Find latest plugin version numerically | Already used; handles 0.0.4 > 0.0.10 correctly |
| stderr for status messages | stdout reserved for data/piping | Already established with `>&2` |
| No `cd` in components | Components receive paths as arguments | Prevents cwd confusion when sourcing |

### Install Script Pattern

```bash
#!/usr/bin/env bash
set -euo pipefail

# Discover plugin
PLUGIN_DIR=$(find_latest_plugin_version)

# Source and run components in order
for component in "$SCRIPT_DIR/components/"*.sh; do
  source "$component"
  component_name=$(basename "$component" .sh)
  apply "$PLUGIN_DIR" "$REPO_DIR"
  # Track per-component status
done
```

### Uninstall Script Pattern

The uninstall script runs components in reverse order. Each component's `revert` function:
1. Checks if its marker is present (skip if not)
2. Removes injected code blocks between markers
3. Restores original values where possible

For `.mcp.json`, the simplest revert is to restore from the plugin's original `.mcp.json.orig` backup (created during install).

### Key Bash Patterns

**Marker-delimited code blocks** for clean injection and removal:

```bash
# In apply:
START_MARKER="// --- discord-channels: local-scoping start ---"
END_MARKER="// --- discord-channels: local-scoping end ---"

# In revert: remove everything between markers (inclusive)
sed -i '' "/$START_MARKER/,/$END_MARKER/d" "$file"
```

**Backup before first patch:**

```bash
[[ -f "$file.orig" ]] || cp "$file" "$file.orig"
```

**`bun -e` for JSON manipulation** (not `jq` -- avoiding new dependencies):

```bash
bun -e "
  const fs = require('fs');
  const mcp = JSON.parse(fs.readFileSync('$MCP_JSON', 'utf8'));
  // ... transform ...
  fs.writeFileSync('$MCP_JSON', JSON.stringify(mcp, null, 2) + '\n');
"
```

## Project-Scoped Config

### Path Convention

**Local:** `$PROJECT_DIR/.claude/channels/discord/access.json`
**Global:** `~/.claude/channels/discord/access.json`

Why this path (unchanged from prior research):
- Mirrors global structure
- The `/discord:access` skill already knows this shape
- Keeps discord state under `channels/discord/` regardless of scope

### Resolution Logic

```typescript
const PROJECT_DIR = process.env.DISCORD_PROJECT_DIR || undefined

function resolveAccessFile() {
  if (PROJECT_DIR) {
    const candidate = join(PROJECT_DIR, '.claude', 'channels', 'discord', 'access.json')
    try {
      statSync(candidate)
      return { path: candidate, scope: 'local' }
    } catch (e) {
      if (e.code !== 'ENOENT') {
        process.stderr.write('discord channel: error checking local access.json: ' + e + '\n')
      }
    }
  }
  return { path: ACCESS_FILE, scope: 'global' }
}
```

This is already implemented in the current patch. The issue is that `DISCORD_PROJECT_DIR` never arrives -- fixing the `.mcp.json` patch is the priority.

## Plugin Cache Resilience

Files in `~/.claude/plugins/cache/` are wiped on plugin updates. The strategy:

1. **SessionStart hook** re-applies all patches via `install.sh` on every session start
2. **Idempotent components** skip work if markers are already present (fast no-op path)
3. **Version-agnostic patching** -- use `bun -e` AST-like transforms with anchor strings, not line-number-dependent unified diffs
4. **Backup originals** -- `file.orig` created on first patch for clean revert

`${CLAUDE_PLUGIN_DATA}` (v2.1.78+) provides a persistent directory that survives plugin updates. Not needed for this project since state lives in the project dir, but useful if we ever need plugin-level persistent config.

## Version Compatibility

| Requirement | Min Version | Notes | Confidence |
|-------------|-------------|-------|------------|
| `CLAUDE_PROJECT_DIR` in hooks | v1.0.58+ | Changelog confirmed | HIGH |
| `${CLAUDE_PROJECT_DIR}` in `.mcp.json` args | v1.0.58+ | Official example confirms | HIGH |
| `${CLAUDE_PROJECT_DIR}` in `.mcp.json` env | v1.0.58+ (assumed) | Docs say "all fields"; no specific example | MEDIUM |
| `${CLAUDE_PLUGIN_DATA}` | v2.1.78+ | Changelog confirmed | HIGH |
| Discord plugin version | 0.0.4 | Currently installed; was 0.0.1 at prior research | HIGH (direct inspection) |

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Env var delivery | `env` block in `.mcp.json` | `sh -c` wrapper capturing `$PWD` | `$PWD` is unreliable; cwd may already be plugin root |
| Env var delivery (fallback) | SessionStart hook writing to `$CLAUDE_ENV_FILE` | -- | Use if `env` block expansion doesn't work for `CLAUDE_PROJECT_DIR` |
| JSON manipulation | `bun -e` inline | `jq` | `jq` is a new dependency; Bun is already available |
| Patch format | Marker-based `bun -e` transforms | Unified diff (`patch -p1`) | Diffs break across plugin versions; anchors are more resilient |
| Script language | Bash | Python/Node | Bash is already established; scripts are glue code, not application logic |
| Install modularity | Numbered component files | Single monolithic script | Components can be added/removed independently as features grow |

## Sources

- `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.4/.mcp.json` -- Current deployed config showing `sh -c` wrapper approach; direct inspection
- `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.4/server.ts` -- Current server with local-scoping patch already applied; direct inspection
- `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/mcp-integration/SKILL.md` -- Documents env var expansion in "all MCP configurations"; HIGH confidence
- `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/mcp-integration/examples/stdio-server.json` -- Shows `${CLAUDE_PROJECT_DIR}` in args; HIGH confidence
- `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/hook-development/SKILL.md` -- Documents `$CLAUDE_PROJECT_DIR` for hooks, `$CLAUDE_ENV_FILE` for env propagation; HIGH confidence
- `~/.claude/cache/changelog.md` -- v1.0.58: `CLAUDE_PROJECT_DIR` for hooks; v2.1.78: `CLAUDE_PLUGIN_DATA`; HIGH confidence
- `scripts/apply-discord-patch.sh` -- Current patch script establishing patterns (markers, `bun -e`, `sort -V`); direct inspection

---
*Stack research for: Claude Code Channels Milestone 2*
*Researched: 2026-03-25*
