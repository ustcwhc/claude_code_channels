# Phase 3: UX Polish - Context

**Gathered:** 2026-03-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Power-user ergonomics: `--local`/`--global` flags on `group add` to bypass the interactive scope prompt, full absolute path in status output, and duplicate-group warning when the same channel appears in both local and global config.

</domain>

<decisions>
## Implementation Decisions

### --local/--global Flags
- **D-01:** Flags apply to `group add` only — other operations use resolved scope automatically
- **D-02:** `--local` skips the AskUserQuestion prompt, writes directly to project-local file
- **D-03:** `--global` skips the AskUserQuestion prompt, writes directly to global file
- **D-04:** If `--local` is used but `DISCORD_PROJECT_DIR` is not set, error with clear message (don't silently fall back)

### Full Resolved Path
- **D-05:** Status output includes the full absolute path (e.g., `/Users/foo/project/.claude/channels/discord/access.json`), not just the abbreviated relative path
- **D-06:** This replaces the Phase 2 abbreviated banner — upgrade from `.claude/channels/discord/access.json` to the full path

### Duplicate Group Warning
- **D-07:** Warning appears on status display AND when running `group add` for a channel that exists in the other file
- **D-08:** Warning is informational only — does not block the operation
- **D-09:** Format: "⚠ Channel <id> also exists in [local/global] config. Local config takes precedence when active."

### Patch Updates
- **D-10:** All changes go into the existing `discord-local-scoping.patch` — regenerate the SKILL.md hunk with the new content

### Claude's Discretion
- Exact flag parsing implementation in SKILL.md
- Warning placement in status output (before or after the groups list)
- Whether `--local` without `DISCORD_PROJECT_DIR` should suggest how to set it up

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Skill Source (modify target)
- `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/skills/access/SKILL.md` — Current scope-aware skill (Phase 2 output)

### Phase 1-2 Artifacts
- `.planning/phases/01-server-side-scoping/01-CONTEXT.md` — Server-side decisions
- `.planning/phases/02-skill-side-scope-awareness/02-CONTEXT.md` — Skill-side decisions
- `scripts/apply-discord-patch.sh` — Patch apply script
- `patches/discord-local-scoping.patch` — Unified patch (3 hunks)

### Project Context
- `.planning/REQUIREMENTS.md` — UX-01, UX-02, SKIL-06, SKIL-07

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Phase 2 SKILL.md scope resolution section — already resolves ACTIVE_PATH; flags just bypass the prompt
- Phase 2 `group add` AskUserQuestion block — flags provide an alternative path around it
- Phase 2 `group rm` dual-file search — can detect duplicates as a side effect

### Established Patterns
- SKILL.md parses `$ARGUMENTS` space-separated; flags like `--no-mention` and `--allow` already exist in `group add`
- Status display already has the banner line — just needs path upgrade
- Patch regeneration follows the same diff workflow as Phase 2 Plan 02

### Integration Points
- `group add` argument parsing — add `--local`/`--global` flag detection before the scope prompt
- Status display — replace abbreviated path with full absolute path
- Both status and `group add` need duplicate detection logic

</code_context>

<specifics>
## Specific Ideas

No specific requirements — standard implementation of flags and warnings.

</specifics>

<deferred>
## Deferred Ideas

None — this is the final phase.

</deferred>

---

*Phase: 03-ux-polish*
*Context gathered: 2026-03-24*
