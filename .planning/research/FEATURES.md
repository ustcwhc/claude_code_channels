# Feature Landscape

**Domain:** Patch-based Discord plugin extension for Claude Code (Milestone 2)
**Researched:** 2026-03-25
**Confidence:** HIGH (all 5 features are well-scoped; codebase inspected directly)

## Table Stakes

Features the extension must have or it does not function as advertised.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Install/uninstall scripts | Without automated install, users must manually patch plugin files after every plugin update. This is the delivery mechanism for everything else. | MEDIUM | Currently `apply-discord-patch.sh` exists but is apply-only (no uninstall). Must become modular to support growing feature set. |
| Fix DISCORD_PROJECT_DIR propagation | The entire project-local scoping feature is broken without this. Sessions silently fall back to global config, defeating the core value proposition. | LOW-MEDIUM | The `sh -c` wrapper in .mcp.json exists but $PWD may not resolve to the project directory at MCP server spawn time. Need to verify the actual value reaching the process. |

## Differentiators

Features that add real value but are not strictly required for basic functionality.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Session greeting to Discord | Confirms to the human on Discord that a Claude Code session is alive and listening. Without this, you send a message and wonder if anyone is home. Reduces "is this thing on?" friction. | LOW | Send a message to configured channel(s) when the MCP server starts and confirms channel access. |
| Channel ID display in session | The user in the CLI needs to know which Discord channel they are connected to. Currently you configure it and hope. Display removes guesswork. | LOW | Print channel ID (and optionally channel name) to stderr or as a tool response during session startup. |
| Strip rich media support | The existing attachment/image handling in the plugin is generic and untested for this extension's use case. Stripping it creates a clean baseline for controlled re-implementation later. | MEDIUM | Must identify all attachment-related code paths (download_attachment tool, file upload in reply, attachment metadata in notifications) and either remove or neutralize them. |

## Anti-Features

Things to deliberately NOT build in this milestone.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Re-implement rich media after stripping | Scope creep. The strip is to establish a clean baseline. Re-adding media support requires proper testing, file size handling, and content-type validation. | Strip now, re-implement in a future milestone with dedicated testing. |
| Merge local + global access.json | Creates ambiguous precedence. Key decision from v1.0 was full replacement. | Keep full replacement -- local file completely overrides global. |
| GUI for channel management | The `/discord:access` skill handles all config. A GUI adds a second source of truth. | Stick with CLI skill-based management. |
| Auto-detection of project directory changes | Hot-reloading config when the user creates/removes local access.json mid-session. | Decide scope at boot. Restart required for config file changes. |
| Multi-bot support | All sessions share one bot. Routing is per-session via config, not per-bot. | Keep single bot architecture. |
| Greeting customization (templates, rich embeds) | Over-engineering. A plain text message ("Claude Code session started for project X") is sufficient. | Simple hardcoded message format. Allow disable via config if needed. |
| Uninstall that removes project-local config files | The uninstall script should only undo plugin cache patches, not touch user's project config (.claude/channels/discord/access.json). | Uninstall reverses plugin patches only. User config is theirs to manage. |

---

## Detailed Feature Specifications

### Feature 1: Install/Uninstall Scripts

**Priority:** Table stakes -- this is the delivery framework for all other features.

**Expected behavior:**
- `install.sh`: Applies all patches to the latest Discord plugin version in `~/.claude/plugins/cache/claude-plugins-official/discord/<version>/`. Idempotent -- safe to run repeatedly. Should be callable from a SessionStart hook.
- `uninstall.sh`: Reverses all patches, restoring the plugin to its original state. Also idempotent.
- Modular structure: Each feature's patch logic should be a discrete section/function so new features can be added without restructuring the script.
- Per-component status reporting: Print which components were patched/skipped/already-applied so the user knows what happened.

**Edge cases:**
- Plugin not installed (no `~/.claude/plugins/cache/claude-plugins-official/discord/` directory) -- exit gracefully with informational message.
- Plugin updated to a new version mid-session -- patches are against the latest version directory. The script must find the correct version. Consider: version sort (`sort -V`) to pick latest.
- Anchor strings not found in new plugin version -- the `bun -e` inline scripts use string matching (e.g., `const ENV_FILE = join(STATE_DIR, '.env')`). If the upstream plugin changes these lines, the patch silently fails. Must detect and report this.
- Uninstall when patches were never applied -- should succeed silently (idempotent).
- Partial patch state (some components patched, others not) -- both install and uninstall must handle this gracefully.

