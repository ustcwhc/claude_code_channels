# Architecture Research

**Domain:** MCP server plugin — project-local access control upgrade
**Researched:** 2026-03-23
**Confidence:** HIGH (based on direct source code inspection)

## Standard Architecture

### System Overview (Current State)

```
Claude Code session (cwd: /path/to/project)
    │
    │  spawns via .mcp.json
    ▼
MCP Server process (cwd: CLAUDE_PLUGIN_ROOT)
    │   bun run --cwd ${CLAUDE_PLUGIN_ROOT} start
    │
    ├── STATE_DIR = ~/.claude/channels/discord/
    │       access.json          ← single global access file
    │       approved/<senderId>  ← approval signals for pairing
    │       inbox/               ← downloaded attachments
    │       .env                 ← bot token
    │
    └── Discord gateway (discord.js Client)
            ↓ messageCreate events
        gate(msg) → loadAccess() → readAccessFile(ACCESS_FILE)
```

```
/discord:access skill (Claude's file tools)
    │
    └── reads/writes ~/.claude/channels/discord/access.json
        hardcoded path — no project-awareness
```

### System Overview (Target State)

```
Claude Code session (cwd: /path/to/project)
    │
    │  spawns with CLAUDE_PROJECT_DIR=/path/to/project injected
    ▼
MCP Server process (cwd: CLAUDE_PLUGIN_ROOT)
    │
    ├── PROJECT_DIR = process.env.CLAUDE_PROJECT_DIR  [NEW]
    │
    ├── resolveAccessFile(PROJECT_DIR)                [NEW]
    │       checks: PROJECT_DIR/.claude/channels/discord/access.json
    │       fallback: ~/.claude/channels/discord/access.json
    │       returns: { path, scope: 'local' | 'global' }
    │
    ├── STATE_DIR = ~/.claude/channels/discord/       [UNCHANGED]
    │       approved/, inbox/, .env still global
    │
    └── Discord gateway
            ↓ messageCreate events
        gate(msg) → loadAccess() → resolveAccessFile()  [CHANGED]
```

```
/discord:access skill (Claude's file tools)
    │
    ├── reads CLAUDE_PROJECT_DIR from environment      [NEW]
    ├── calls resolveAccessFile() logic in skill       [NEW]
    │       checks local path first → falls back global
    │
    ├── `group add` prompts: "local or global scope?"  [NEW]
    │       local  → writes PROJECT_DIR/.claude/channels/discord/access.json
    │       global → writes ~/.claude/channels/discord/access.json
    │
    └── no-args status shows: "Active: local @ /path/to/project" [NEW]
```

### Component Responsibilities

| Component | Responsibility | Change Needed |
|-----------|----------------|---------------|
| `.mcp.json` | Launches server with `bun run start` | Add `env: { CLAUDE_PROJECT_DIR: "${CLAUDE_PROJECT_DIR}" }` |
| `server.ts` top-level constants | Derive `STATE_DIR`, `ACCESS_FILE` from env | Add `PROJECT_DIR`, `resolveAccessFile()`, change `ACCESS_FILE` reference |
| `readAccessFile()` | Read and parse access.json | No change — still takes a path implicitly; wired through `resolveAccessFile()` |
| `loadAccess()` | Return snapshot (static) or live read | No change — already calls `readAccessFile()` indirectly |
| `saveAccess()` | Write access.json atomically | Must write to the resolved path, not hardcoded `ACCESS_FILE` |
| `gate()` | Inbound message gating per access rules | No change — already calls `loadAccess()` |
| `fetchAllowedChannel()` | Outbound channel authorization | No change — already calls `loadAccess()` |
| `checkApprovals()` | Polls `approved/` dir, sends DM confirms | No change — approval flow is always global (DMs are user-level) |
| `SKILL.md` (`/discord:access`) | Edits access.json via Claude file tools | Major changes — scope discovery, local write path, status display |

## Recommended Project Structure

```
~/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/
├── server.ts                  # [MODIFIED] — resolveAccessFile(), env var
├── .mcp.json                  # [MODIFIED] — CLAUDE_PROJECT_DIR env injection
├── skills/
│   └── access/
│       └── SKILL.md           # [MODIFIED] — scope prompting, local path logic
└── ...

# Per-project local config (new, written by /discord:access):
/path/to/project/
└── .claude/
    └── channels/
        └── discord/
            └── access.json    # local access file (project-scoped)

# Global config (existing, unchanged location):
~/.claude/channels/discord/
├── access.json                # global fallback
├── approved/                  # always global — DM flow is user-level
├── inbox/                     # always global
└── .env                       # bot token
```

### Structure Rationale

- **`approved/` stays global:** The pairing approval handshake is DM-based (user-level), not project-level. Writing approval signals to the global dir keeps the server's polling logic unchanged.
- **`inbox/` stays global:** Downloaded attachments are session-level artifacts; project-scoping them adds complexity with no benefit.
- **`.env` stays global:** Single bot token shared across all sessions — no need to scope.
- **Local access.json in `.claude/channels/discord/`:** Mirrors the global path structure under the project root, making it discoverable and consistent.

