# Phase 3: UX Polish - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.

**Date:** 2026-03-24
**Phase:** 03-ux-polish
**Areas discussed:** Flag behavior, Duplicate warning

---

## Flag Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| group add only | Flags only on group add | ✓ |
| group add + set | Flags on group add and set | |
| All operations | Flags everywhere | |
| You decide | Claude picks | |

**User's choice:** group add only

## Duplicate Warning

| Option | Description | Selected |
|--------|-------------|----------|
| Status only | Warn only on /discord:access (no args) | |
| Status + group add | Warn on status AND group add | ✓ |
| You decide | Claude picks | |

**User's choice:** Status + group add

## Claude's Discretion

- Flag parsing implementation details
- Warning placement in status output
- Error message when --local used without DISCORD_PROJECT_DIR
