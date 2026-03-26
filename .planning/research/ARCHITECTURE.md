# Architecture Patterns

**Domain:** Claude Code plugin patching -- Discord channel project-local scoping
**Researched:** 2026-03-25 (updated from 2026-03-23)
**Confidence:** HIGH (direct inspection of plugin source, official MCP docs, official examples)

## How Claude Code Launches MCP Servers

Understanding the launch chain is the single most important piece of context for this project, because the core bug -- `DISCORD_PROJECT_DIR` not reaching the server -- stems from a misunderstanding of how this chain works.

### The Launch Chain (stdio type)

```
1. Claude Code reads .mcp.json from plugin cache
   ↓
2. Template expansion: ${CLAUDE_PLUGIN_ROOT}, ${CLAUDE_PROJECT_DIR}, ${USER_ENV_VARS}
   (string substitution on command, args, and env values BEFORE spawning)
   ↓
3. Spawns child process:
   - executable: expanded `command`
   - arguments: expanded `args`
   - environment: inherited env + expanded `env` block
   - cwd: NOT DOCUMENTED, NOT RELIABLE -- do not depend on it
   ↓
4. Child process communicates via stdin/stdout (JSON-RPC)
   ↓
5. Process lives for the entire Claude Code session
   Terminated when Claude Code exits
```

### Key Facts

| Fact | Confidence | Source |
|------|------------|--------|
| `${VAR}` in `.mcp.json` is expanded by Claude Code before spawning | HIGH | MCP integration SKILL.md, stdio-server.json example |
| `${CLAUDE_PLUGIN_ROOT}` resolves to plugin cache dir | HIGH | Used in original `.mcp.json`, documented |
| `${CLAUDE_PROJECT_DIR}` is available for expansion | HIGH | Official `stdio-server.json` uses it in `args` |
| `env` block values become `process.env` in child | HIGH | MCP docs pattern: `"env": { "API_KEY": "${MY_API_KEY}" }` |
| Child process cwd is not the project directory | HIGH | Original `.mcp.json` uses `--cwd ${CLAUDE_PLUGIN_ROOT}` explicitly |
| `CLAUDE_PROJECT_DIR` was added in v1.0.58 | HIGH | Changelog line 2111 |

### Root Cause: Why the Current `sh -c` Approach Fails

**Original `.mcp.json` (from marketplace):**
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

**Current patched `.mcp.json` (broken):**
```json
{
  "mcpServers": {
    "discord": {
      "command": "sh",
      "args": ["-c", "DISCORD_PROJECT_DIR=$PWD exec bun run --cwd '${CLAUDE_PLUGIN_ROOT}' --shell=bun --silent start"]
    }
  }
}
```

**The bug:** `$PWD` inside the `sh -c` command reflects the child process's cwd at spawn time. Claude Code does NOT spawn MCP server processes with cwd set to the user's project directory. The child process inherits whatever cwd Claude Code assigns -- likely the plugin root or an unspecified default. So `DISCORD_PROJECT_DIR` gets set to the wrong value (plugin cache path or home dir), and `resolveAccessFile()` looks for a local access.json in the wrong location, finds nothing, and falls back to global.

**Evidence:** PROJECT.md states "DISCORD_PROJECT_DIR is not reaching the MCP server, so sessions fall back to global config." The server logs "using global config" when it should log "using local config."

### The Correct Approach: `env` Block with Template Expansion

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
1. Claude Code expands `${CLAUDE_PROJECT_DIR}` to the actual project path at template time (before spawning)
2. The expanded value is injected as `DISCORD_PROJECT_DIR` in the child process environment
3. `server.ts` reads `process.env.DISCORD_PROJECT_DIR` and gets the correct path
4. No shell wrapper needed -- the original `command`/`args` structure is preserved
5. `--cwd` still correctly sets bun's working directory to the plugin root for module resolution

**Why use `DISCORD_PROJECT_DIR` not `CLAUDE_PROJECT_DIR` directly:** Avoids name-collision risk if Claude Code changes its variable namespace. The env block creates a deliberate mapping. The server code is explicit about what it needs.

## Recommended Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────────────┐
│  Project Repository (claude_code_channels)              │
│                                                         │
│  scripts/                                               │
│  ├── install.sh          ← entry point, orchestrates    │
│  ├── uninstall.sh        ← reverses all patches         │
│  └── patches/            ← modular patch functions      │
│      ├── common.sh       ← shared: find plugin, markers │
│      ├── server-ts.sh    ← server.ts code injection     │
│      ├── mcp-json.sh     ← .mcp.json env block          │
│      └── skill-md.sh     ← SKILL.md replacement         │
│                                                         │
│  patches/                                               │
│  └── SKILL.md            ← full replacement file        │
│                                                         │
│  .claude/                                               │
│  └── hooks.json          ← SessionStart → install.sh    │
└─────────────────────────────────────────────────────────┘
         │ patches at runtime ↓