**Complexity:** MEDIUM. The current `apply-discord-patch.sh` is a reasonable starting point but needs: (1) uninstall counterpart, (2) modular structure for new features, (3) better error reporting when anchors are missing.

---

### Feature 2: Fix DISCORD_PROJECT_DIR Propagation

**Priority:** Table stakes -- without this, local scoping is non-functional.

**Expected behavior:**
- When Claude Code starts a session in `/path/to/project`, the MCP server for Discord receives `DISCORD_PROJECT_DIR=/path/to/project` as an environment variable.
- The server uses this to check for `<project>/.claude/channels/discord/access.json` and, if present, uses it instead of the global config.

**Current state (broken):**
- The `.mcp.json` uses `sh -c "DISCORD_PROJECT_DIR=$PWD exec bun run --cwd '${CLAUDE_PLUGIN_ROOT}' ..."`.
- The problem: `$PWD` is a shell variable that expands at `sh -c` execution time. But Claude Code may set the working directory to the plugin root (via `--cwd`) BEFORE the `sh` subprocess inherits its `$PWD`. OR Claude Code might spawn the MCP server from a different directory than the project root.
- Alternative approach from the patch file: `.mcp.json` `env` block with `"DISCORD_PROJECT_DIR": "${PWD}"` -- but `${PWD}` substitution in the env block depends on Claude Code performing env var expansion, which may not happen for `PWD` (only `CLAUDE_*` vars may be expanded).

**Edge cases:**
- Project directory with spaces in the path -- must be properly quoted in the `sh -c` command.
- `$PWD` not set or set to unexpected value -- fallback to global config (existing behavior, but should log a warning).
- Symlinked project directories -- `$PWD` might not match the canonical path. The `resolveAccessFile()` function currently does a simple `join()` without resolving symlinks.
- Claude Code launched from a subdirectory of the project -- `$PWD` would be the subdirectory, not the project root. The local access.json is at the project root's `.claude/` directory.

**Investigation needed:** The actual mechanism by which Claude Code spawns MCP servers. Does it set CWD to the project directory before exec? Does it expand `${CLAUDE_PROJECT_DIR}` in the env block? The `sh -c` wrapper captures `$PWD` but if Claude Code doesn't chdir to the project before spawning, this captures the wrong directory.

**Complexity:** LOW-MEDIUM. The fix is likely small (possibly just using `${CLAUDE_PROJECT_DIR}` in the env block instead of relying on `$PWD`), but diagnosing the exact failure mode requires runtime testing.

---

### Feature 3: Session Greeting to Discord

**Priority:** Differentiator -- nice to have, reduces "is this thing on?" friction.

