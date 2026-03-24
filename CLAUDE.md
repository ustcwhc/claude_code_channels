<!-- GSD:project-start source:PROJECT.md -->
## Project

**Claude Code Channels — Project-Local Discord Access**

An upgrade to the Claude Code official Discord channel plugin that adds project-local channel scoping. When multiple Claude Code sessions run in different project directories, each session only receives Discord messages from channels paired to that specific project — eliminating cross-project message routing.

**Core Value:** Discord messages reach the correct Claude Code session based on which project directory the session is running in — no cross-talk between projects.

### Constraints

- **Plugin cache**: Files in `~/.claude/plugins/cache/` may be overwritten on plugin updates — changes need to be resilient or upstreamed
- **No new dependencies**: Must work with existing Bun + discord.js stack
- **Backward compatible**: Projects without local access.json must work exactly as before
- **Single bot token**: All sessions share one Discord bot — the routing is done server-side by filtering which channels each session listens to
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Context
## Key Finding: How MCP Servers Receive Project Context
## Recommended Stack
### Core Technologies
| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Bun | existing | Runtime + package manager | Already in use; no justification to change |
| `@modelcontextprotocol/sdk` | existing | MCP stdio server | Already in use; standard SDK |
| discord.js | existing | Discord Gateway client | Already in use |
| Node.js `fs` (sync) | built-in | Read/write access.json at startup | Already used throughout server.ts; synchronous is fine at boot |
### Project-Scoped Config Pattern
- Mirrors the global path structure (`~/.claude/channels/discord/access.json`)
- The `/discord:access` skill already knows the path shape — adapting it to check the project-local variant is minimal
- Keeps all discord channel state under `channels/discord/`, whether global or local
### Supporting Libraries
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Node.js `path` | built-in | Construct local access.json path from `DISCORD_PROJECT_DIR` | Always — already imported |
| Node.js `fs.existsSync` | built-in | Check if local access.json exists before reading | At startup to determine active config |
### Development Tools
| Tool | Purpose | Notes |
|------|---------|-------|
| `bun run --cwd ${CLAUDE_PLUGIN_ROOT} start` | Existing launch command | Do not change; the `--cwd` sets the server's working directory to the plugin root, not the project dir — this is why env var injection is necessary |
## Installation
## How to Modify `.mcp.json` to Pass Project Directory
## Server.ts Startup Logic
## Alternatives Considered
| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `env` block in `.mcp.json` | Pass as CLI arg (`--project-dir`) | If the server accepted named CLI args — it doesn't; `bun run start` doesn't forward extra args to server.ts |
| `env` block in `.mcp.json` | Read from process.cwd() | Never — cwd is explicitly set to `CLAUDE_PLUGIN_ROOT` via `--cwd`, not the project directory |
| `env` block in `.mcp.json` | Use `CLAUDE_PROJECT_DIR` directly (no rename) | Works, but `DISCORD_PROJECT_DIR` is clearer and avoids shadowing the Claude-injected var if the name space changes |
| `.claude/channels/discord/access.json` (local) | `.claude/discord.local.json` | Use the `.local.json` path if you want the `plugin-settings` skill convention; costs nothing but changes the mental model |
## What NOT to Use
| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `process.cwd()` to find project dir | The server's cwd is always `CLAUDE_PLUGIN_ROOT` (set by `--cwd` in `.mcp.json`), not the project | `process.env.DISCORD_PROJECT_DIR` |
| Merging local + global access.json | Merging creates ambiguous precedence and split-brain state — if a channel is in global but removed from local, which wins? | Full replacement: local file completely overrides global |
| Hot-reloading the active file selection at runtime | The file selection (local vs global) is a boot-time decision based on whether the local file exists at startup | Decide once at boot; restart required if user creates/removes local file |
| Writing local access.json from the MCP server process | The server knows `DISCORD_PROJECT_DIR` but should not write project files autonomously | The `/discord:access` skill (prompt-driven, user-invoked) writes the file; server only reads it |
| Committing `.claude/channels/discord/access.json` to project git | Contains Discord user IDs and channel IDs — sensitive, project-local | Add to `.gitignore` |
## Skill Layer Changes
## Plugin Cache Resilience
## Version Compatibility
| Requirement | Version | Notes |
|-------------|---------|-------|
| `CLAUDE_PROJECT_DIR` env var | Claude Code v1.0.58+ | Added in changelog entry "Hooks: Added CLAUDE_PROJECT_DIR env var for hook commands"; behavior in MCP env block confirmed by stdlib example |
| `${CLAUDE_PROJECT_DIR}` in `.mcp.json` `env` | Same as above | The `env` block substitution follows the same expansion rules as `args` |
| `${CLAUDE_PLUGIN_DATA}` (alternative) | Claude Code v2.1.78+ | For data that should survive plugin updates — not needed here since state lives in the project dir |
## Sources
- `/Users/haocheng_mini/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/mcp-integration/examples/stdio-server.json` — Confirms `${CLAUDE_PROJECT_DIR}` in args; HIGH confidence (official plugin-dev skill example)
- `/Users/haocheng_mini/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/mcp-integration/SKILL.md` — Documents env var substitution in all `.mcp.json` fields; HIGH confidence (official docs)
- `/Users/haocheng_mini/.claude/cache/changelog.md` line 1989 — v1.0.58 changelog confirms `CLAUDE_PROJECT_DIR` env var for hook commands; HIGH confidence (first-party changelog)
- `/Users/haocheng_mini/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/hook-development/examples/load-context.sh` — Shows `$CLAUDE_PROJECT_DIR` used in hook scripts; HIGH confidence
- `/Users/haocheng_mini/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/plugin-settings/SKILL.md` — Documents `.claude/plugin-name.local.md` pattern; HIGH confidence
- `/Users/haocheng_mini/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/server.ts` — Existing server; confirms `STATE_DIR` and `ACCESS_FILE` pattern; direct inspection
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
