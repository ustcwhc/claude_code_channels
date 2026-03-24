# Phase 1: Server-Side Scoping - Context

**Gathered:** 2026-03-23
**Status:** Ready for planning

<domain>
## Phase Boundary

MCP server resolves project directory from env var, loads project-local `access.json` if present, falls back to global `~/.claude/channels/discord/access.json` when absent. Changes must survive plugin cache updates.

</domain>

<decisions>
## Implementation Decisions

### Code Residency
- **D-01:** Use a git-style diff `.patch` file stored in this repo, applied via a Claude Code hook
- **D-02:** Hook fires on every Claude Code session start — checks if patch is already applied, applies if not
- **D-03:** Patch targets `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/server.ts` and `.mcp.json`

### Env Var Plumbing
- **D-04:** Add `"DISCORD_PROJECT_DIR": "${CLAUDE_PROJECT_DIR}"` to `.mcp.json` `env` block — cleanest injection path
- **D-05:** Env var named `DISCORD_PROJECT_DIR` (plugin-specific, won't conflict with other plugins)
- **D-06:** If `DISCORD_PROJECT_DIR` is unset: log a visible warning that project scoping is unavailable, then fall back to global

### File Resolution
- **D-07:** If project dir is set but no local `access.json` exists → fall back to global (user must create via `/discord:access`)
- **D-08:** If local `access.json` is corrupt (invalid JSON) → error and stop (don't rename aside — force user to fix)
- **D-09:** When local is active, full isolation — DMs are also gated by local config. If local has no `allowFrom`, DMs won't be delivered to that session
- **D-10:** DM operations (pairing pending writes) always go to global `access.json` — avoids polluting local with DM state
- **D-11:** Channel group writes go to whichever file was resolved at boot

### Pairing in Local Mode
- **D-12:** Claude's discretion — choose the least surprising behavior for pairing when local config is active. Likely: pairing reads global for pending checks, but gate() uses local for delivery

### Boot Logging
- **D-13:** One-liner at boot: `"discord channel: using local config /path/..."` or `"discord channel: using global config /path/..."`

### Claude's Discretion
- Exact patch application mechanism (how to detect "already applied")
- Pairing behavior when local config is active (D-12)
- Whether `resolveAccessFile()` caches the result at boot or re-resolves on each call
- Exact error message format for corrupt local file

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Plugin Source (modify targets)
- `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/server.ts` — Full MCP server implementation; `readAccessFile()` at line 147, `saveAccess()` at line 191, `loadAccess()` at line 187, `gate()` at line 230
- `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/.mcp.json` — MCP server launch config; needs `env` block added

### Research
- `.planning/research/ARCHITECTURE.md` — Component boundaries, data flow, build order for the scoping change
- `.planning/research/PITFALLS.md` — Code residency risk, skill-server desync, approved/ IPC issues
- `.planning/research/STACK.md` — `${CLAUDE_PROJECT_DIR}` availability confirmation, `.mcp.json` env block pattern

### Project Context
- `.planning/PROJECT.md` — Constraints, key decisions (local replaces global, env var approach)
- `.planning/REQUIREMENTS.md` — SERV-01 through SERV-06, RESL-01, RESL-02

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `readAccessFile()` (server.ts:147) — current global-only reader, extend to local resolution
- `saveAccess()` (server.ts:191) — current global-only writer, needs split behavior (channel writes → resolved, DM writes → global)
- `DISCORD_STATE_DIR` env var pattern (server.ts:33) — existing pattern for path override via env var

### Established Patterns
- Atomic write pattern: `writeFileSync(tmp)` then `renameSync(tmp, target)` — keep this for local writes too
- Corrupt file handling: `renameSync(file, file.corrupt-timestamp)` — used for global, but local should error instead per D-08
- `process.stderr.write()` for all server logging — consistent, no dependency

### Integration Points
- `loadAccess()` (server.ts:187) — single entry point for all access reads; modify this to route through `resolveAccessFile()`
- `gate()` (server.ts:230) — calls `loadAccess()` for every inbound message; must use resolved file
- `fetchAllowedChannel()` (server.ts:399) — outbound gate; calls `loadAccess()`, same resolution needed
- `BOOT_ACCESS` (server.ts:173) — static mode snapshot; must snapshot from resolved file

</code_context>

<specifics>
## Specific Ideas

- Patch should be idempotent — running it twice doesn't break anything
- Hook should be fast — just check a marker (e.g., grep for a comment line added by the patch) and skip if already applied
- The one-liner boot log should include the full absolute path so the user can find and edit the file

</specifics>

<deferred>
## Deferred Ideas

- `/discord:access` skill changes — Phase 2
- `--local`/`--global` flags — Phase 3
- Duplicate group warning — Phase 3

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-server-side-scoping*
*Context gathered: 2026-03-23*
