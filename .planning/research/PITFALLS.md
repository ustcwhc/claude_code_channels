# Domain Pitfalls

**Domain:** MCP server plugin patching -- project-local config scoping (Discord)
**Researched:** 2026-03-25
**Confidence:** HIGH -- based on direct inspection of broken patch, official MCP docs, and plugin-dev skill examples

---

## Critical Pitfalls

### Pitfall 1: `$PWD` in `sh -c` Wrapper Does Not Capture the Project Directory

**What goes wrong:**
The v1.1 patch replaced the original `.mcp.json` command with an `sh -c` wrapper:
```json
"command": "sh",
"args": ["-c", "DISCORD_PROJECT_DIR=$PWD exec bun run --cwd '${CLAUDE_PLUGIN_ROOT}' --shell=bun --silent start"]
```
The intent: `sh` inherits the project directory as its cwd, so `$PWD` captures it before `--cwd` changes it for the bun process. The reality: **Claude Code does not necessarily spawn MCP server processes with the project directory as cwd.** The cwd of the spawned process is controlled by Claude Code's process manager, not by the user's terminal. If Claude Code sets cwd to the plugin root (or any other directory) before invoking the command, `$PWD` resolves to that directory, not the project.

**Why it happens:**
Confusion between two variable expansion mechanisms:
1. **Claude Code template expansion** -- `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PROJECT_DIR}`, and user env vars like `${MY_API_KEY}` are expanded by Claude Code's own substitution engine *before* spawning the process. These use `${...}` syntax in `.mcp.json` fields.
2. **Shell expansion** -- `$PWD` is expanded by `sh` at runtime, using whatever working directory the process was spawned with.

The official stdio-server.json example passes `${CLAUDE_PROJECT_DIR}` in `args` -- this is Claude Code template expansion, not shell expansion. It works because Claude Code knows the project directory and substitutes it at config parse time.

**Evidence:**
- The official example (`plugins/plugin-dev/skills/mcp-integration/examples/stdio-server.json`) uses `"${CLAUDE_PROJECT_DIR}"` in args -- never `$PWD`.
- The MCP integration SKILL.md documents "environment variable substitution" as a feature of `.mcp.json` config parsing, listing `${CLAUDE_PLUGIN_ROOT}` and user env vars.
- The original reference patch (`patches/discord-local-scoping.patch`) used the `env` block approach: `"DISCORD_PROJECT_DIR": "${PWD}"` -- this relies on Claude Code expanding `${PWD}` from the user's environment, which may or may not work depending on whether Claude Code's substitution engine looks up arbitrary env vars or only its own magic vars.
- The `sh -c` wrapper was introduced in `apply-discord-patch.sh` as an alternative to the `env` block approach, but both approaches have the same underlying uncertainty about what `PWD` resolves to.

