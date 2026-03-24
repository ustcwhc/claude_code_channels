# Requirements: Claude Code Channels

**Defined:** 2026-03-23
**Core Value:** Discord messages reach the correct Claude Code session based on project directory — no cross-talk

## v1 Requirements

### Server Scoping

- [x] **SERV-01**: Server resolves project directory from `DISCORD_PROJECT_DIR` env var at startup
- [x] **SERV-02**: `.mcp.json` passes `${CLAUDE_PROJECT_DIR}` to server via `env` block as `DISCORD_PROJECT_DIR`
- [x] **SERV-03**: If `<projectDir>/.claude/channels/discord/access.json` exists, server uses it exclusively (full replacement)
- [x] **SERV-04**: If no local access.json exists, server falls back to `~/.claude/channels/discord/access.json` (backward compatible)
- [x] **SERV-05**: `saveAccess()` writes to the resolved file (local or global), not hardcoded global path
- [x] **SERV-06**: `approved/` and `inbox/` directories remain at global `STATE_DIR` (pairing is user-level)

### Skill Scoping

- [ ] **SKIL-01**: `/discord:access` (no args) shows which file is active — full path + "local" or "global" label
- [ ] **SKIL-02**: `/discord:access group add <channelId>` prompts user to choose local vs global scope
- [ ] **SKIL-03**: Choosing "local" creates/writes `./.claude/channels/discord/access.json` in project directory
- [ ] **SKIL-04**: Choosing "global" writes to `~/.claude/channels/discord/access.json` (existing behavior)
- [ ] **SKIL-05**: `/discord:access group rm <channelId>` edits whichever file contains that channel group
- [ ] **SKIL-06**: `--local` flag on `group add` skips scope prompt, writes to project-local file
- [ ] **SKIL-07**: `--global` flag on `group add` skips scope prompt, writes to global file

### UX Polish

- [ ] **UX-01**: Status output shows full resolved path of active config file
- [ ] **UX-02**: Warn when a channel group appears in both local and global config (informational only)

### Resilience

- [x] **RESL-01**: Changes survive plugin cache updates (code residency strategy)
- [x] **RESL-02**: Missing `DISCORD_PROJECT_DIR` env var gracefully falls back to global (no crash)

## v2 Requirements

### Enhanced Scoping

- **ESCL-01**: Default `group add` scope to "local" when `DISCORD_PROJECT_DIR` is set
- **ESCL-02**: `group list` shows groups from both local and global with source labels
- **ESCL-03**: `migrate` command to move groups from global to local config

## Out of Scope

| Feature | Reason |
|---------|--------|
| Merge local + global access.json | Full replacement chosen — merge adds precedence complexity with no isolation benefit |
| Auto-detect project dir from cwd | MCP server cwd is `CLAUDE_PLUGIN_ROOT`, not project dir — unreliable |
| Per-channel-group scope (some local, some global) | Breaks simple "one file wins" mental model |
| Directory tree walk for config | Deterministic env var > implicit directory walking for channel routing |
| GUI/web interface | Developer tool, CLI-only audience |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SERV-01 | Phase 1 | Complete |
| SERV-02 | Phase 1 | Complete |
| SERV-03 | Phase 1 | Complete |
| SERV-04 | Phase 1 | Complete |
| SERV-05 | Phase 1 | Complete |
| SERV-06 | Phase 1 | Complete |
| RESL-01 | Phase 1 | Complete |
| RESL-02 | Phase 1 | Complete |
| SKIL-01 | Phase 2 | Pending |
| SKIL-02 | Phase 2 | Pending |
| SKIL-03 | Phase 2 | Pending |
| SKIL-04 | Phase 2 | Pending |
| SKIL-05 | Phase 2 | Pending |
| SKIL-06 | Phase 2 | Pending |
| SKIL-07 | Phase 2 | Pending |
| UX-01 | Phase 3 | Pending |
| UX-02 | Phase 3 | Pending |

**Coverage:**
- v1 requirements: 17 total
- Mapped to phases: 17
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-23*
*Last updated: 2026-03-23 after roadmap creation*