┌─────────────────────────────────────────────────────────┐
│  Plugin Cache (~/.claude/plugins/cache/.../discord/X.Y) │
│                                                         │
│  .mcp.json     ← patched: env block added               │
│  server.ts     ← patched: resolveAccessFile() injected  │
│  skills/       ← patched: scope-aware SKILL.md          │
│  package.json  ← untouched                              │
└─────────────────────────────────────────────────────────┘
         │ launched by Claude Code ↓
┌─────────────────────────────────────────────────────────┐
│  Running MCP Server Process                             │
│                                                         │
│  process.env.DISCORD_PROJECT_DIR = "/path/to/project"   │
│  cwd = plugin cache dir (via --cwd)                     │
│                                                         │
│  Boot: resolveAccessFile()                              │
│    → Check $PROJECT_DIR/.claude/channels/discord/       │
│      access.json                                        │
│    → Fall back to ~/.claude/channels/discord/access.json│
│                                                         │
│  Runtime: Discord Gateway → filter by access config     │
└─────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| `install.sh` | Orchestrator: find plugin dir, source patches, run them, report status | All patch scripts via `source` |
| `uninstall.sh` | Reverse: restore original files or strip markers | Plugin cache files directly |
| `patches/common.sh` | Find latest plugin version, define marker constants, provide `check_marker` helper | Sourced by install.sh and uninstall.sh |
| `patches/server-ts.sh` | Inject `resolveAccessFile()` into server.ts via `bun -e` anchor-based insertion | Plugin cache `server.ts` |
| `patches/mcp-json.sh` | Add `env` block with `DISCORD_PROJECT_DIR` mapping | Plugin cache `.mcp.json` |
| `patches/skill-md.sh` | Copy scope-aware SKILL.md to plugin skills dir | Plugin cache `skills/access/SKILL.md` |
| `hooks.json` | Trigger `install.sh` on SessionStart (re-apply after cache wipe) | Claude Code hook system |
| `resolveAccessFile()` (injected) | Runtime: decide local vs global access.json | server.ts internals |

### Data Flow

```
Session Start
  → Claude Code fires SessionStart hook
  → hooks.json triggers install.sh
  → install.sh sources patches/common.sh (finds plugin dir)
  → install.sh sources + runs each patch script
  → Each patch: check marker → skip if present, apply if not

MCP Server Launch (after patches applied)
  → Claude Code reads patched .mcp.json
  → Expands ${CLAUDE_PROJECT_DIR} → "/Users/me/myproject" in env block
  → Expands ${CLAUDE_PLUGIN_ROOT} → "~/.claude/plugins/cache/.../0.0.4" in args
  → Spawns: bun run --cwd <plugin_root> start
  → bun reads package.json → runs: bun install --no-summary && bun server.ts
  → Server boots, reads process.env.DISCORD_PROJECT_DIR
  → resolveAccessFile() checks /Users/me/myproject/.claude/channels/discord/access.json
  → If exists → local scope; else → global fallback
  → Server connects to Discord, filters messages by active access config
```

## Patterns to Follow

### Pattern 1: Idempotent Marker-Gated Patches

**What:** Every patch script checks a unique marker before applying. Running N times = same result as running once.

**When:** Always -- the SessionStart hook fires on every session start.

**Implementation:**
```bash
# In patches/common.sh
check_marker() {
  local marker="$1" file="$2"
  grep -qF "$marker" "$file" 2>/dev/null
}

# In patches/server-ts.sh
apply_server_patch() {
  local marker="// discord-local-scoping patch applied"
  if check_marker "$marker" "$SERVER_TS"; then
    echo "server.ts: already patched" >&2
    return 0
  fi
  # ... apply patch ...
}
```

### Pattern 2: Anchor-Based Code Injection via `bun -e`

**What:** Use `bun -e` with inline JS to find a known anchor line in server.ts and inject code after it. More resilient than unified diffs which break on any upstream change.

**When:** Patching server.ts.

**Why `bun -e` not `sed`:** The injected code is multi-line TypeScript with template literals, escaping, and regex replacements. JS-based manipulation is more reliable than shell string manipulation for this complexity.

**Anchor choice:** `const ENV_FILE = join(STATE_DIR, '.env')` -- this line is part of the core constant block that defines `STATE_DIR`, `ACCESS_FILE`, `APPROVED_DIR`, and `ENV_FILE`. It is stable across minor plugin versions because the state directory structure is a fundamental design choice.