## Architectural Patterns

### Pattern 1: Env Var Project Directory Injection

**What:** The MCP launch command in `.mcp.json` passes `CLAUDE_PROJECT_DIR` from Claude Code's environment into the server process.

**When to use:** When the server's `cwd` is not the project directory (this case: server `cwd` is `CLAUDE_PLUGIN_ROOT`).

**Trade-offs:** Simple and explicit. Requires `.mcp.json` to support `env` block — Claude Code's MCP config format does support this. Only works if Claude Code actually sets `CLAUDE_PROJECT_DIR` in the shell environment before launching the plugin.

**Example:**
```json
{
  "mcpServers": {
    "discord": {
      "command": "bun",
      "args": ["run", "--cwd", "${CLAUDE_PLUGIN_ROOT}", "--shell=bun", "--silent", "start"],
      "env": {
        "CLAUDE_PROJECT_DIR": "${CLAUDE_PROJECT_DIR}"
      }
    }
  }
}
```

**Fallback behavior:** If `CLAUDE_PROJECT_DIR` is absent (older Claude Code version), `resolveAccessFile()` returns the global path — backward compatible.

### Pattern 2: Dual-Path Resolution with Full Isolation

**What:** `resolveAccessFile()` checks for a local access.json first; if present, it is the entire access config (no merge with global). If absent, global is used.

**When to use:** When the desired behavior is full project isolation — a project's channels should never bleed into another session.

**Trade-offs:** Simpler mental model than merge (no "which file wins for key X?"). Means a local file that only configures one group still suppresses global DM allowlists — the operator must be aware. This tradeoff was explicitly chosen in PROJECT.md.

**Example:**
```typescript
function resolveAccessFile(): { path: string; scope: 'local' | 'global' } {
  const projectDir = process.env.CLAUDE_PROJECT_DIR
  if (projectDir) {
    const localPath = join(projectDir, '.claude', 'channels', 'discord', 'access.json')
    try {
      statSync(localPath)
      return { path: localPath, scope: 'local' }
    } catch {
      // ENOENT — fall through to global
    }
  }
  return { path: ACCESS_FILE, scope: 'global' }
}
```

`readAccessFile()` and `saveAccess()` both call `resolveAccessFile()` to get the correct path rather than using the module-level `ACCESS_FILE` constant directly.

### Pattern 3: Skill-Side Scope Discovery

**What:** The `/discord:access` skill (running inside Claude Code, with access to the terminal environment) reads `CLAUDE_PROJECT_DIR` from the process environment to discover which scope to operate on.

**When to use:** Every `/discord:access` operation that reads or writes access.json.

**Trade-offs:** The skill runs as Claude's tool calls — it does not import `server.ts`. It must independently implement the same `resolveAccessFile()` logic using file system checks. This duplication is unavoidable given the skill/server boundary.

**Example (SKILL.md logic):**
```
Resolve active access file:
1. Check env: CLAUDE_PROJECT_DIR
2. If set, check: $CLAUDE_PROJECT_DIR/.claude/channels/discord/access.json
3. If that file exists → scope = "local", path = above
4. Else → scope = "global", path = ~/.claude/channels/discord/access.json
```

For `group add`, before writing:
```
Prompt: "Write to local project scope ($PROJECT_DIR/.claude/channels/discord/) or global (~/.claude/channels/discord/)?"
→ local: mkdir -p $PROJECT_DIR/.claude/channels/discord/ then write there
→ global: write to ~/.claude/channels/discord/access.json
```

## Data Flow

### Inbound Message Gating (Target State)

```
Discord gateway: messageCreate
    │
    ▼
handleInbound(msg)
    │
    ▼
gate(msg)
    │
    ▼
loadAccess()
    │
    ▼
resolveAccessFile()                    ← NEW
    │  checks CLAUDE_PROJECT_DIR env var
    │  if local access.json exists → return local path
    │  else → return global path
    │
    ▼
readAccessFile(resolvedPath)           ← path now varies
    │
    ▼
access.groups[channelId]?
    │  YES → deliver to Claude via mcp.notification()
    │  NO  → drop
```

### /discord:access skill — group add (Target State)

```
User: /discord:access group add <channelId>
    │
    ▼
SKILL.md executes (Claude's file tools)
    │
    ├── Read CLAUDE_PROJECT_DIR from env
    ├── Check $CLAUDE_PROJECT_DIR/.claude/channels/discord/access.json
    │
    ├── Prompt: local or global scope?
    │       ↓ local
    │       mkdir -p $PROJECT_DIR/.claude/channels/discord/
    │       Read existing local access.json (or create default)
    │       Add group entry
    │       Write to local path
    │
    │       ↓ global
    │       Read ~/.claude/channels/discord/access.json
    │       Add group entry
    │       Write to global path
    │
    └── Confirm: "Group <channelId> added to [local|global] access"
```

### /discord:access (no args) — status display (Target State)

