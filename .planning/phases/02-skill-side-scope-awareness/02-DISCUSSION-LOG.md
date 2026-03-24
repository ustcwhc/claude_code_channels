# Phase 2: Skill-Side Scope Awareness - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-24
**Phase:** 02-skill-side-scope-awareness
**Areas discussed:** Scope prompt UX, Status display, group rm behavior, Skill residency

---

## Scope Prompt UX

| Option | Description | Selected |
|--------|-------------|----------|
| AskUserQuestion | Claude's built-in multi-choice UI | ✓ |
| Plain text prompt | "Add to (1) local or (2) global?" | |
| You decide | Claude picks | |

**User's choice:** AskUserQuestion

| Option | Description | Selected |
|--------|-------------|----------|
| Local first | Default to local when in a project | ✓ |
| No default | Present both equally | |
| You decide | Claude picks | |

**User's choice:** Local first

| Option | Description | Selected |
|--------|-------------|----------|
| Skip prompt, use global | Silently write to global | |
| Warn then global | Show note, then write to global | ✓ |
| You decide | Claude picks | |

**User's choice:** Warn then global

| Option | Description | Selected |
|--------|-------------|----------|
| Bash pwd | Run pwd via Bash tool | |
| Env var | Read DISCORD_PROJECT_DIR from env | ✓ |
| You decide | Claude picks | |

**User's choice:** Env var

---

## Status Display

| Option | Description | Selected |
|--------|-------------|----------|
| Local only | Show only local file contents | ✓ |
| Both labeled | Show local then global with labels | |
| You decide | Claude picks | |

**User's choice:** Local only

| Option | Description | Selected |
|--------|-------------|----------|
| Banner line | "Using: local (...)" at top | ✓ |
| Inline note | "(local)" appended to heading | |
| You decide | Claude picks | |

**User's choice:** Banner line

---

## group rm Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Active file only | Only remove from active file | |
| Search both | Check both, remove from whichever has it | ✓ |
| You decide | Claude picks | |

**User's choice:** Search both

| Option | Description | Selected |
|--------|-------------|----------|
| Error message | "Channel X not found in config" | |
| Hint at other | "Not found in local. May exist in global." | ✓ |
| You decide | Claude picks | |

**User's choice:** Hint at other

---

## Skill Residency

| Option | Description | Selected |
|--------|-------------|----------|
| Same patch file | Add to existing discord-local-scoping.patch | ✓ |
| Separate patch | New patch file for SKILL.md | |
| You decide | Claude picks | |

**User's choice:** Same patch file

| Option | Description | Selected |
|--------|-------------|----------|
| Patch (diff) | Apply diff to existing SKILL.md | |
| Full replace | Keep complete modified SKILL.md, copy over | |
| You decide | Claude picks | ✓ |

**User's choice:** You decide (Claude's discretion)

## Claude's Discretion

- Diff vs full-replace for SKILL.md within the patch
- Exact wording of scope prompt options
- How skill reads DISCORD_PROJECT_DIR
- pair/deny operations: always global or follow active

## Deferred Ideas

- `--local`/`--global` flags — Phase 3
- Full resolved path in status — Phase 3
- Duplicate group warning — Phase 3
