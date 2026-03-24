# Phase 2: Skill-Side Scope Awareness - Context

**Gathered:** 2026-03-24
**Status:** Ready for planning

<domain>
## Phase Boundary

The `/discord:access` skill independently resolves the active config file (local vs global) and all operations (`group add`, `group rm`, status display) read/write the correct file. The scope prompt on `group add` lets users choose local vs global.

</domain>

<decisions>
## Implementation Decisions

### Scope Prompt UX (group add)
- **D-01:** Use `AskUserQuestion` for the local/global scope choice — consistent with GSD prompt style
- **D-02:** When `DISCORD_PROJECT_DIR` is set, default to "local" as the first/recommended option — matches git behavior
- **D-03:** If `DISCORD_PROJECT_DIR` is not available, show a warning that local scoping isn't available, then write to global without prompting
- **D-04:** Skill discovers project directory via `DISCORD_PROJECT_DIR` env var (not `pwd`)

### Status Display
- **D-05:** When local config is active, show only the local file's contents — consistent with full isolation model
- **D-06:** Banner line at the top: `"Using: local (.claude/channels/discord/access.json)"` or `"Using: global (~/.claude/channels/discord/access.json)"` before showing contents
- **D-07:** When no local config exists, show global contents with global banner (existing behavior + banner)

### group rm Behavior
- **D-08:** `group rm` searches both local and global files — removes from whichever contains the group (more forgiving than strict isolation)
- **D-09:** If the group isn't found in either file, hint: "Channel X not found in local config. It may exist in global config." (or vice versa)

### Skill Residency
- **D-10:** SKILL.md changes go into the same `discord-local-scoping.patch` file as server.ts/.mcp.json changes — one patch covers all plugin modifications
- **D-11:** Claude's discretion on whether to use diff or full-replace for SKILL.md within the patch

### Other Operations
- **D-12:** `pair`, `deny`, `allow`, `remove`, `policy` — these are DM/user-level operations. They always operate on global `access.json` per Phase 1 decision D-10
- **D-13:** `set` (delivery config) — operates on the active file (local or global)

### Claude's Discretion
- Whether SKILL.md changes use diff hunks or full file replacement within the patch
- Exact wording of the scope prompt options
- How the skill reads `DISCORD_PROJECT_DIR` (Bash env check vs direct read)
- `pair`/`deny` operations: always global, or follow active file

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Skill Source (modify target)
- `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/skills/access/SKILL.md` — Full skill definition; all operations, dispatch logic, implementation notes

### Phase 1 Artifacts (established patterns)
- `.planning/phases/01-server-side-scoping/01-CONTEXT.md` — Prior decisions D-01 through D-13 that constrain this phase
- `scripts/apply-discord-patch.sh` — Existing patch apply script (will need to handle SKILL.md too)
- `patches/discord-local-scoping.patch` — Existing patch file (append SKILL.md changes)

### Server Implementation (reference for consistency)
- `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/server.ts` — `resolveAccessFile()` implementation, `ACTIVE_ACCESS_FILE`, `ACTIVE_SCOPE` patterns

### Project Context
- `.planning/PROJECT.md` — Constraints, key decisions
- `.planning/REQUIREMENTS.md` — SKIL-01 through SKIL-07

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `resolveAccessFile()` pattern in server.ts — same resolution logic needed in SKILL.md (check local first, fall back to global)
- `apply-discord-patch.sh` — already handles server.ts and .mcp.json; extend to include SKILL.md
- `patches/discord-local-scoping.patch` — append SKILL.md hunks to existing patch

### Established Patterns
- SKILL.md uses `Read` and `Write` tools to manipulate access.json — all reads/writes go through a single hardcoded path (`~/.claude/channels/discord/access.json`)
- Skill dispatches on arguments: no args → status, `group add` → add group, `group rm` → remove group, etc.
- The skill runs inside Claude Code with access to `Read`, `Write`, and `Bash(ls *)`, `Bash(mkdir *)` tools only

### Integration Points
- Every operation that reads access.json needs to resolve the path first (local vs global)
- Every operation that writes access.json needs to write to the resolved path
- `group add` is the only operation that needs the scope prompt
- Status (no args) needs the banner line addition
- `group rm` needs to search both files

</code_context>

<specifics>
## Specific Ideas

- The skill's resolution logic should mirror server.ts: check `DISCORD_PROJECT_DIR` env var → check if `<projectDir>/.claude/channels/discord/access.json` exists → use it or fall back to global
- The AskUserQuestion prompt for scope should be clear and concise — "Add this channel to your project-local config or global config?"

</specifics>

<deferred>
## Deferred Ideas

- `--local`/`--global` flags to bypass the prompt — Phase 3
- Full resolved path in status output — Phase 3
- Duplicate group warning — Phase 3

</deferred>

---

*Phase: 02-skill-side-scope-awareness*
*Context gathered: 2026-03-24*
