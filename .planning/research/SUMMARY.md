# Project Research Summary

**Project:** Claude Code Channels -- Project-Local Discord Access (Milestone 2)
**Domain:** MCP plugin patching -- project-local config scoping
**Researched:** 2026-03-25
**Confidence:** HIGH

## Executive Summary

This project extends the official Claude Code Discord plugin with project-local channel scoping so that multiple Claude Code sessions in different project directories each receive only messages from their paired Discord channels. The core mechanism is a patch-based system: bash scripts modify the plugin's cached files (server.ts, .mcp.json, SKILL.md) on every session start via a SessionStart hook. The v1.1 attempt was fully reverted because its central feature -- delivering the project directory to the MCP server process -- was broken. The root cause is now well understood: the `sh -c` wrapper with `$PWD` does not capture the project directory because Claude Code does not spawn MCP servers with the project directory as cwd.

The fix is straightforward and well-supported by official documentation: replace the `sh -c` wrapper with a `.mcp.json` `env` block that uses Claude Code's own `${CLAUDE_PROJECT_DIR}` template variable, which is expanded before process spawn. This is the same mechanism used in the official `stdio-server.json` example. Beyond the core fix, Milestone 2 adds modular install/uninstall scripts (replacing the monolithic apply script), a session greeting to Discord, channel ID display in the CLI, and stripping of rich media code to establish a clean baseline.

The primary risk is that `${CLAUDE_PROJECT_DIR}` expansion in the `env` block -- while documented as supported "in all fields" -- has no official example specifically in an `env` block (only in `args`). This needs empirical verification early in Phase 1. If it fails, a documented fallback exists: a SessionStart hook writing to `$CLAUDE_ENV_FILE`. Secondary risks are plugin version drift breaking patch anchors (already happened once with 0.0.1 to 0.0.4) and nested bash/JS quoting bugs in `bun -e` inline scripts.

## Key Findings

### Recommended Stack

The stack is fixed -- Bun, discord.js, and `@modelcontextprotocol/sdk` are already in use and there is no reason to change. The patching infrastructure uses POSIX bash with `bun -e` for JSON/TypeScript manipulation (avoiding new dependencies like `jq`). The key stack decision is using Claude Code's `${CLAUDE_PROJECT_DIR}` template variable (available since v1.0.58) instead of shell-level `$PWD` workarounds.

**Core technologies:**
- **Bun 1.3.11**: Runtime + package manager -- already in use, no change needed
- **Bash (POSIX)**: Install/uninstall scripts -- established pattern, scripts are glue code
- **`bun -e` inline scripts**: TypeScript/JSON manipulation in patches -- avoids `jq` dependency
- **`${CLAUDE_PROJECT_DIR}`**: MCP config template variable -- the correct way to pass project dir to server

### Expected Features

**Must have (table stakes):**
- **Modular install/uninstall scripts** -- delivery framework for all patches; must be idempotent and re-runnable from SessionStart hook
- **Fix DISCORD_PROJECT_DIR propagation** -- the entire project-local scoping feature is non-functional without this

**Should have (differentiators):**
- **Session greeting to Discord** -- low complexity, high user-facing impact; confirms session is alive
- **Channel ID display in CLI** -- low complexity, removes guesswork about active channels
- **Strip rich media support** -- creates clean baseline; removes untested attachment code paths

**Defer (v2+):**
- Rich media re-implementation (needs proper testing, file size handling, content-type validation)
- Greeting customization (templates, rich embeds)
- GUI for channel management
- Multi-bot support
- Hot-reload of config changes mid-session

### Architecture Approach

The architecture is a three-layer system: (1) a project repo containing modular patch scripts and hook config, (2) the plugin cache which gets patched at runtime, and (3) the running MCP server process that uses the patched code. The install script orchestrates numbered patch components (`patches/common.sh`, `patches/mcp-json.sh`, `patches/server-ts.sh`, etc.), each gated by unique markers for idempotency. The uninstall script reverses patches in reverse order using marker-delimited block removal and `.orig` file backups. The SessionStart hook ensures patches survive plugin cache wipes.