### Pattern 3: Structural JSON Manipulation for .mcp.json

**What:** Use `bun -e` with `JSON.parse`/`JSON.stringify` to modify `.mcp.json` structurally rather than text replacement.

**Corrected implementation:**
```bash
bun -e "
  const fs = require('fs');
  const mcp = JSON.parse(fs.readFileSync('$MCP_JSON', 'utf8'));
  const discord = mcp.mcpServers.discord;
  // Restore original command/args, add env block
  discord.command = 'bun';
  discord.args = ['run', '--cwd', '\${CLAUDE_PLUGIN_ROOT}', '--shell=bun', '--silent', 'start'];
  discord.env = { DISCORD_PROJECT_DIR: '\${CLAUDE_PROJECT_DIR}' };
  fs.writeFileSync('$MCP_JSON', JSON.stringify(mcp, null, 2) + '\n');
"
```

**Why restore original command/args:** The `sh -c` wrapper was the wrong approach. Restoring `command: "bun"` with `args` keeps the standard `.mcp.json` contract that Claude Code expects.

### Pattern 4: Modular Patch Scripts

**What:** Each patch is a separate file in `scripts/patches/` that defines a function. `install.sh` sources them and calls each.

**When:** Adding new features (greeting, strip rich media, channel ID display). Each gets its own patch script.

**Why:** Avoids a monolithic install script. Each feature can be developed, tested, and debugged independently. Uninstall can target individual patches. New features don't touch existing patch code.

```bash
# install.sh structure
source "$SCRIPT_DIR/patches/common.sh"

find_plugin_dir || exit 0

source "$SCRIPT_DIR/patches/mcp-json.sh"
source "$SCRIPT_DIR/patches/server-ts.sh"
source "$SCRIPT_DIR/patches/skill-md.sh"

apply_mcp_patch
apply_server_patch
apply_skill_patch
```

## Anti-Patterns to Avoid

### Anti-Pattern 1: Shell Wrapper for Env Injection (`sh -c "VAR=$PWD exec ..."`)

**What:** Using a shell wrapper to capture `$PWD` before `--cwd` changes it.

**Why bad:** The child process cwd when Claude Code spawns MCP servers is not the user's project directory. `$PWD` captures the wrong value. Also makes the command harder to debug and breaks the standard `.mcp.json` contract.

**Instead:** Use the `env` block with `${CLAUDE_PROJECT_DIR}` template expansion.

### Anti-Pattern 2: Unified Diff Patches (`git apply`, `patch`)

**What:** Using `.patch` files to modify plugin source.

**Why bad:** Plugin updates change line numbers, whitespace, and surrounding context. Patches fail on any upstream change. The existing `discord-local-scoping.patch` file is a reference artifact, not a usable patch mechanism.

**Instead:** Anchor-based injection with `bun -e`.

### Anti-Pattern 3: Monolithic Install Script

**What:** One script that handles all patches, all markers, all features in sequence.

**Why bad:** Hard to test individual patches, hard to add new features, hard to debug which patch failed, hard to uninstall selectively.

**Instead:** Modular scripts in `scripts/patches/`, orchestrated by `install.sh`.

### Anti-Pattern 4: Reading `process.cwd()` for Project Directory

**What:** Using `process.cwd()` in server.ts to determine the project directory.

**Why bad:** The server's cwd is explicitly set to `CLAUDE_PLUGIN_ROOT` by `--cwd` in `.mcp.json`. It will always be the plugin cache directory.

**Instead:** Read `process.env.DISCORD_PROJECT_DIR`.

### Anti-Pattern 5: Merging Local + Global access.json

**What:** Union-merging groups from both files.

**Why bad:** Creates ambiguous precedence. If global has DM allowlists and a project creates local file scoped to guild channels only, DMs still arrive -- surprising. Explicitly rejected in PROJECT.md.

**Instead:** Full replacement -- local file is the entire config for that session.

## Build Order (Feature Dependencies)

```
Phase 1: Fix Core Infrastructure (CRITICAL PATH)
├── 1a. Fix .mcp.json patch → env block approach     ← BLOCKS everything
│       (replaces sh -c wrapper with env block)
├── 1b. Modularize install/uninstall scripts          ← enables future features
│       (split monolith into patches/common.sh, patches/*.sh)
├── 1c. Verify DISCORD_PROJECT_DIR reaches server     ← validates 1a works
│       (check server stderr log: "using local config")
└── 1d. Wire SessionStart hook                        ← ensures patches survive cache wipe

Phase 2: Features (can parallelize after Phase 1)
├── 2a. Session greeting (needs working project dir + install framework)
├── 2b. Channel ID display (needs working server)
└── 2c. Strip rich media (independent patch, uses install framework)

Phase 3: Polish
└── 3a. Robustness: version compatibility checks, error reporting
```

