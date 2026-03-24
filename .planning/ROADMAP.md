# Roadmap: Claude Code Channels

## Overview

Ship project-local Discord channel scoping in three phases: first make the MCP server resolve the correct access.json (local beats global), then teach the `/discord:access` skill the same resolution logic so writes go to the right file, then add power-user ergonomics. Each phase is independently shippable and verifiable against real behavior.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Server-Side Scoping** - MCP server resolves project dir, loads local access.json if present, falls back to global (completed 2026-03-24)
- [x] **Phase 2: Skill-Side Scope Awareness** - `/discord:access` skill reads and writes the correct file with scope prompt on `group add` (completed 2026-03-24)
- [ ] **Phase 3: UX Polish** - `--local`/`--global` flags, full resolved path in status, duplicate-group warning

## Phase Details

### Phase 1: Server-Side Scoping
**Goal**: The MCP server correctly loads the project-local access.json when present, falls back to global when absent, and survives plugin cache updates
**Depends on**: Nothing (first phase)
**Requirements**: SERV-01, SERV-02, SERV-03, SERV-04, SERV-05, SERV-06, RESL-01, RESL-02
**Success Criteria** (what must be TRUE):
  1. Starting a Claude Code session in a project with `.claude/channels/discord/access.json` causes the server to use only that file — global channel groups are not visible
  2. Starting a session in a project with no local config causes the server to behave exactly as before — global access.json is used, no crash
  3. Missing or unset `DISCORD_PROJECT_DIR` env var causes silent fallback to global, not a server crash
  4. A boot log line confirms which file (local path or global) is active, enabling debugging
  5. Changes to server.ts survive a plugin cache update (code residency strategy implemented)
**Plans**: 2 plans

Plans:
- [x] 01-01-PLAN.md — Patch delivery mechanism: idempotent apply script + SessionStart hook registration
- [x] 01-02-PLAN.md — Env var injection (.mcp.json) + resolveAccessFile() + readAccessFile/saveAccess wiring + patch generation

### Phase 2: Skill-Side Scope Awareness
**Goal**: The `/discord:access` skill independently resolves the active config file and all writes (`group add`, `group rm`) land in the correct file
**Depends on**: Phase 1
**Requirements**: SKIL-01, SKIL-02, SKIL-03, SKIL-04, SKIL-05, SKIL-06, SKIL-07
**Note**: SKIL-06 (--local flag) and SKIL-07 (--global flag) are deferred to Phase 3 per user decision in 02-CONTEXT.md.
**Success Criteria** (what must be TRUE):
  1. `/discord:access` (no args) displays "local" or "global" label indicating which file is active
  2. `/discord:access group add <channelId>` prompts the user to choose local vs global scope before writing
  3. Choosing "local" creates `.claude/channels/discord/access.json` in the project directory and adds the group there
  4. Choosing "global" adds the group to `~/.claude/channels/discord/access.json` (existing behavior, unchanged)
  5. `/discord:access group rm <channelId>` removes the group from whichever file contains it — not silently from the wrong one
**Plans**: 2 plans

Plans:
- [x] 02-01-PLAN.md — Rewrite SKILL.md with scope resolution helper, status banner, group add scope prompt, group rm dual-file search
- [x] 02-02-PLAN.md — Generate SKILL.md patch hunk, append to discord-local-scoping.patch, extend apply script to check SKILL.md marker

### Phase 3: UX Polish
**Goal**: Power users can bypass the scope prompt with flags, and the status output surfaces enough detail to debug routing issues
**Depends on**: Phase 2
**Requirements**: UX-01, UX-02, SKIL-06, SKIL-07
**Success Criteria** (what must be TRUE):
  1. `/discord:access` status shows the full absolute path of the active config file, not just "local" or "global"
  2. When the same channel group ID appears in both local and global config, a warning is shown (informational, not blocking)
  3. `--local` flag on `group add` skips scope prompt, writes to project-local file
  4. `--global` flag on `group add` skips scope prompt, writes to global file
**Plans**: TBD

Plans:
- [ ] 03-01: Add full resolved path to status output, duplicate-group detection warning, and --local/--global flags

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Server-Side Scoping | 2/2 | Complete   | 2026-03-24 |
| 2. Skill-Side Scope Awareness | 2/2 | Complete   | 2026-03-24 |
| 3. UX Polish | 0/1 | Not started | - |
