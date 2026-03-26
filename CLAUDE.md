<!-- GSD:project-start source:PROJECT.md -->
## Project

**Claude Code Channels — Project-Local Discord Access**

A patch-based extension to the official Claude Code Discord channel plugin that adds project-local channel scoping, session awareness, and a modular install/uninstall system. Each Claude Code session only receives Discord messages from channels paired to its specific project directory.

**Core Value:** Discord messages reach the correct Claude Code session based on which project directory the session is running in — no cross-talk between projects.

### Constraints

- **Plugin cache**: Files in `~/.claude/plugins/cache/` get wiped on plugin updates — all changes must be re-applicable via install script
- **No new dependencies**: Must work with existing Bun + discord.js stack
- **Backward compatible**: Projects without local access.json must work exactly as before
- **Single bot token**: All sessions share one Discord bot — routing is per-session via config scoping
- **Bash scripts**: Install/uninstall are bash scripts, not Claude Code skills
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Context
## Env Var Delivery: The Core Problem
### What's Broken
### Recommended Fix: `env` Block with `${CLAUDE_PROJECT_DIR}`
- `${CLAUDE_PROJECT_DIR}` is expanded by Claude Code *before* spawning the subprocess (same expansion engine as `args`)
- The official MCP integration docs state: "All MCP configurations support environment variable substitution"
- `${CLAUDE_PROJECT_DIR}` in `args` is confirmed working by the official `stdio-server.json` example
- The `env` block uses the same `${VAR}` expansion mechanism as `args`
### What NOT to Use
| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `sh -c` wrapper with `$PWD` | `$PWD` is unreliable -- Claude Code may set cwd before shell launches | `env` block with `${CLAUDE_PROJECT_DIR}` |
| `process.cwd()` in server.ts | Server cwd is always `CLAUDE_PLUGIN_ROOT` (set by `--cwd`) | `process.env.DISCORD_PROJECT_DIR` |
| Reading `CLAUDE_PROJECT_DIR` directly (no rename) | Works but risks namespace collision if Claude Code changes the var | Rename to `DISCORD_PROJECT_DIR` at the boundary |
| Merging local + global access.json | Ambiguous precedence, split-brain state | Full replacement: local overrides global entirely |
## Recommended Stack
### Core Technologies (Unchanged)
| Technology | Version | Purpose | Confidence |
|------------|---------|---------|------------|
| Bun | 1.3.11 (installed) | Runtime + package manager | HIGH -- already in use |
| `@modelcontextprotocol/sdk` | existing | MCP stdio server | HIGH -- standard SDK |
| discord.js | existing | Discord Gateway client | HIGH -- already in use |
| Node.js `fs` (sync) | built-in | Read/write access.json at startup | HIGH -- already used throughout server.ts |
### Plugin Patching Stack
| Technology | Purpose | Why |
|------------|---------|-----|
| Bash (POSIX-compatible) | Install/uninstall scripts | Already established; no justification for Python/Node scripts |
| `bun -e` inline scripts | TypeScript/JSON manipulation in patches | Already used in apply-discord-patch.sh; handles JSON and regex transforms that sed cannot do safely |
| `grep -qF` marker detection | Idempotency checks | Simple, portable, already established pattern |
| Unified diff patches | NOT recommended for this project | Plugin versions change frequently (now 0.0.4, was 0.0.1); line offsets shift and patches fail silently |
### Claude Code Plugin Infrastructure
| Variable/Feature | Available Since | Purpose | Confidence |
|------------------|----------------|---------|------------|
| `${CLAUDE_PLUGIN_ROOT}` | Early versions | Plugin directory path in `.mcp.json` | HIGH -- used everywhere |
| `${CLAUDE_PROJECT_DIR}` | v1.0.58+ | Project directory in `.mcp.json` args | HIGH -- official example exists |
| `${CLAUDE_PROJECT_DIR}` in `env` block | v1.0.58+ (assumed) | Project directory as env var | MEDIUM -- docs say all fields support expansion, but no official `env` example |
| `${CLAUDE_PLUGIN_DATA}` | v2.1.78+ | Persistent plugin data dir (survives updates) | HIGH -- changelog confirmed |
| `$CLAUDE_ENV_FILE` | Early versions | SessionStart hooks can write env vars here | HIGH -- documented in hook-development skill |
| SessionStart hooks | Early versions | Run scripts when Claude Code starts | HIGH -- already used by this project |
## Modular Bash Install/Uninstall Architecture
### Design Principles
### Bash Best Practices for This Project
| Practice | Why | How |
|----------|-----|-----|
| `set -euo pipefail` | Fail fast on any error | Already used in current scripts |
| Marker-based idempotency | Safe to re-run; SessionStart hook calls install on every session | `grep -qF "MARKER" file && return 0` |
| Component exit codes | Orchestrator needs per-component status | 0=applied, 1=error, 2=already-applied, 3=skipped (anchor missing) |
| `sort -V` for version discovery | Find latest plugin version numerically | Already used; handles 0.0.4 > 0.0.10 correctly |
| stderr for status messages | stdout reserved for data/piping | Already established with `>&2` |
| No `cd` in components | Components receive paths as arguments | Prevents cwd confusion when sourcing |
### Install Script Pattern
#!/usr/bin/env bash
# Discover plugin
# Source and run components in order
### Uninstall Script Pattern
### Key Bash Patterns
# In apply:
# In revert: remove everything between markers (inclusive)
## Project-Scoped Config
### Path Convention
- Mirrors global structure
- The `/discord:access` skill already knows this shape
- Keeps discord state under `channels/discord/` regardless of scope
### Resolution Logic
## Plugin Cache Resilience
## Version Compatibility
| Requirement | Min Version | Notes | Confidence |
|-------------|-------------|-------|------------|
| `CLAUDE_PROJECT_DIR` in hooks | v1.0.58+ | Changelog confirmed | HIGH |
| `${CLAUDE_PROJECT_DIR}` in `.mcp.json` args | v1.0.58+ | Official example confirms | HIGH |
| `${CLAUDE_PROJECT_DIR}` in `.mcp.json` env | v1.0.58+ (assumed) | Docs say "all fields"; no specific example | MEDIUM |
| `${CLAUDE_PLUGIN_DATA}` | v2.1.78+ | Changelog confirmed | HIGH |
| Discord plugin version | 0.0.4 | Currently installed; was 0.0.1 at prior research | HIGH (direct inspection) |
## Alternatives Considered
| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Env var delivery | `env` block in `.mcp.json` | `sh -c` wrapper capturing `$PWD` | `$PWD` is unreliable; cwd may already be plugin root |
| Env var delivery (fallback) | SessionStart hook writing to `$CLAUDE_ENV_FILE` | -- | Use if `env` block expansion doesn't work for `CLAUDE_PROJECT_DIR` |
| JSON manipulation | `bun -e` inline | `jq` | `jq` is a new dependency; Bun is already available |
| Patch format | Marker-based `bun -e` transforms | Unified diff (`patch -p1`) | Diffs break across plugin versions; anchors are more resilient |
| Script language | Bash | Python/Node | Bash is already established; scripts are glue code, not application logic |
| Install modularity | Numbered component files | Single monolithic script | Components can be added/removed independently as features grow |
## Sources
- `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.4/.mcp.json` -- Current deployed config showing `sh -c` wrapper approach; direct inspection
- `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.4/server.ts` -- Current server with local-scoping patch already applied; direct inspection
- `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/mcp-integration/SKILL.md` -- Documents env var expansion in "all MCP configurations"; HIGH confidence
- `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/mcp-integration/examples/stdio-server.json` -- Shows `${CLAUDE_PROJECT_DIR}` in args; HIGH confidence
- `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/hook-development/SKILL.md` -- Documents `$CLAUDE_PROJECT_DIR` for hooks, `$CLAUDE_ENV_FILE` for env propagation; HIGH confidence
- `~/.claude/cache/changelog.md` -- v1.0.58: `CLAUDE_PROJECT_DIR` for hooks; v2.1.78: `CLAUDE_PLUGIN_DATA`; HIGH confidence
- `scripts/apply-discord-patch.sh` -- Current patch script establishing patterns (markers, `bun -e`, `sort -V`); direct inspection
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
