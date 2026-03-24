# Claude Code Channels — Project-Local Discord Access

## What This Is

An upgrade to the Claude Code official Discord channel plugin that adds project-local channel scoping. Each Claude Code session only receives Discord messages from channels paired to its specific project directory, eliminating cross-project message routing. Includes a patch delivery mechanism that survives plugin cache updates.

## Core Value

Discord messages reach the correct Claude Code session based on which project directory the session is running in — no cross-talk between projects.

## Requirements

### Validated

- ✓ Server resolves project-local access.json on startup — v1.0 Phase 1
- ✓ Local access.json fully replaces global (full isolation) — v1.0 Phase 1
- ✓ Fallback to global when no local exists — v1.0 Phase 1
- ✓ Changes survive plugin cache updates via patch + SessionStart hook — v1.0 Phase 1
- ✓ `/discord:access group add` prompts local vs global scope — v1.0 Phase 2
- ✓ Local writes to project `.claude/channels/discord/access.json` — v1.0 Phase 2
- ✓ Global writes to `~/.claude/channels/discord/access.json` — v1.0 Phase 2
- ✓ Status shows which file is active with full absolute path — v1.0 Phase 2+3
- ✓ `group rm` searches both files — v1.0 Phase 2
- ✓ `--local`/`--global` flags bypass scope prompt — v1.0 Phase 3
- ✓ Duplicate group warning on status and group add — v1.0 Phase 3

### Active

(None — v1.0 milestone complete)

### Out of Scope

- Merging local + global access.json — full replacement chosen for simplicity
- Changes to DM pairing flow — DMs are user-level, not project-level
- Multi-bot support — single Discord bot shared across projects
- GUI/web interface for channel management

## Context

Shipped v1.0 with 414 LOC across scripts and patches.

**Architecture:**
- `server.ts` modified with `resolveAccessFile()` + `ACTIVE_ACCESS_FILE` constant
- `.mcp.json` injects `DISCORD_PROJECT_DIR` from `${CLAUDE_PROJECT_DIR}`
- `SKILL.md` rewritten with scope resolution, status banner, scope prompt, dual-file group rm, --local/--global flags
- Unified diff patch (`discord-local-scoping.patch`) covers all 3 files
- SessionStart hook (`apply-discord-patch.sh`) auto-applies after cache wipes

## Constraints

- **Plugin cache**: Solved via patch + hook mechanism — changes are resilient to updates
- **No new dependencies**: Pure bash + existing Bun stack
- **Backward compatible**: Sessions without local config work exactly as before
- **Single bot token**: Routing is per-session via access.json scoping

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Local replaces global (no merge) | Simpler mental model, full isolation between projects | ✓ Good |
| Project dir via DISCORD_PROJECT_DIR env var | MCP server cwd is plugin root, not project dir | ✓ Good |
| Patch + SessionStart hook for residency | Plugin cache gets wiped on updates, need resilient delivery | ✓ Good |
| DM pairing writes always go to global | DMs are user-level, not project-level | ✓ Good |
| group rm searches both files | More forgiving than strict isolation | ✓ Good |
| AskUserQuestion for scope prompt | Consistent with Claude Code UX patterns | ✓ Good |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-03-24 after v1.0 milestone*