**Prevention:**
Use `${CLAUDE_PROJECT_DIR}` (Claude Code's own magic variable) in the `.mcp.json` `env` block instead of `$PWD`:
```json
{
  "mcpServers": {
    "discord": {
      "command": "bun",
      "args": ["run", "--cwd", "${CLAUDE_PLUGIN_ROOT}", "--shell=bun", "--silent", "start"],
      "env": {
        "DISCORD_PROJECT_DIR": "${CLAUDE_PROJECT_DIR}"
      }
    }
  }
}
```
This uses Claude Code's template expansion (proven to work in the official example) and keeps the original command structure (no `sh -c` wrapper).

**Warning signs:**
- `DISCORD_PROJECT_DIR` is empty or contains the plugin cache path at server boot
- Server always reports "using global config" even when local access.json exists
- The `sh -c` wrapper introduces a layer of indirection that makes debugging harder (which shell? which env?)

**Detection test:** Add `process.stderr.write('DISCORD_PROJECT_DIR=' + process.env.DISCORD_PROJECT_DIR)` at boot and verify it shows the actual project path, not the plugin root or empty string.

**Phase to address:** Phase 1 -- this is THE root cause of the v1.1 failure.

---

### Pitfall 2: Plugin Cache Version Drift Breaks Hardcoded Paths and Regex Anchors

**What goes wrong:**
The apply script discovers the latest version via `ls | sort -V | tail -1`. Between v1.0 (version `0.0.1`) and now (version `0.0.4`), the plugin version changed. Every regex anchor in the bun -e patching script (e.g., `const ENV_FILE = join(STATE_DIR, '.env')`, `import { join, sep } from 'path'`) depends on the exact source text of the upstream plugin. If the upstream plugin changes even whitespace, the regex fails silently (the anchor check prints a warning to stderr but continues), and partial patches get applied.

**Why it happens:**
The patching strategy uses string matching against the upstream source. Any upstream change -- new imports, reformatted constants, added lines between anchors -- breaks the match. The script correctly checks for an anchor before inserting, but:
- If the anchor is missing, the server.ts patch is skipped silently (just a stderr message)
- The `.mcp.json` patch may still apply, creating a mismatch: the env var is injected but the server code that reads it is absent

**Prevention:**
1. **Check patch coherence:** After all patches are applied, verify that BOTH the server.ts marker AND the `.mcp.json` marker exist. If only one was applied, error out and tell the user.
2. **Pin expected version:** Store the expected plugin version in the script. If the discovered version differs from expected, warn loudly and require explicit `--force` to proceed.
3. **Test anchors before patching:** Before running the bun -e script, grep for all required anchors. If any are missing, fail early with a clear message about which anchor is gone.

**Warning signs:**
- Patch reports "server.ts patched" but the key functions are missing from the file
- `.mcp.json` is patched (has `DISCORD_PROJECT_DIR`) but `server.ts` has no `resolveAccessFile`
- New plugin version appears in cache but install script still reports "already applied" because it only checks one marker

**Detection test:** After patching, grep the patched `server.ts` for `resolveAccessFile` AND `ACTIVE_ACCESS_FILE` -- both must be present if the marker is present.

**Phase to address:** Phase 1 (install script hardening).

---

### Pitfall 3: `sh -c` Wrapper Breaks Plugin's Own Shell Assumptions

**What goes wrong:**
The original `.mcp.json` uses `"command": "bun"` with direct args. Changing this to `"command": "sh"` with an `-c` wrapper alters the process tree: `sh` becomes the parent, `bun` is exec'd. This can break:
- Signal handling (SIGTERM goes to sh, not bun, unless `exec` is used -- the current script does use `exec`, but if someone removes it, bun becomes a child and signals break)
- Environment inheritance (sh may not pass through all env vars that Claude Code sets on the process)
- The `env` block in `.mcp.json` is applied to the command process -- with `sh` as the command, env vars are set on `sh`, which `exec bun` inherits. But if Claude Code applies env vars *and* substitutes `${...}` patterns in args before spawning, the `$PWD` in the args string will be treated as a literal `$PWD` (not expanded) if Claude Code's substitution engine doesn't recognize it.

**Why it happens:**
The `sh -c` wrapper was a creative workaround to capture `$PWD` at runtime. But it introduces a layer of shell indirection that interacts unpredictably with Claude Code's process management.

**Prevention:**
Don't use `sh -c` wrappers. Use the `.mcp.json` `env` block with Claude Code's own template variables:
```json
"env": { "DISCORD_PROJECT_DIR": "${CLAUDE_PROJECT_DIR}" }
```
Keep `"command": "bun"` and `"args"` as the upstream defines them. The only change to `.mcp.json` should be adding the `env` block.

**Warning signs:**
- MCP server process doesn't respond to `/mcp` status checks
- Server takes longer to start (extra process spawn)
- Debug logs show `sh` as the process name instead of `bun`

**Phase to address:** Phase 1 -- simplify the `.mcp.json` patch.

---

### Pitfall 4: Patch Script Idempotency Fails When Partially Applied

**What goes wrong:**
The current script checks three independent markers (`MARKER` for server.ts, `MCP_MARKER` for .mcp.json, `SKILL_MARKER` for SKILL.md) and short-circuits if ALL THREE are present. But if only one or two are present (partial application from a previous failed run or version change), the script tries to apply only the missing patches. This can create inconsistent states:
- `.mcp.json` patched (env var injection) but `server.ts` not patched (no code to read it) -- env var is set but ignored
- `server.ts` patched but `.mcp.json` not patched -- code expects env var that's never set
- SKILL.md patched but nothing else -- user sees scope resolution instructions but the mechanism doesn't work

**Why it happens:**
Each patch is checked and applied independently. The "all or nothing" check only gates the fast-path skip. There's no validation that the resulting state is coherent after partial application.

**Prevention:**
1. Add a post-patch coherence check: after all three patch blocks run, verify that all three markers are present. If not, error with a clear message.
2. Consider a "force re-apply" mode that strips existing patches first (remove markers and injected code) then re-applies from scratch.
3. Track patch version: instead of just a boolean marker, use a versioned marker (e.g., `// discord-local-scoping patch v2`) so the script knows when to re-apply after changes.

**Warning signs:**
- Script reports "patch already applied" but features don't work
- One component (e.g., server.ts) has the marker but the code around it is from a different version
- Running the script multiple times produces different results

**Phase to address:** Phase 1 (install script robustness).

---

### Pitfall 5: `bun -e` Patching Script Has Fragile Quoting and Escaping

**What goes wrong:**
The apply script embeds a multi-line JavaScript string inside a bash heredoc-like construct (`bun -e "..."`). The JavaScript itself contains template literals, regex patterns, and escaped characters. This creates multiple layers of escaping:
1. Bash expands `$` variables inside double quotes (e.g., `$SERVER_TS` is intentionally expanded, but `$PWD` in the injected code must be literal)
2. JavaScript template literal backticks inside bash double quotes
3. Escaped newlines (`\\n` vs `\n`) behave differently depending on whether bash or JavaScript processes them first

Current code has `\\\\n` in some places (double-escaped for bash + JS), which produces literal `\\n` in the output instead of actual newlines. This is visible in the patched server.ts where error messages contain literal backslash-n instead of newlines.

**Why it happens:**
Nested quoting contexts (bash > bun -e > JavaScript template literal > regex) make it nearly impossible to reason about escaping correctly. Every layer interprets escape sequences differently.

**Prevention:**
1. **Move the patching logic to a standalone JS/TS file** instead of inlining it in bash. The apply script calls `bun run scripts/patch-server.ts "$SERVER_TS"` instead of `bun -e "..."`. This eliminates the bash-JS quoting interaction entirely.
2. If inline is required, use a heredoc with single-quoted delimiter (`bun -e "$(cat <<'PATCH_EOF' ... PATCH_EOF)"`) to prevent bash expansion inside the script body.

**Warning signs:**
- Patched code contains literal `\\n` instead of newline characters
- Regex replacements silently don't match because escape sequences differ
- `$PWD` in the injected JavaScript is expanded by bash to the script runner's directory instead of being preserved as a literal

**Phase to address:** Phase 1 (install script rewrite).

---

### Pitfall 6: `${PWD}` vs `${CLAUDE_PROJECT_DIR}` in `.mcp.json` env Block

**What goes wrong:**
The original reference patch (`patches/discord-local-scoping.patch`) used:
```json
"env": {
  "DISCORD_PROJECT_DIR": "${PWD}"
}
```
This relies on Claude Code's template substitution expanding `${PWD}`. But the official MCP integration docs only document two categories of variables for expansion:
1. **Magic variables:** `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_DATA}`
2. **User env vars:** `${MY_API_KEY}` etc. -- expanded from the user's shell environment

`PWD` falls into category 2 -- it would be expanded from the user's shell environment. But the question is: which shell environment? Claude Code may not inherit the terminal's `PWD` if it was launched via an app launcher, IDE integration, or background process. And `PWD` may not be the project directory even if it is set -- the user might have `cd`'d somewhere else before launching.

`CLAUDE_PROJECT_DIR` is category 1 -- a magic variable that Claude Code explicitly sets to the project root regardless of how it was launched. This is always correct.

**Prevention:**
Always use `${CLAUDE_PROJECT_DIR}` in `.mcp.json` env blocks for the project directory. Never use `${PWD}`, `${HOME}/...`, or any shell-specific path variable.

**Phase to address:** Phase 1 -- the `.mcp.json` patch must use the correct variable.

---

### Pitfall 7: Plugin Cache Wipe on Update Requires Re-Patching

**What goes wrong:**
Files in `~/.claude/plugins/cache/` are overwritten when the plugin updates. Both `server.ts` and `.mcp.json` changes are lost. The previous milestone relied on a SessionStart hook to re-apply patches, but that hook was part of the reverted v1.1 changes.

**Why it happens:**
The plugin cache is designed as a disposable artifact -- Claude Code manages it, and plugins are expected to be self-contained. Patching cached files is inherently fragile because the cache is not a stable surface.

**Prevention:**
1. **Install script must be re-runnable:** The user (or a hook) must be able to run the install script after any plugin update. The script must handle version changes gracefully.
2. **SessionStart hook for auto-repair:** Register a hook that runs the install script on every session start. This ensures patches are always fresh. But the hook itself lives outside the cache (in the project or user's `.claude/` config), so it survives cache wipes.
3. **Detect unpatched state:** The server.ts code should log clearly when `DISCORD_PROJECT_DIR` is not set, making it obvious when patches need to be re-applied rather than silently falling back.

**Warning signs:**
- Features stop working after a Claude Code update with no code changes in the project
- Plugin version number in cache changes (e.g., `0.0.1` -> `0.0.4`)
- `server.ts` modification timestamp matches plugin release date, not last patch date

**Phase to address:** Phase 1 (install script) and Phase 2 (hook registration).

---

## Moderate Pitfalls

### Pitfall 8: `delete discord.env` in Apply Script Removes Upstream env Block

**What goes wrong:**
Line 141 of `apply-discord-patch.sh`:
```javascript
delete discord.env;
```
This removes the entire `env` block from the discord MCP server config. If a future plugin version adds env vars (e.g., for feature flags or debugging), the patch will strip them. This is unnecessary with the `${CLAUDE_PROJECT_DIR}` approach, which only adds to the env block rather than replacing the command structure.

**Prevention:**
Use additive patching: add `DISCORD_PROJECT_DIR` to the existing `env` block (creating it if absent) rather than restructuring the command/args and deleting env:
```javascript
discord.env = discord.env || {};
discord.env.DISCORD_PROJECT_DIR = '${CLAUDE_PROJECT_DIR}';
```

**Phase to address:** Phase 1 (install script rewrite).

---

### Pitfall 9: Skill-Server Config File Desync

**What goes wrong:**
The `/discord:access` skill edits access.json based on `printenv DISCORD_PROJECT_DIR`. But `DISCORD_PROJECT_DIR` is an env var set on the MCP server process, not on hook/skill processes. The skill runs in a different process context (Claude's tool execution environment), and `printenv` in that context may not show the same env vars as the MCP server.

**Prevention:**
The skill should use `${CLAUDE_PROJECT_DIR}` (available in the Claude Code session environment) to discover the project directory, not `DISCORD_PROJECT_DIR` (which is a server-specific env var). This means the SKILL.md patch should reference `CLAUDE_PROJECT_DIR` in its scope resolution logic.

**Warning signs:**
- `printenv DISCORD_PROJECT_DIR` returns empty in skill context
- Skill writes to global access.json while server reads local
- `group add --local` creates the file but server doesn't see it

**Phase to address:** Phase 2 (skill update).

---

### Pitfall 10: Bash `sort -V` Unavailability

**What goes wrong:**
The version discovery uses `ls -1 "$PLUGIN_BASE" | sort -V | tail -1`. The `-V` (version sort) flag is a GNU coreutils extension. On macOS (which this project runs on), `sort -V` is available in modern versions but was not always present. If the user has an older `sort` or uses a minimal shell, version sorting falls back to lexicographic, which sorts `0.0.4` before `0.0.10` incorrectly.

**Prevention:**
For the current plugin (versions like `0.0.1`, `0.0.4`), lexicographic sort happens to work. But for robustness, use `ls -1t` (sort by modification time, newest first) with `head -1` instead. Or explicitly handle the case where only one version directory exists (which is the common case).

**Phase to address:** Phase 1 (minor hardening).

---

## Minor Pitfalls

### Pitfall 11: `.mcp.json` Format Assumption

**What goes wrong:**
The patching script assumes `.mcp.json` has a specific structure: `{ mcpServers: { discord: { command, args, env } } }`. If the upstream format changes (e.g., top-level keys without `mcpServers` wrapper, or renamed server key), the patch silently produces broken JSON.

**Prevention:**
Add defensive checks: verify `mcp.mcpServers?.discord` exists before modifying. Error clearly if the structure is unexpected.

**Phase to address:** Phase 1.

---

### Pitfall 12: No Rollback Mechanism

**What goes wrong:**
If the install script breaks the plugin, there's no undo. The user must wait for a plugin cache refresh or manually restore the original files.

**Prevention:**
Back up original files before patching (e.g., `server.ts.orig`, `.mcp.json.orig`). Provide an uninstall script that restores from backups. The current repo has uninstall logic, but it was reverted with v1.1.

**Phase to address:** Phase 1 (include with install script).

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| .mcp.json patching | Using $PWD or sh -c instead of ${CLAUDE_PROJECT_DIR} env block | Use official template variable; test by checking process.env at boot |
| server.ts patching | Regex anchors broken by upstream version change | Pin expected version; fail loudly on anchor miss; verify coherence post-patch |
| Install script | Partial application leaves incoherent state | Post-patch coherence check; versioned markers |
| Install script | Nested bash/JS quoting causes silent escaping bugs | Move patch logic to standalone .ts file |
| SKILL.md patching | Skill uses DISCORD_PROJECT_DIR which only exists in server process | Skill should use CLAUDE_PROJECT_DIR instead |
| SessionStart hook | Hook itself in plugin cache gets wiped | Hook config lives in project .claude/ settings, not in cache |
| Plugin version change | 0.0.1 -> 0.0.4 already happened; anchors may have shifted | Inspect current version's server.ts before writing patch logic |
| Backward compatibility | Projects without local access.json break | Env var and local file both optional; graceful fallback to global |

---

## Post-Mortem: Why v1.1 Failed

**Root cause (most likely):** The `sh -c` wrapper with `$PWD` does not capture the project directory because Claude Code spawns MCP server processes with a working directory that is not the project root. The `$PWD` shell variable reflects whatever cwd the process was given, which is likely the plugin root or Claude Code's own working directory.

**Contributing factors:**
1. The approach was never tested end-to-end with a real MCP server launch -- the `$PWD` assumption was plausible but unverified.
2. The official mechanism (`${CLAUDE_PROJECT_DIR}` in `.mcp.json` env/args) was documented but overlooked in favor of the `sh -c` workaround.
3. No boot-time diagnostic logged the actual value of `DISCORD_PROJECT_DIR`, making the failure invisible -- the server just silently fell back to global config.
4. The v1.1 release bundled multiple features (greeting, install/uninstall) with the broken core mechanism, so the revert had to roll back everything.

**Key lesson:** When Claude Code provides a first-party mechanism (template variable expansion in `.mcp.json`), use it. Shell-level workarounds add indirection that is hard to test and interacts unpredictably with the host's process management.

---

## Sources

- Direct inspection: `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.4/.mcp.json` -- shows current patched state with `sh -c` wrapper (the broken approach)
- Direct inspection: `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.4/server.ts` -- confirms server.ts patches are applied but env var is not reaching the process
- Direct inspection: `scripts/apply-discord-patch.sh` -- the broken install script
- Direct inspection: `patches/discord-local-scoping.patch` -- the original reference patch using `"${PWD}"` in env block
- Official: `plugins/plugin-dev/skills/mcp-integration/examples/stdio-server.json` -- shows `${CLAUDE_PROJECT_DIR}` as the correct way to pass project dir in MCP config; HIGH confidence
- Official: `plugins/plugin-dev/skills/mcp-integration/SKILL.md` -- documents env var substitution in `.mcp.json`; HIGH confidence
- Official: `plugins/plugin-dev/skills/hook-development/SKILL.md` line 326 -- confirms `$CLAUDE_PROJECT_DIR` is available in hook context; HIGH confidence
- Changelog: `~/.claude/cache/changelog.md` line 2111 -- v1.0.58 added `CLAUDE_PROJECT_DIR` for hooks; HIGH confidence
- Git history: `46a7b6d` revert commit -- confirms v1.1 was rolled back completely

---

*Pitfalls research for: MCP plugin project-local config scoping (Discord)*
*Researched: 2026-03-25*
*Previous version: 2026-03-23 (pre-v1.1 failure)*
