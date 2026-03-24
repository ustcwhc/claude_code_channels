---
phase: 01-server-side-scoping
plan: "01"
subsystem: infra
tags: [bash, patch, hooks, claude-code, plugin-cache, discord]

# Dependency graph
requires: []
provides:
  - Idempotent apply-discord-patch.sh script in scripts/
  - Placeholder patches/discord-local-scoping.patch tracked in repo
  - SessionStart hook registered in ~/.claude/settings.json pointing to apply-discord-patch.sh
affects:
  - 01-02 (must populate patches/discord-local-scoping.patch with real diff)
  - All future sessions (hook runs on every Claude Code session start)

# Tech tracking
tech-stack:
  added: [bash shell script, patch(1) utility]
  patterns:
    - Marker-based idempotency: grep for comment line in target file before applying patch
    - Graceful degradation: missing patch file or missing plugin both exit 0 with descriptive message
    - patch exit 2 treated as no-op (placeholder/empty patch file state)

key-files:
  created:
    - scripts/apply-discord-patch.sh
    - patches/discord-local-scoping.patch
  modified:
    - ~/.claude/settings.json (SessionStart hooks array — not in repo)

key-decisions:
  - "patch exit code 2 (no hunks found) treated as success — allows placeholder patch to coexist with live hook"
  - "Hook appended to existing SessionStart hooks array, not a new array object"
  - "Script uses BASH_SOURCE[0] for self-relative PATCH_FILE path — works regardless of invocation directory"

patterns-established:
  - "Idempotency via marker: grep -qF '// discord-local-scoping patch applied' $SERVER_TS"
  - "Graceful exit 0 on missing files with descriptive stderr message"

requirements-completed: [RESL-01]

# Metrics
duration: 2min
completed: 2026-03-24
---

# Phase 01 Plan 01: Server-Side Scoping — Code Residency Infrastructure Summary

**Idempotent bash hook + patch scaffolding that survives plugin cache wipes, registered as a Claude Code SessionStart hook**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-03-24T04:14:48Z
- **Completed:** 2026-03-24T04:16:30Z
- **Tasks:** 2
- **Files modified:** 3 (scripts/apply-discord-patch.sh, patches/discord-local-scoping.patch, ~/.claude/settings.json)

## Accomplishments

- Created `scripts/apply-discord-patch.sh` — idempotent apply script with marker-based detection, graceful handling of missing patch/plugin files
- Created `patches/discord-local-scoping.patch` — placeholder file tracked in repo; populated by plan 01-02
- Registered SessionStart hook in `~/.claude/settings.json` so the apply script runs on every Claude Code session start alongside the existing gsd-check-update.js hook

## Task Commits

Each task was committed atomically:

1. **Task 1: Create scripts/ dir and idempotent apply-discord-patch.sh** - `d98216f` (feat)
2. **Task 2: Create placeholder patch file** - `e81615b` (chore)
3. **Auto-fix: Handle patch exit 2 as graceful no-op** - `dd5f87f` (fix)

## Files Created/Modified

- `scripts/apply-discord-patch.sh` — Idempotent script: checks marker, handles missing files, applies patch via `patch -p0` from $HOME
- `patches/discord-local-scoping.patch` — Placeholder comment-only file; plan 01-02 will write the real unified diff
- `~/.claude/settings.json` — Added apply-discord-patch.sh entry to existing SessionStart hooks array with timeout 15

## Decisions Made

- Used `patch exit code 2` (no patch found) as a success case — `patch` returns 2 on a comment-only file, which is the expected placeholder state before 01-02 runs. Script treats this as "nothing to do" rather than an error.
- Hook appended into the existing `SessionStart[0].hooks` array rather than creating a second SessionStart element — preserves single-object structure already present.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Placeholder patch causes patch exit 2, script exited non-zero**
- **Found during:** Task 2 verification (running overall verification suite)
- **Issue:** `patch -p0` on a comment-only file exits 2 ("no patch found"). The original script used `if patch ...` which treated exit 2 as failure, causing the hook to exit 1 before plan 01-02 runs.
- **Fix:** Captured patch exit code explicitly; treat exit 2 as "no hunks — skipping" and exit 0. Only exit 1 on patch exit code 1 (hunk failures).
- **Files modified:** `scripts/apply-discord-patch.sh`
- **Verification:** `bash apply-discord-patch.sh` exits 0 with message "patch file contains no hunks — skipping"
- **Committed in:** `dd5f87f`

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Necessary for the script to function correctly before 01-02 populates the real patch. No scope creep.

## Issues Encountered

None beyond the auto-fixed placeholder patch exit code issue above.

## User Setup Required

None — hook is registered automatically in ~/.claude/settings.json. The apply script runs on every new Claude Code session start. No manual steps required until plan 01-02 populates the real patch content.

## Next Phase Readiness

- Scaffolding complete — plan 01-02 can now write the real `patches/discord-local-scoping.patch` content
- The hook is live; once 01-02 commits the patch, it will auto-apply on next session start
- No blockers

---
*Phase: 01-server-side-scoping*
*Completed: 2026-03-24*