```
SKILL.md resolves active file:
    ├── scope = 'local' → "Active: LOCAL  /path/to/project/.claude/channels/discord/access.json"
    └── scope = 'global' → "Active: GLOBAL  ~/.claude/channels/discord/access.json"

Then: show dmPolicy, allowFrom, groups, pending (same as before)
```

### saveAccess flow (Target State)

```
saveAccess(access) in server.ts
    │
    ▼
resolveAccessFile()
    │  returns { path, scope }
    │
    ▼
mkdirSync(dirname(path), { recursive: true, mode: 0o700 })
writeFileSync(path + '.tmp', ...)
renameSync(path + '.tmp', path)
    │
    NOTE: if scope = 'local', creates project-local dir automatically
    on first pairing/pending write triggered by that session
```

## Build Order

The components have the following dependency chain — build in this order:

```
1. .mcp.json env injection
       ↓ (server must receive CLAUDE_PROJECT_DIR before anything else works)
2. resolveAccessFile() in server.ts
       ↓ (all server path operations depend on this)
3. readAccessFile() + saveAccess() wired to resolveAccessFile()
       ↓ (gate(), loadAccess(), fetchAllowedChannel() all call these)
4. gate() / inbound message gating uses resolved path automatically
       ↓ (no code change — already calls loadAccess())
5. SKILL.md scope discovery + status display
       ↓ (skill must know which file is active before any write)
6. SKILL.md group add scope prompt + local write path
       ↓ (depends on skill-side scope resolution being correct)
7. SKILL.md group rm / pair / deny operating on correct file
```

Steps 1-4 are purely server-side and can be shipped together. Steps 5-7 are skill-side and depend only on steps 1-4 being stable (they share no runtime — skill reads files, server reads files, no IPC between them).

## Anti-Patterns

### Anti-Pattern 1: Merging Local + Global access.json

**What people do:** Union the `groups` from local with the `groups` from global so a project only needs to specify its additions.

**Why it's wrong:** Creates a non-obvious mental model. If global has a DM allowlist for user X, and a project creates a local file scoped to only guild channels, user X's DMs still arrive — surprising to the operator. Merge semantics for `pending` entries are especially ambiguous.

**Do this instead:** Full replacement — local access.json is the entire config for that session. If a project needs DM access, it adds it to its own local file. Explicitly chosen in PROJECT.md.

### Anti-Pattern 2: Scoping approved/ and inbox/ directories locally

**What people do:** Mirror the full state directory structure under the project dir, including `approved/<senderId>` and `inbox/`.

**Why it's wrong:** The pairing flow is DM-based (user-level). If the server polls a project-local `approved/` dir, and the approval was written by the skill running in a different session (which might have resolved to global scope), the approval handshake breaks silently.

**Do this instead:** `approved/` and `inbox/` always live in the global `STATE_DIR`. Only `access.json` is project-scoped.

### Anti-Pattern 3: Hardcoding the local access.json check in server.ts only

**What people do:** Add `resolveAccessFile()` to `server.ts` but leave `SKILL.md` pointing at `~/.claude/channels/discord/access.json` with no scope awareness.

**Why it's wrong:** The skill and server operate independently — skill edits the global file, server reads the local file, they diverge silently. The user sees groups listed in status but messages never arrive.

**Do this instead:** Implement scope resolution in both server.ts and SKILL.md. The logic is simple enough (stat one file, fall back) to duplicate safely.

### Anti-Pattern 4: Using process.cwd() to discover project directory

**What people do:** In `server.ts`, call `process.cwd()` expecting it to return the project directory.

**Why it's wrong:** The `.mcp.json` launch command explicitly sets `--cwd ${CLAUDE_PLUGIN_ROOT}`, so `process.cwd()` always returns the plugin root, not the project directory.

**Do this instead:** Use `process.env.CLAUDE_PROJECT_DIR` exclusively. Pass it explicitly via `.mcp.json`'s `env` block.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Discord gateway | discord.js `Client` with GatewayIntentBits | Unchanged — gating logic is access-file-only |
| MCP protocol | `@modelcontextprotocol/sdk` stdio transport | Unchanged |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| server.ts ↔ access.json | Filesystem read/write | `resolveAccessFile()` determines which path; atomic rename-write preserved |
| SKILL.md ↔ access.json | Claude's Read/Write tools | Skill must implement same resolution logic as server — no shared runtime |
| server.ts ↔ approved/ | Filesystem poll (5s interval) | Always global path — DM pairing is user-level |
| .mcp.json ↔ server.ts | Process environment variables | `CLAUDE_PROJECT_DIR` is the new injection point |
| Claude Code ↔ .mcp.json | `${CLAUDE_PROJECT_DIR}` variable substitution | Depends on Claude Code expanding this in env blocks — verify version support |

## Sources

- Direct source inspection: `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/server.ts` (full file)
- Direct source inspection: `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/skills/access/SKILL.md`
- Direct source inspection: `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/.mcp.json`
- Project requirements: `/Users/haocheng_mini/Documents/projects/claude_code_channels/.planning/PROJECT.md`

---
*Architecture research for: Discord MCP server project-local access control upgrade*
*Researched: 2026-03-23*
