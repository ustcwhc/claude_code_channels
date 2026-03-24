# Phase 1: Server-Side Scoping - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-23
**Phase:** 01-server-side-scoping
**Areas discussed:** Code residency, Env var plumbing, File resolution, Boot logging

---

## Code Residency

| Option | Description | Selected |
|--------|-------------|----------|
| Fork to local dir | Copy plugin to non-cache location, register as local MCP server | |
| Patch script | Keep a patch file, auto-apply after each plugin update | ✓ |
| Upstream PR | Submit changes to claude-plugins-official repo | |

**User's choice:** Patch script
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Manual script | Shell script user runs after plugin updates | |
| Claude Code hook | Auto-apply via hook on plugin update events | ✓ |
| You decide | Claude picks | |

**User's choice:** Claude Code hook
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Copy over | Keep full modified files in repo, copy to cache dir | |
| Git-style diff patch | Keep .patch file, apply with `patch` command | ✓ |
| You decide | Claude picks | |

**User's choice:** Git-style diff patch
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| On session start | Check and apply every time Claude Code starts | ✓ |
| Manual trigger | User runs command when they know plugin updated | |
| You decide | Claude picks | |

**User's choice:** On session start
**Notes:** None

---

## Env Var Plumbing

| Option | Description | Selected |
|--------|-------------|----------|
| .mcp.json env block | Add env: {"DISCORD_PROJECT_DIR": "${CLAUDE_PROJECT_DIR}"} | ✓ |
| Wrapper script | Shell script sets env then launches bun | |
| You decide | Claude picks | |

**User's choice:** .mcp.json env block
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Silent fallback to global | Server uses global, logs a note | |
| Warning + fallback | Visible warning, then fall back to global | ✓ |
| You decide | Claude picks | |

**User's choice:** Warning + fallback
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| DISCORD_PROJECT_DIR | Plugin-specific name, clear purpose | ✓ |
| CLAUDE_PROJECT_DIR direct | Read directly, no mapping | |
| You decide | Claude picks | |

**User's choice:** DISCORD_PROJECT_DIR
**Notes:** None

---

## File Resolution

| Option | Description | Selected |
|--------|-------------|----------|
| Fall back to global | Only use local when file exists | ✓ |
| Create empty local | Auto-create default local on first run | |
| You decide | Claude picks | |

**User's choice:** Fall back to global
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Rename + fall back | Move corrupt aside, fall back to global | |
| Error and stop | Log error, refuse to start | ✓ |
| You decide | Claude picks | |

**User's choice:** Error and stop
**Notes:** Different from global behavior (which renames aside). User wants corrupt local to be a hard error.

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, resolved file | All writes go to resolved file | |
| Global only for DM ops | DM writes go to global, channel writes to resolved | ✓ |
| You decide | Claude picks | |

**User's choice:** Global only for DM ops
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| DMs via global always | DM gating reads global allowFrom | |
| Full isolation | Only channels in local file, DMs blocked unless local has allowFrom | ✓ |
| You decide | Claude picks | |

**User's choice:** Full isolation
**Notes:** When local is active, it's the only source of truth for message gating.

| Option | Description | Selected |
|--------|-------------|----------|
| Pairing reads global | Pairing/pending check always reads global | |
| Disable pairing in local mode | Pairing disabled, user must pair via global session | |
| You decide | Claude picks least surprising | ✓ |

**User's choice:** You decide (Claude's discretion)
**Notes:** None

---

## Boot Logging

| Option | Description | Selected |
|--------|-------------|----------|
| One-liner | "discord channel: using local config /path/..." | ✓ |
| Detailed | Full resolution chain logged | |
| You decide | Claude picks | |

**User's choice:** One-liner
**Notes:** None

## Claude's Discretion

- Pairing behavior when local config is active
- Exact patch application detection mechanism
- Whether resolveAccessFile() caches at boot or re-resolves per call
- Exact error message for corrupt local file

## Deferred Ideas

- None — discussion stayed within phase scope
