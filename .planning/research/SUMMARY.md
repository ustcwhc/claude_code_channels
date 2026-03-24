# Project Research Summary

**Project:** Claude Code Channels — Discord MCP Plugin Project-Local Config Scoping
**Domain:** MCP server plugin upgrade — project-scoped access control
**Researched:** 2026-03-23
**Confidence:** HIGH

## Executive Summary

This project upgrades an existing Claude Code Discord MCP plugin to support project-local configuration scoping. The plugin currently uses a single global `access.json` at `~/.claude/channels/discord/access.json` for all sessions, causing Discord channel groups configured for one project to bleed into others. The upgrade introduces a per-project `access.json` at `.claude/channels/discord/access.json` inside the project root, with full replacement semantics (local file completely overrides global — no merge). This matches the mental model established by git's local/global config split and eliminates cross-project leakage by design.

The entire implementation is additive and backward-compatible. No new dependencies are required. The core mechanism is: Claude Code injects `CLAUDE_PROJECT_DIR` into the MCP server's environment via the `.mcp.json` `env` block; the server reads `process.env.CLAUDE_PROJECT_DIR` at boot and resolves the active access file path — local if it exists, global otherwise. The same resolution logic must be duplicated in the `/discord:access` skill (SKILL.md) because the skill and server are separate processes that share state only via the filesystem.

The two most critical risks are: (1) the server's cwd is `CLAUDE_PLUGIN_ROOT`, not the project directory — any code using `process.cwd()` for project discovery silently fails; and (2) changes made directly to `~/.claude/plugins/cache/` are erased on plugin updates — the code residency strategy must be decided before writing any implementation. Both risks must be resolved in Phase 1 before any feature work begins.

## Key Findings

### Recommended Stack

No new dependencies are required. The existing stack (Bun + discord.js + `@modelcontextprotocol/sdk`) is unchanged. The `env` block in `.mcp.json` supports `${CLAUDE_PROJECT_DIR}` substitution, confirmed by the official `plugin-dev` skill examples (Claude Code v1.0.58+). The server uses built-in `fs.statSync` and `path.join` — already imported — to check for the local access file at boot.

The chosen local config path is `.claude/channels/discord/access.json` inside the project root. This mirrors the global path structure and makes the `/discord:access` skill's discovery logic straightforward (same path shape, different root).

**Core technologies:**
- Bun: runtime and package manager — already in use, no change
- `@modelcontextprotocol/sdk`: MCP stdio transport — already in use, no change
- discord.js: Discord gateway client — already in use, no change
- Node.js `fs`/`path` (built-in): local file resolution at boot — already imported

### Expected Features

The feature set is well-defined. All P1 features are low-complexity; the scope prompt in `group add` is the only MEDIUM item (requires knowing the active file before writing).

**Must have (table stakes):**
- Project dir passed via env var to server and skill — foundational; nothing else works without it
- Server reads local access.json at startup, falls back to global — the core routing behavior
- `group add` prompts for local vs global scope — the UX moment where project isolation is established
- Status command (`/discord:access` no args) shows which file is active and its full path — required for debugging
- `group rm` operates on the correct file — editing the wrong file is silent data corruption

**Should have (competitive):**
- `--local` / `--global` flags on `group add` — power-user scripting, avoids interactive prompt
- Full resolved path shown in status output — reduces "which file am I editing?" confusion
- Warning when a channel group appears in both local and global config — informational safety net

**Defer (v2+):**
- Default scope inferred from whether a local config already exists — adds magic; explicit prompt is safer until patterns emerge
- `config init` command to scaffold a local access.json — useful if project dotfile workflows become common

### Architecture Approach

The upgrade touches three components: `.mcp.json` (env injection), `server.ts` (new `resolveAccessFile()` function + wiring), and `SKILL.md` (scope discovery and scope-aware writes). The rest of the server — `gate()`, `loadAccess()`, `fetchAllowedChannel()`, `checkApprovals()` — is untouched. `approved/` and `inbox/` directories remain global by design: the pairing approval handshake is DM-based (user-level) and must not be scoped to a project.

