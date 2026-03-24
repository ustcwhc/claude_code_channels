# Roadmap: Claude Code Channels

## Overview

Ship project-local Discord channel scoping in three phases: first make the MCP server resolve the correct access.json (local beats global), then teach the `/discord:access` skill the same resolution logic so writes go to the right file, then add power-user ergonomics. Each phase is independently shippable and verifiable against real behavior.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Server-Side Scoping** - MCP server resolves project dir, loads local access.json if present, falls back to global
- [ ] **Phase 2: Skill-Side Scope Awareness** - `/discord:access` skill reads and writes the correct file with scope prompt on `group add`
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
**Plans**: TBD

Plans:
- [ ] 01-01: Decide and implement code residency strategy (prevents cache wipe)
- [ ] 01-02: Add env var injection to `.mcp.json` and `resolveAccessFile()` to server.ts

### Phase 2: Skill-Side Scope Awareness
**Goal**: The `/discord:access` skill independently resolves the active config file and all writes (`group add`, `group rm`) land in the correct file
**Depends on**: Phase 1
**Requirements**: SKIL-01, SKIL-02, SKIL-03, SKIL-04, SKIL-05, SKIL-06, SKIL-07
**Success Criteria** (what must be TRUE):
  1. `/discord:access` (no args) displays "local" or "global" label indicating which file is active
  2. `/discord:access group add <channelId>` prompts the user to choose local vs global scope before writing
  3. Choosing "local" creates `.claude/channels/discord/access.json` in the project directory and adds the group there
  4. Choosing "global" adds the group to `~/.claude/channels/discord/access.json` (existing behavior, unchanged)
  5. `/discord:access group rm <channelId>` removes the group from whichever file contains it — not silently from the wrong one
**Plans**: TBD

Plans:
- [ ] 02-01: Update SKILL.md scope resolution, status display, and `group add` scope prompt
- [ ] 02-02: Update SKILL.md `group rm`, `pair`, and `deny` to operate on the resolved file

### Phase 3: UX Polish
**Goal**: Power users can bypass the scope prompt with flags, and the status output surfaces enough detail to debug routing issues
**Depends on**: Phase 2
**Requirements**: UX-01, UX-02
**Success Criteria** (what must be TRUE):
  1. `/discord:access` status shows the full absolute path of the active config file, not just "local" or "global"
  2. When the same channel group ID appears in both local and global config, a warning is shown (informational, not blocking)
**Plans**: TBD

Plans:
- [ ] 03-01: Add full resolved path to status output and duplicate-group detection warning

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Server-Side Scoping | 0/2 | Not started | - |
| 2. Skill-Side Scope Awareness | 0/2 | Not started | - |
| 3. UX Polish | 0/1 | Not started | - |