**Critical path:** `.mcp.json` env block fix (1a) unblocks everything. Without `DISCORD_PROJECT_DIR` reaching the server correctly, local scoping, greeting, and all project-aware features fail silently (they fall back to global with no error).

**Modularization (1b)** is a framework investment that makes Phase 2 features additive -- each is a new file in `scripts/patches/`, not a modification to existing code.

## File Layout (Target State)

```
claude_code_channels/
├── scripts/
│   ├── install.sh                ← orchestrator
│   ├── uninstall.sh              ← reverse orchestrator
│   └── patches/
│       ├── common.sh             ← find_plugin_dir(), check_marker(), vars
│       ├── mcp-json.sh           ← apply_mcp_patch(): env block injection
│       ├── server-ts.sh          ← apply_server_patch(): resolveAccessFile()
│       ├── skill-md.sh           ← apply_skill_patch(): SKILL.md copy
│       ├── greeting.sh           ← (Phase 2) apply_greeting_patch()
│       ├── strip-rich-media.sh   ← (Phase 2) apply_strip_rich_media_patch()
│       └── channel-id-display.sh ← (Phase 2) apply_channel_id_patch()
├── patches/
│   └── SKILL.md                  ← full replacement skill file
├── .claude/
│   └── hooks.json                ← SessionStart → scripts/install.sh
└── ...
```

## Scalability Considerations

| Concern | At 3 patches (now) | At 6 patches | At 10+ patches |
|---------|---------------------|--------------|----------------|
| Install time | <1s | <2s | <3s (still fine) |
| Anchor conflicts | None | Watch for overlapping insertion points | Need anchor registry |
| Uninstall complexity | Per-marker grep-and-remove | Same | Consider full file restore from backup |
| Plugin version compat | Single anchor check | Multiple anchors to verify | Need version compatibility matrix |
| Code review surface | Small, focused scripts | Manageable | Still manageable (each file is independent) |

## Integration Points

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Claude Code -> .mcp.json | Template expansion at spawn time | `${CLAUDE_PROJECT_DIR}` and `${CLAUDE_PLUGIN_ROOT}` |
| .mcp.json -> server process | `env` block -> `process.env` | New: `DISCORD_PROJECT_DIR` mapping |
| server.ts -> access.json | Filesystem read/write via `resolveAccessFile()` | Resolved path varies by scope |
| SKILL.md -> access.json | Claude's Read/Write file tools | Must implement same resolution logic as server |
| SessionStart hook -> install.sh | Claude Code hook system | Re-applies patches after plugin cache updates |
| install.sh -> plugin cache | Filesystem writes via `bun -e` | Idempotent, marker-gated |

## Sources

- `/Users/haocheng_mini/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/mcp-integration/SKILL.md` -- MCP integration docs: env block expansion, process lifecycle, stdio type; HIGH confidence (official)
- `/Users/haocheng_mini/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/mcp-integration/examples/stdio-server.json` -- Confirms `${CLAUDE_PROJECT_DIR}` available in MCP config; HIGH confidence (official example)
- `/Users/haocheng_mini/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/mcp-integration/references/server-types.md` -- stdio process lifecycle details; HIGH confidence
- `/Users/haocheng_mini/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/discord/.mcp.json` -- Original unpatched config (command: "bun", no env block); HIGH confidence (direct inspection)
- `/Users/haocheng_mini/.claude/plugins/cache/claude-plugins-official/discord/0.0.4/.mcp.json` -- Current patched config with broken `sh -c` wrapper; HIGH confidence (direct inspection)
- `/Users/haocheng_mini/.claude/plugins/cache/claude-plugins-official/discord/0.0.4/server.ts` -- Current patched server with `resolveAccessFile()`; HIGH confidence (direct inspection)
- `/Users/haocheng_mini/.claude/plugins/cache/claude-plugins-official/discord/0.0.4/package.json` -- Start script: `bun install --no-summary && bun server.ts`; HIGH confidence
- `/Users/haocheng_mini/.claude/cache/changelog.md` line 2111 -- `CLAUDE_PROJECT_DIR` added v1.0.58 for hooks; HIGH confidence (first-party changelog)
- `/Users/haocheng_mini/Documents/projects/claude_code_channels/.planning/PROJECT.md` -- Bug confirmation: "DISCORD_PROJECT_DIR is not reaching the MCP server"; HIGH confidence (project docs)