**Major components:**
1. `.mcp.json` env injection — passes `CLAUDE_PROJECT_DIR` to server process; one-line change
2. `resolveAccessFile()` in `server.ts` — checks for local access.json, returns `{ path, scope }`, called by `readAccessFile()` and `saveAccess()`
3. `/discord:access` SKILL.md scope awareness — independent reimplementation of the same resolution logic; writes to the correct file; displays active scope in status

**Build order (dependency chain):**
1. `.mcp.json` env injection (server must receive `CLAUDE_PROJECT_DIR` first)
2. `resolveAccessFile()` in server.ts
3. `readAccessFile()` + `saveAccess()` wired to resolved path
4. SKILL.md scope discovery + status display
5. SKILL.md `group add` scope prompt + local write
6. SKILL.md `group rm` / `pair` / `deny` on correct file

Steps 1–3 are server-side and can ship together. Steps 4–6 are skill-side and depend only on steps 1–3 being stable.

### Critical Pitfalls

1. **Wrong cwd for project discovery** — `process.cwd()` returns `CLAUDE_PLUGIN_ROOT`, not the project. Use `process.env.DISCORD_PROJECT_DIR` exclusively. Never use cwd, `__dirname`, or argv for project dir inference.

2. **Plugin cache overwrite erases server.ts changes** — `~/.claude/plugins/cache/` is replaced on plugin updates. Decide code residency strategy before writing any logic into server.ts (upstream PR, local override path, or external sidecar). This is a Phase 1 gate.

3. **Skill-vs-server config file desync** — skill and server are separate processes sharing state via the filesystem only. If skill still writes to the hardcoded global path while server reads a local path, `group add` silently has no effect. Scope resolution must be implemented in both independently.

4. **approved/ polling IPC mismatch** — `APPROVED_DIR` is polled by the server every 5s. If skill writes approval files to a different dir than the server polls, pairing confirmation DMs never fire. Resolution: keep `approved/` always at the global path; only `access.json` is project-scoped.

5. **Backward compat break** — if `CLAUDE_PROJECT_DIR` is absent (old Claude Code version or config not updated), the server must silently fall back to global, not crash. The fallback and the env var check must ship in the same commit.

## Implications for Roadmap

Based on research, the natural phase split follows the build order dependency chain: server-side first, skill-side second. This is a 2-phase project with a possible cleanup phase for polish.

### Phase 1: Server-Side Scoping Foundation

**Rationale:** Everything depends on the server correctly receiving and resolving the project directory. The skill cannot be correctly updated until the server's resolution logic is stable and testable. This phase also forces the code residency decision — editing a cached file that will be overwritten is a critical risk that blocks shipping.

**Delivers:** A running MCP server that automatically loads the correct access.json (local if present, global otherwise) with a boot log line confirming which file is active. Backward compatibility with sessions that have no local config is preserved exactly.

**Addresses:** Project dir via env var (P1), server reads local config with global fallback (P1), backward compat (P1), silent fallback observability (P1)

**Avoids:** Wrong cwd pitfall, plugin cache overwrite pitfall, backward compat break pitfall, shared bot race documentation

**Research flag:** None — all patterns are well-documented and directly confirmed by source code inspection.

### Phase 2: Skill-Side Scope Awareness

**Rationale:** The skill and server operate independently; the skill must be taught the same resolution logic. Without this phase, `group add` writes to the wrong file and the feature appears to work but silently does nothing. This phase also covers the approved/ IPC contract — keeping it at global STATE_DIR prevents the pairing confirmation break.

**Delivers:** `/discord:access` skill that shows active config scope/path in status, prompts for local vs global on `group add`, writes to the correct file, and correctly handles `group rm`, `pair`, and `deny` operations against the active file.

**Addresses:** Status shows active file (P1), `group add` scope prompt (P1), `group rm` on correct file (P1)

