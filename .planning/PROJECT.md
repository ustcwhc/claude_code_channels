# Claude Code Channels — Project-Local Discord Access

## What This Is

An upgrade to the Claude Code official Discord channel plugin that adds project-local channel scoping. When multiple Claude Code sessions run in different project directories, each session only receives Discord messages from channels paired to that specific project — eliminating cross-project message routing.

## Core Value

Discord messages reach the correct Claude Code session based on which project directory the session is running in — no cross-talk between projects.

## Requirements

### Validated

- ✓ `server.ts` checks for project-local access.json on startup — Phase 1
- ✓ If local access.json exists, it completely replaces the global one (full isolation) — Phase 1
- ✓ If no local access.json exists, fall back to global access.json (existing behavior) — Phase 1
- ✓ Changes survive plugin cache updates via patch + SessionStart hook — Phase 1

- ✓ `/discord:access group add` prompts user to choose global vs local scope — Phase 2
- ✓ Choosing "local" writes to `./.claude/channels/discord/access.json` in the current project directory — Phase 2
- ✓ Choosing "global" writes to `~/.claude/channels/discord/access.json` (existing behavior) — Phase 2
- ✓ `/discord:access` (no args) shows which file is active (local vs global) and its contents — Phase 2
- ✓ `/discord:access group rm` operates on the correct file based on where the group was defined — Phase 2

### Active

(Remaining items in Phase 3: `--local`/`--global` flags, full resolved path in status, duplicate group warning)

### Out of Scope

- Merging local + global access.json — full replacement chosen for simplicity
- Changes to DM pairing flow — DMs are user-level, not project-level
- Multi-bot support — single Discord bot shared across projects
- GUI/web interface for channel management

## Context

- The Discord plugin is an MCP server at `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/`
- `server.ts` is the MCP server entry point — reads `access.json` to gate inbound/outbound messages
- The `/discord:access` skill is a prompt-driven skill in `skills/access/SKILL.md` — it edits access.json via Claude's file tools
- The MCP server is launched per Claude Code session via `bun run --cwd ${CLAUDE_PLUGIN_ROOT} start`
- The server currently uses `process.env.DISCORD_STATE_DIR` or defaults to `~/.claude/channels/discord/`
- Key challenge: the server's cwd is set to `CLAUDE_PLUGIN_ROOT`, not the project directory — need a way to discover the project dir
- The user runs `claude --channels plugin:discord@claude-plugins-official` to start a session with Discord

## Constraints

- **Plugin cache**: Files in `~/.claude/plugins/cache/` may be overwritten on plugin updates — changes need to be resilient or upstreamed
- **No new dependencies**: Must work with existing Bun + discord.js stack
- **Backward compatible**: Projects without local access.json must work exactly as before
- **Single bot token**: All sessions share one Discord bot — the routing is done server-side by filtering which channels each session listens to

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Local replaces global (no merge) | Simpler mental model, full isolation between projects | — Pending |
| Project dir discovery via env var | MCP server cwd is plugin root, not project dir — need explicit passing | — Pending |

---
*Last updated: 2026-03-23 after initialization*