**Expected behavior:**
- When the MCP server starts and successfully connects to Discord (bot is online), send a message to each configured channel announcing the session.
- Message content: Simple text like "Claude Code session connected (project: my-project-name)" or similar. Include the project name (derived from the project directory basename) if `DISCORD_PROJECT_DIR` is set.
- Only send greeting to channels the session is authorized to use (from the active access.json's `groups`).
- If no channels are configured, skip the greeting (don't crash, don't warn excessively).

**Edge cases:**
- Bot not yet connected when greeting fires -- must wait for Discord.js `ready` event before sending.
- Channel ID in config but bot doesn't have access to that channel -- catch the send error, log to stderr, continue. Do not crash the entire server.
- Multiple channels configured -- send greeting to all of them.
- Session restarts rapidly (e.g., during development) -- rapid greetings could be annoying. Consider: no rate limiting in v1, but design the message to be unobtrusive.
- Greeting should only fire once at startup, not on reconnections (Discord.js can reconnect the WebSocket without restarting the process).
- DISCORD_PROJECT_DIR not set -- greeting should still work, just without project name. "Claude Code session connected" is fine.

**Complexity:** LOW. The Discord.js client is already initialized; sending a message to a channel by ID is a single API call. The only subtlety is timing (wait for `ready` event) and error handling.

---

### Feature 4: Channel ID Display in Session

**Priority:** Differentiator -- removes guesswork about which channel the session is connected to.

**Expected behavior:**
- After the MCP server starts and resolves which access.json to use, display the connected channel ID(s) to the Claude Code session.
- This could be: (a) stderr output visible in Claude Code's MCP server logs, or (b) a notification-style message surfaced through the MCP protocol, or (c) part of the greeting message logic.
- Show: channel ID, and if possible, the channel name (requires a Discord API call to resolve).

**Edge cases:**
- No channels configured (empty `groups` object) -- display "No channels configured. Use /discord:access group add <channelId> to add one."
- Channel ID exists in config but bot can't access the channel -- display the ID but note it may be inaccessible.
- Multiple channels -- list all of them.
- The display mechanism matters: stderr is only visible if the user checks MCP server logs. A tool response or notification is more visible but requires the right MCP lifecycle hook.

**Implementation options:**
1. **Stderr at startup** -- simplest, but least visible to the user. Already used for "using local/global config" messages.
2. **Part of the greeting feature** -- the greeting already announces to Discord; this announces to the CLI. Natural pairing.
3. **MCP server info/status tool** -- a `discord_status` tool the user can call to see connection state. More discoverable but requires adding a new tool to the MCP server.

**Recommendation:** Option 1 (stderr) as the baseline, since it requires zero protocol changes. Option 3 as a stretch goal if the install script framework makes adding new tools easy.

**Complexity:** LOW. Reading channel IDs from the parsed access.json and printing to stderr is trivial. Resolving channel names via Discord API adds a small amount of async complexity.

---

### Feature 5: Strip Rich Media Support

**Priority:** Differentiator -- creates a clean baseline for future re-implementation.

**Expected behavior:**
- Remove or disable the `download_attachment` tool from the MCP server.
- Remove file attachment support from the `reply` tool (the `files` parameter).
- Remove attachment metadata from incoming message notifications (the `attachment_count` and `attachments` attributes on the channel XML tag).
- The plugin should still handle messages that contain attachments -- it just ignores them. No crashes on messages with images/files.

**Current attachment code in server.ts (v0.0.4):**
- `MAX_ATTACHMENT_BYTES` constant (line 160)
- `downloadAttachment()` function (line 443-459) -- downloads an attachment to local inbox
- `safeAttName()` function (line 461) -- generates safe filenames for attachments
- `download_attachment` tool definition (line 596) and handler (line 717-730)
- `reply` tool's `files` parameter (line 563) and file upload logic (line 640-646)
- Attachment listing in message notifications (lines 883-906)
- Server instructions mentioning attachments (line 483, 485)

**Edge cases:**
- Messages with only attachments and no text content -- currently rendered as `(attachment)`. After stripping, these should either be silently dropped or rendered as "(message contained attachments only -- media not supported)".
- The `download_attachment` tool must be completely removed from the tool list, not just made non-functional. Leaving a broken tool confuses the LLM.
- Server instructions (the MCP server description) reference attachments -- these strings must be updated to not mention attachment capabilities.
- File upload in `reply` -- if the `files` parameter is removed, ensure the LLM doesn't try to use it (update the tool description).

**Complexity:** MEDIUM. There are 6+ code locations to modify. The patch must be thorough -- leaving a partial attachment code path creates confusing errors. The install script needs a dedicated section for this feature.

---

## Feature Dependencies

```
install.sh (Feature 1)
  |
  +-- All other features depend on install.sh as the delivery mechanism
  |
  +-- Fix DISCORD_PROJECT_DIR (Feature 2) -- must be applied first
  |     |
  |     +-- Session greeting (Feature 3) -- uses PROJECT_DIR for project name
  |     |
  |     +-- Channel ID display (Feature 4) -- uses active config (local vs global)
  |
  +-- Strip rich media (Feature 5) -- independent of scoping, depends only on install.sh
```

**Critical path:** Feature 1 (install) -> Feature 2 (env var fix) -> Features 3+4 (greeting + display). Feature 5 is parallel to 2-4.

## MVP Recommendation

**Must ship (table stakes):**
1. Install/uninstall scripts (Feature 1) -- everything else needs this
2. Fix DISCORD_PROJECT_DIR (Feature 2) -- the core value prop is broken without it

**Should ship (high-value differentiators):**
3. Session greeting (Feature 3) -- low complexity, high user-facing impact
4. Channel ID display (Feature 4) -- low complexity, complements greeting

**Can ship independently:**
5. Strip rich media (Feature 5) -- useful cleanup but not blocking other features

**Recommended phase ordering:**
- Phase 1: Install/uninstall framework + DISCORD_PROJECT_DIR fix (table stakes)
- Phase 2: Session greeting + channel ID display (natural pairing, both low complexity)
- Phase 3: Strip rich media (isolated, medium complexity)

## Sources

- Direct inspection of `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.4/server.ts` (921 lines)
- Direct inspection of `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.4/.mcp.json`
- Direct inspection of `scripts/apply-discord-patch.sh` (current install script)
- Direct inspection of `patches/SKILL.md` (patched access skill)
- `.planning/PROJECT.md` (requirements, constraints, key decisions)