**Avoids:** Skill-server desync pitfall, approved/ IPC mismatch pitfall

**Research flag:** None — SKILL.md pattern is straightforward file tool usage; no novel integration required.

### Phase 3: Polish and Power-User Ergonomics (Optional)

**Rationale:** Once core functionality is working, low-effort quality-of-life improvements for users who script project setup. These are P2/P3 features with no hard dependencies on each other.

**Delivers:** `--local` / `--global` flags on `group add`, full resolved path in status output, warning when a channel group appears in both local and global config.

**Addresses:** `--local/--global` flags (P2), full path in status (P2), duplicate group warning (P3)

**Research flag:** None — all enhancements are simple additions to the SKILL.md logic from Phase 2.

### Phase Ordering Rationale

- Server-before-skill ordering is forced by the architecture: the skill cannot be verified correct until the server's resolution logic is stable and observable (boot log).
- Code residency decision (where server.ts changes live permanently) is gated in Phase 1 because any implementation is worthless if it gets wiped on the next plugin update.
- Phase 3 is explicitly deferred: all P2/P3 features add ergonomics, not correctness. Shipping Phase 1+2 first lets real usage reveal whether scripting (`--flags`) or deduplication warnings are actually needed.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 1:** Plugin cache override mechanism — the LOCAL confidence on the "local override path" for `~/.claude/plugins/local/` needs verification before committing to a residency strategy. This is the one open question in the entire project.

Phases with standard patterns (skip research-phase):
- **Phase 2:** Skill-side scope logic is straightforward Claude file tool usage with no novel patterns.
- **Phase 3:** All polish features are simple SKILL.md additions.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | No new dependencies; confirmed `${CLAUDE_PROJECT_DIR}` env substitution via official plugin-dev skill examples and v1.0.58 changelog |
| Features | HIGH | Feature set derived from established CLI tools (git, npm, ESLint); all P1 features confirmed against PROJECT.md decisions |
| Architecture | HIGH | Based on direct source inspection of server.ts, SKILL.md, and .mcp.json from the existing plugin |
| Pitfalls | HIGH | All critical pitfalls identified from direct code inspection; confirmed by project requirements in PROJECT.md |

**Overall confidence:** HIGH

### Gaps to Address

- **Plugin cache residency strategy (LOW confidence):** Whether `~/.claude/plugins/local/` exists as an override path needs verification before Phase 1 implementation begins. If no such path exists, the change must either be upstreamed to the plugin source as a new version, or implemented as an external sidecar module imported by server.ts. This is the only open question gating Phase 1.

- **SKILL.md env var availability:** Whether `CLAUDE_PROJECT_DIR` is available to the skill process (Claude's tool environment) needs testing. The safer approach (skill uses `Bash(pwd)` to discover project root) is documented in STACK.md as a fallback if the env var is not forwarded to skill execution context.

## Sources

### Primary (HIGH confidence)
- `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/mcp-integration/SKILL.md` — env var substitution in .mcp.json env blocks
- `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/mcp-integration/examples/stdio-server.json` — `${CLAUDE_PROJECT_DIR}` in args confirmed
- `~/.claude/cache/changelog.md` line 1989 — v1.0.58 changelog: `CLAUDE_PROJECT_DIR` env var for hook commands
- `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/server.ts` — full source inspection; STATE_DIR, ACCESS_FILE, saveAccess, gate, checkApprovals
- `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/skills/access/SKILL.md` — confirmed hardcoded global path
- `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/.mcp.json` — confirmed current launch command

### Secondary (MEDIUM confidence)
- git config documentation (`git config --help`) — local/global/system hierarchy reference for feature design
- npm .npmrc resolution (npm docs) — config file cascade reference

### Tertiary (LOW confidence)
- `~/.claude/plugins/local/` override path — not confirmed; needs verification before Phase 1

---
*Research completed: 2026-03-23*
*Ready for roadmap: yes*