**Major components:**
1. **`install.sh` / `uninstall.sh`** -- orchestrators that discover the plugin directory, source patch modules, and run them in order
2. **`patches/common.sh`** -- shared utilities: find latest plugin version, marker checks, path constants
3. **`patches/mcp-json.sh`** -- adds `env` block with `DISCORD_PROJECT_DIR` mapping to `.mcp.json`
4. **`patches/server-ts.sh`** -- injects `resolveAccessFile()` into server.ts via anchor-based `bun -e` insertion
5. **`patches/skill-md.sh`** -- copies scope-aware SKILL.md to plugin skills directory
6. **Feature patch scripts** (Phase 2) -- `greeting.sh`, `strip-rich-media.sh`, `channel-id-display.sh`

### Critical Pitfalls

1. **`$PWD` does not capture project directory** -- Claude Code does not set cwd to project dir before spawning MCP servers. Use `${CLAUDE_PROJECT_DIR}` in the `.mcp.json` `env` block instead. This is THE root cause of the v1.1 failure.
2. **Plugin version drift breaks patch anchors** -- v0.0.1 to v0.0.4 already caused shifts. Pin expected version, test all anchors before patching, add post-patch coherence checks to ensure server.ts and .mcp.json patches are both present or both absent.
3. **Partial patch application creates incoherent state** -- if `.mcp.json` is patched but server.ts anchor is missing, the env var is set but no code reads it. Add a post-patch validation step that checks all markers.
4. **Nested bash/JS quoting in `bun -e`** -- multi-layer escaping (bash > JS > template literals > regex) produces silent bugs like literal `\\n` in output. Move complex patch logic to standalone `.ts` files where feasible.
5. **Skill-server config desync** -- the `/discord:access` skill runs in a different process context than the MCP server. The skill must use `CLAUDE_PROJECT_DIR` (available in Claude's tool execution environment), not `DISCORD_PROJECT_DIR` (server-only env var).

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Core Infrastructure Fix

**Rationale:** Everything else depends on two things working: (1) the install framework to deliver patches, and (2) the env var fix so project-local scoping actually functions. This is the critical path identified by all four research files.

**Delivers:** Modular install/uninstall scripts, fixed `.mcp.json` env block with `${CLAUDE_PROJECT_DIR}`, SessionStart hook wiring, backup/restore mechanism, post-patch coherence validation.

**Addresses:** Feature 1 (install/uninstall) and Feature 2 (env var fix) from FEATURES.md.

**Avoids:** Pitfalls 1 ($PWD), 2 (version drift), 3 (sh -c wrapper), 4 (partial application), 5 (quoting), 6 (PWD vs CLAUDE_PROJECT_DIR), 7 (cache wipe), 8 (delete env), 11 (JSON format assumption), 12 (no rollback).

### Phase 2: Session Awareness Features

**Rationale:** With the install framework in place and env var delivery working, greeting and channel display are low-complexity additions that each become a new file in `scripts/patches/`. They naturally pair because both fire at server startup and both improve the "is this thing on?" experience. This phase also addresses the skill-server desync pitfall.

**Delivers:** Discord greeting message on session start (with project name), channel ID/name display in CLI stderr, updated SKILL.md for scope-aware access management.

**Addresses:** Feature 3 (greeting) and Feature 4 (channel display) from FEATURES.md.

**Avoids:** Pitfall 9 (skill-server desync) -- skill must use `CLAUDE_PROJECT_DIR` not `DISCORD_PROJECT_DIR`.

### Phase 3: Strip Rich Media

**Rationale:** Independent of scoping features, depends only on the install framework from Phase 1. Medium complexity due to 6+ code locations in server.ts. Best done last to avoid conflicts with Phase 2 server.ts patches.

**Delivers:** Clean server.ts without attachment download/upload code paths, updated tool descriptions that do not mention attachment capabilities, graceful handling of messages that contain only attachments.

**Addresses:** Feature 5 (strip rich media) from FEATURES.md.

**Avoids:** Pitfall 2 (anchor drift) -- more anchors means more version-sensitivity; doing this last minimizes the surface area during Phase 1/2 development.

### Phase Ordering Rationale

- **Phase 1 first** because it is the critical path: every other feature depends on the install framework and working env var delivery. All four research files independently identify the `.mcp.json` fix as the top priority.
- **Phase 2 before Phase 3** because greeting and channel display are low complexity (each is a single API call + error handling) and directly address user-facing friction. They validate the install framework with simple additions before the more invasive rich media strip.
- **Phase 3 last** because it touches the most code locations (6+) and is the most likely to conflict with upstream plugin changes. Isolating it reduces risk during the critical Phase 1 work.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 1:** Needs empirical verification that `${CLAUDE_PROJECT_DIR}` expands in `.mcp.json` `env` blocks (not just `args`). Plan the fallback (`$CLAUDE_ENV_FILE` via hook) before starting. Also needs inspection of current v0.0.4 server.ts to verify all anchor strings are still present.

Phases with standard patterns (skip research-phase):
- **Phase 2:** Session greeting and channel display are straightforward Discord.js API calls. The patterns are well-documented and the install framework from Phase 1 makes adding them mechanical.
- **Phase 3:** Rich media stripping is code removal, not addition. The code locations are already mapped in FEATURES.md (6 specific line references in server.ts v0.0.4).

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Stack is fixed (Bun + discord.js); no decisions to make. `${CLAUDE_PROJECT_DIR}` confirmed by official examples in `args`. |
| Features | HIGH | All 5 features directly inspected in codebase; complexity estimates grounded in line-level code analysis. |
| Architecture | HIGH | Component layout, data flow, and integration points derived from direct inspection of plugin source and official MCP docs. |
| Pitfalls | HIGH | Root cause of v1.1 failure identified with evidence from multiple sources; all pitfalls have concrete prevention strategies. |

**Overall confidence:** HIGH

### Gaps to Address

- **`${CLAUDE_PROJECT_DIR}` in `env` block expansion**: MEDIUM confidence. Official docs say "all fields" support expansion, but no example shows it in `env` specifically. Must verify empirically in Phase 1 before committing to this approach. Fallback: SessionStart hook writing to `$CLAUDE_ENV_FILE`.
- **v0.0.4 anchor stability**: Anchors were identified against the current version but could shift in a future plugin update. The install script needs a version pin or anchor pre-check to detect breakage early.
- **Skill process environment**: Whether `CLAUDE_PROJECT_DIR` is available when the `/discord:access` skill executes file operations needs verification. The skill runs in Claude's tool execution context, not the MCP server process.

## Sources

### Primary (HIGH confidence)
- Official MCP integration SKILL.md -- documents env var substitution in `.mcp.json` fields
- Official `stdio-server.json` example -- confirms `${CLAUDE_PROJECT_DIR}` in MCP config args
- Official hook-development SKILL.md -- documents `$CLAUDE_PROJECT_DIR` for hooks, `$CLAUDE_ENV_FILE` for env propagation
- Claude Code changelog v1.0.58 -- `CLAUDE_PROJECT_DIR` env var addition
- Claude Code changelog v2.1.78 -- `CLAUDE_PLUGIN_DATA` persistent directory

### Secondary (MEDIUM confidence)
- MCP integration docs claim "all fields" support `${VAR}` expansion -- no specific `env` block example exists
- Plugin-settings SKILL.md documents `.local.md` pattern -- alternative config path convention

### Tertiary (direct inspection, HIGH confidence for current state)
- `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.4/server.ts` -- 921 lines, all patch anchors verified
- `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.4/.mcp.json` -- current broken `sh -c` wrapper
- `scripts/apply-discord-patch.sh` -- current monolithic install script
- Git history `46a7b6d` -- v1.1 revert commit confirming full rollback

---
*Research completed: 2026-03-25*
*Ready for roadmap: yes*
