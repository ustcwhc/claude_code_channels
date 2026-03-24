# Milestones

## v1.0 Project-Local Discord Access (Shipped: 2026-03-24)

**Phases completed:** 3 phases, 5 plans, 9 tasks

**Key accomplishments:**

- Idempotent bash hook + patch scaffolding that survives plugin cache wipes, registered as a Claude Code SessionStart hook
- Project-local access.json resolution in the Discord MCP server via resolveAccessFile(), ACTIVE_ACCESS_FILE wiring, and a unified diff patch for cache-wipe resilience
- Extended discord-local-scoping.patch with a SKILL.md diff hunk and updated apply script to check both server.ts and SKILL.md markers before skipping — SKILL.md scope changes now survive plugin cache updates.
- `/discord:access` status now shows full absolute path; `group add` gains `--local`/`--global` flags to bypass interactive scope prompt; duplicate-group warnings added to both status and group add

---
