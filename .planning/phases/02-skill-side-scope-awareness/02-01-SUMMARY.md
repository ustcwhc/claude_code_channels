---
phase: 02-skill-side-scope-awareness
plan: "01"
subsystem: skill
tags: [discord, access-control, scope, skill]
dependency_graph:
  requires: [01-server-side-scoping]
  provides: [skill-scope-awareness]
  affects: [discord-access-skill]
tech_stack:
  added: []
  patterns: [scope-resolution-via-printenv, AskUserQuestion-for-scope-choice]
key_files:
  created: []
  modified:
    - ~/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/skills/access/SKILL.md
decisions:
  - "D-01: AskUserQuestion for scope choice in group add"
  - "D-02: Default to local when DISCORD_PROJECT_DIR set"
  - "D-03: No PROJECT_DIR → warn, write global, no prompt"
  - "D-12: pair/deny/allow/remove/policy always global"
  - "D-13: set follows active (resolved) file"
metrics:
  duration: "2 minutes"
  completed_date: "2026-03-24"
  tasks_completed: 1
  files_modified: 1
---

# Phase 02 Plan 01: Scope-Aware Discord Access Skill Summary

Rewrote `/discord:access` SKILL.md with full scope-awareness: printenv-based DISCORD_PROJECT_DIR resolution, Using: local/global status banner, AskUserQuestion scope prompt on `group add`, dual-file search in `group rm`, and explicit global-only annotations on `pair`/`deny`/`allow`/`remove`/`policy`.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Write updated SKILL.md with scope-aware logic | f80e2bb | `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/skills/access/SKILL.md` |

## What Was Built

The SKILL.md now mirrors the `resolveAccessFile()` pattern from server.ts:

1. **Scope resolution section** — uses `Bash(printenv DISCORD_PROJECT_DIR)` to discover the project directory, then `Bash(ls ...)` to check if the local access.json exists. Sets SCOPE=local or SCOPE=global and ACTIVE_PATH accordingly.

2. **Status banner** — before showing access.json contents, prints `Using: local (.claude/channels/discord/access.json)` or `Using: global (~/.claude/channels/discord/access.json)`.

3. **group add scope prompt** — when DISCORD_PROJECT_DIR is set, uses AskUserQuestion to let the user choose local or global. Defaults "local" as first option (D-02). When PROJECT_DIR is unset, warns and writes to global without prompting (D-03).

4. **group rm dual-file search** — checks both LOCAL_PATH and GLOBAL_PATH, removes from whichever file contains the group. Handles edge cases: not found in either, found in both.

5. **pair/deny/allow/remove/policy** — each section now carries an explicit note: "this operation always uses the global access.json". These DM/user-level operations are not project-scoped (D-12).

6. **set** — runs scope resolution to get ACTIVE_PATH, then reads/writes that path (D-13).

7. **Frontmatter** — added `Bash(printenv *)` to `allowed-tools` so the skill can read env vars.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check

- SKILL.md exists at expected path: PASSED
- `grep "Scope resolution"` returns 1 match: PASSED
- `grep -c "DISCORD_PROJECT_DIR"` returns 4 (>= 3): PASSED
- `grep -c "Using: local"` returns 1: PASSED
- `grep -c "Using: global"` returns 1: PASSED
- `grep -c "AskUserQuestion"` returns 1: PASSED
- `grep -c "always uses the global"` returns 5 (>= 4): PASSED
- `Bash(ls *)` and `Bash(mkdir *)` still in frontmatter: PASSED
- `grep -c "printenv DISCORD_PROJECT_DIR"` returns 2 (>= 1): PASSED
- Task commit f80e2bb exists: PASSED
