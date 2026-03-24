# Project Retrospective

## Milestone: v1.0 — Project-Local Discord Access

**Shipped:** 2026-03-24
**Phases:** 3 | **Plans:** 5

### What Was Built
- Project-local access.json resolution in the Discord MCP server (`resolveAccessFile()`)
- Scope-aware `/discord:access` skill with local/global prompt, status banner, dual-file group rm
- `--local`/`--global` flags for power-user scripting
- Duplicate-group warnings on status and group add
- Patch delivery mechanism (SessionStart hook + unified diff) for plugin cache resilience

### What Worked
- Patch-based code residency solved the plugin cache overwrite problem cleanly — no fork needed
- Sequential phase structure (server → skill → polish) kept each phase focused and independently verifiable
- Full isolation model (local replaces global entirely) eliminated complex merge logic
- Coarse granularity (3 phases, 5 plans) was the right call for a small plugin upgrade

### What Was Inefficient
- SKIL-06/SKIL-07 (flags) were initially mapped to Phase 2, then deferred to Phase 3 during discuss-phase — could have been Phase 3 from the start in roadmap
- Phase 3 required regenerating the SKILL.md patch hunk — same diff workflow ran 3 times across phases

### Patterns Established
- Plugin modification via unified diff patch + SessionStart hook
- SKILL.md scope resolution mirroring server.ts `resolveAccessFile()` pattern
- Env var bridge: `CLAUDE_PROJECT_DIR` → `DISCORD_PROJECT_DIR` via `.mcp.json` env block

### Key Lessons
- Plugin cache files are volatile — always plan for a residency strategy before modifying them
- Skills and servers share no runtime — resolution logic must be independently implemented in both
- `approved/` and `inbox/` directories are user-level, not project-level — keep them global

### Cost Observations
- Model mix: planner used opus, executors and researchers used sonnet
- Sessions: 1 continuous session
- Notable: research was skipped for Phases 2-3 (domain well-understood from Phase 1 research)

## Cross-Milestone Trends

| Milestone | Phases | Plans | Days | Key Pattern |
|-----------|--------|-------|------|-------------|
| v1.0 | 3 | 5 | 1 | Plugin modification via patch + hook |
