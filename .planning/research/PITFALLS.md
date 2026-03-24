# Pitfalls Research

**Domain:** MCP server plugin — project-local config scoping (Discord access control)
**Researched:** 2026-03-23
**Confidence:** HIGH — based on direct code inspection of server.ts and SKILL.md

---

## Critical Pitfalls

### Pitfall 1: Project Directory Discovery — The Server Has the Wrong cwd

**What goes wrong:**
The MCP server is launched with `--cwd ${CLAUDE_PLUGIN_ROOT}`, so `process.cwd()` is the plugin cache directory, not the user's project directory. Any code that tries to locate `.claude/channels/discord/access.json` relative to cwd will resolve to the plugin root, not the project.

**Why it happens:**
Developers assume the server runs from where the user is working. The plugin launch mechanism doesn't forward the project cwd — it only exposes `CLAUDE_PLUGIN_ROOT` as the server's working directory.

**How to avoid:**
Pass the project directory explicitly via a dedicated environment variable (e.g., `CLAUDE_PROJECT_DIR`) set by Claude Code's plugin launch config. Do not infer project dir from `process.cwd()`, `__dirname`, import.meta.url, or argv. Document the env var contract clearly so the launch config change is not missed.

**Warning signs:**
- Local access.json never loads even after creating `.claude/channels/discord/access.json` in the project
- `process.cwd()` logged at boot shows a path under `~/.claude/plugins/cache/`
- Fallback to global access.json even when local file exists

**Phase to address:**
Phase 1 (project dir discovery mechanism) — this is a foundational blocker; nothing else works without it.

---

### Pitfall 2: Plugin Cache Overwrites Erase server.ts Changes

**What goes wrong:**
`~/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/server.ts` is inside the plugin cache. Any upstream plugin update will overwrite the file, silently losing local-scoping logic. This is the most likely cause of a silent regression weeks after shipping.

**Why it happens:**
Developers edit the cached file directly because it's the fastest path to get things working. The update mechanism doesn't merge — it replaces the entire versioned directory.

**How to avoid:**
The project-local scoping logic must live in a file outside the plugin cache (e.g., `~/.claude/channels/discord/local-scope.js` as an optional sidecar), OR the changes must be upstreamed to the plugin source and released as a new version. A mid-path is to have server.ts `require`/import from a well-known external path so the cache file stays thin and the logic lives in the user's config directory.

**Warning signs:**
- After running `claude` with a fresh plugin fetch, local scope stops working
- File modification timestamp on `server.ts` resets to the original release date
- Behavior reverts to global-only access.json silently

**Phase to address:**
Phase 1 — decide the code residency strategy before writing any logic into server.ts.

---

### Pitfall 3: Skill-vs-Server Config File Desync

**What goes wrong:**
The `/discord:access` skill edits `~/.claude/channels/discord/access.json` unconditionally (hardcoded path in SKILL.md). If the server is reading a local access.json at `.claude/channels/discord/access.json` but the skill writes to the global path, the skill and server are operating on different files. Users will run `group add` or `pair`, see success, but the server ignores the change.

**Why it happens:**
The skill and server are decoupled — the skill is a prompt-driven Claude tool that edits JSON; the server is a running process. They share state only via the filesystem. When scoping is added, the server's "active file" path becomes dynamic, but the skill still hardcodes the old path.

**How to avoid:**
The skill must be taught the same discovery logic as the server — either by reading a sidecar file that identifies the active scope, or by accepting a `--scope local|global` flag. The simpler approach: when the server starts in local mode, write a sentinel file (e.g., `.claude/channels/discord/.active-scope`) that the skill reads to know which file to edit.

**Warning signs:**
- `/discord:access group add` reports success but Discord messages from that channel are still dropped
- Status output from `/discord:access` shows channels that the server is not actually routing
- `pair` command succeeds (writes approved/ dir) but pairing confirmation never fires because server is watching a different STATE_DIR

**Phase to address:**
Phase 2 (skill update) — after server-side scoping is working, the skill update is required before the feature is usable end-to-end.

---

### Pitfall 4: Shared Bot + Per-Session Filtering — Race on saveAccess

**What goes wrong:**
All Claude Code sessions share one Discord bot and one gateway connection. But each session has its own MCP server process with its own in-memory state. If two sessions both call `saveAccess()` on the same global access.json concurrently (e.g., two pending pairings approved at the same time), the tmp-rename pattern in the current code is atomic per-write but not transactional — one session's write can clobber the other's in-flight changes if both read before either writes.

The server uses `readAccessFile()` fresh on every `gate()` call (not a cached copy), which means this is actually a low-frequency window, but it exists during the pairing flow where `saveAccess` is called twice in sequence.

**Why it happens:**
The current code was designed for a single-session use case. The tmp-rename pattern (`writeFileSync(tmp); renameSync(tmp, ACCESS_FILE)`) is safe against crashes but not against concurrent writers. When local scoping is added, two sessions with the same global access.json will be concurrent writers.

**How to avoid:**
For the global file: accept the existing race as acceptable — the window is small and the worst case is a pairing code getting lost (user retries). For local access.json: this is a single-session file by design, so there is no concurrency concern. Document this clearly — local files are single-writer by construction.

**Warning signs:**
- Pairing codes disappear from `pending` without being approved
- `access.json` gets corrupted (triggers the `.corrupt-${Date.now()}` rename)
- Groups added in one session disappear after another session approves a pairing

**Phase to address:**
Phase 1 — document the concurrency model so the implementation doesn't accidentally introduce new shared-file writes from local-scoped sessions.

---

### Pitfall 5: Backward Compatibility Break for Projects Without Local Config

**What goes wrong:**
If the env var (`CLAUDE_PROJECT_DIR`) is not passed by Claude Code's plugin launch config, the server crashes or silently falls back incorrectly. Existing projects that work fine with global access.json break because the new code path introduces an uncaught exception when the env var is absent.

**Why it happens:**
New code that checks `process.env.CLAUDE_PROJECT_DIR` fails to handle the `undefined` case gracefully. The fallback path ("if no local file, use global") is the correct behavior but requires deliberate defensive coding.

**How to avoid:**
Treat the env var as optional. If `CLAUDE_PROJECT_DIR` is unset or the resulting local access.json path doesn't exist, silently fall through to global. Log a single line to stderr only in debug/verbose mode. Never fail-fast on missing env var for this feature — the old behavior must be preserved exactly.

**Warning signs:**
- Existing users (no local access.json) start getting `DISCORD_BOT_TOKEN required` or similar boot errors after update
- Server exits with nonzero on startup for users who haven't set `CLAUDE_PROJECT_DIR`
- Global-only users see "local access.json not found" errors in stderr

**Phase to address:**
Phase 1 — the fallback logic must be in the very first diff; never ship the env var check without the graceful fallback on the same commit.

---

### Pitfall 6: The approved/ Polling Directory Is Tied to STATE_DIR

**What goes wrong:**
The server polls `~/.claude/channels/discord/approved/` every 5 seconds to send pairing confirmations. This directory is derived from `STATE_DIR`. If the server is in local mode and the skill writes the approval file to the global `approved/` dir (because the skill didn't get the memo about local scoping), the polling loop never fires and the pairing confirmation DM is never sent. The user is approved but gets no "Paired!" message.

**Why it happens:**
`APPROVED_DIR` is computed once at module load from `STATE_DIR`. If the skill and server compute different `STATE_DIR` values, the handshake breaks. The approval flow is a file-based IPC contract between two separate processes.

**How to avoid:**
Make the skill write the approval file to the same `approved/` dir the server is polling. This means the skill must discover the server's active `STATE_DIR` — the sentinel file approach from Pitfall 3 covers this. Alternatively, always use the global `approved/` dir for the handshake (it's user-level, not project-level) and only scope `access.json` itself.

**Warning signs:**
- `/discord:access pair <code>` succeeds (access.json updated) but user never receives "Paired!" DM
- Files accumulate in `~/.claude/channels/discord/approved/` without being cleaned up
- `approved/` dir under `.claude/channels/discord/` stays empty even after pairing

**Phase to address:**
Phase 2 (skill update) — the simplest fix is to keep `approved/` always at the global path and only scope `access.json`.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Edit server.ts directly in plugin cache | Fastest path to working code | Silently lost on plugin update | Never — always upstream or use external sidecar |
| Hardcode local access.json path as `.claude/channels/discord/access.json` | Simple, predictable | Can't be configured per-project if project layout changes | Acceptable for v1 with documentation |
| Read active-scope sentinel file from disk on every gate() call | No in-memory state to get stale | Extra fs read per Discord message | Acceptable — same pattern as existing readAccessFile() |
| Skip updating SKILL.md and rely on users manually specifying paths | Faster to ship | Skill and server immediately desync; feature is broken by default | Never — skill update is required for the feature to be usable |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Claude Code plugin launch config | Assuming env vars from the user's shell are forwarded | Only `CLAUDE_PLUGIN_ROOT` is guaranteed; project dir must be explicitly injected via the launch config |
| MCP server + skill (SKILL.md) | Treating them as the same process | They are separate: server is a long-running Bun process; skill is a Claude prompt tool. They share only the filesystem |
| access.json + STATIC mode | STATIC snapshots at boot — local file changes after startup are ignored | Always restart the server after writing a new local access.json; document this to users |
| approved/ polling IPC | Assuming server and skill agree on STATE_DIR | The approval handshake is a two-party filesystem contract; both parties must resolve to the same directory |
| Discord bot (single shared) | Adding per-session bot reconnects | There is one bot, one gateway connection. Filtering is server-side in the gate() function, not at the Discord API level |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Storing local access.json at a world-readable path | Other users on the machine can read the allowlist and channel IDs | Create `.claude/channels/discord/` with mode 0o700, matching the existing global dir convention |
| Trusting `CLAUDE_PROJECT_DIR` env var for path traversal | Malicious env could point to a path outside the project (e.g., `../../.ssh/`) | Validate that the resolved local access.json path is actually inside the project directory before reading/writing |
| Leaking local scope sentinel file via the assertSendable guard | If the sentinel file is inside STATE_DIR, the existing `assertSendable` guard already blocks it; if outside, it's exposed | Place the sentinel file inside STATE_DIR (same protection) or in the project `.claude/` dir (outside server reach) |
| Allowing the local access.json path to be set via Discord message | Prompt injection from an allowlisted Discord user could redirect the active config | The active scope must be set only at server boot via env var, not via any tool or channel message |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Silent fallback to global with no indication | User creates a local access.json, it silently doesn't load; they spend an hour debugging | Log one line to stderr at boot: "using local access.json at <path>" or "no local access.json found, using global" |
| `/discord:access` status shows global file when local is active | User can't tell which file controls what they're seeing | Status output must show "Active config: LOCAL (.claude/channels/discord/access.json)" vs "Active config: GLOBAL (~/.claude/channels/discord/access.json)" |
| group rm operates on wrong file | User removes a group from the global file but it was defined in the local file (or vice versa); removal silently does nothing | The skill must identify which file contains the group before removing it |
| No error when local access.json is malformed JSON | Falls back to global silently — user thinks local scope is working but isn't | Log a clear warning: "local access.json is malformed, falling back to global" |

---

## "Looks Done But Isn't" Checklist

- [ ] **Local scope loading:** Verify with `process.stderr` log line at boot — not just that the code path exists, but that it actually fires with a real project dir
- [ ] **Skill desync:** After adding a group with `/discord:access group add`, check which file was written — confirm it's the same file the server is reading
- [ ] **Pairing confirmation:** After `/discord:access pair <code>` in local mode, verify the "Paired!" DM actually arrives — tests the approved/ IPC path
- [ ] **Plugin update resilience:** Simulate a plugin cache clear; verify local scoping still works (logic is not in the cache)
- [ ] **Backward compat:** In a session with no local access.json and no `CLAUDE_PROJECT_DIR`, verify exact same behavior as before the change
- [ ] **STATIC mode + local:** In `DISCORD_ACCESS_MODE=static`, verify the local file snapshot is taken at boot and not re-read

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Plugin cache overwrite erases server.ts changes | HIGH | Re-apply the diff to server.ts; if no upstream PR exists, maintain a patch file or git stash in the project repo |
| Skill-server desync (wrong file edited) | LOW | Manually copy groups/allowlist entries between global and local access.json; restart server |
| Local access.json corruption | LOW | Delete local file; server falls back to global; recreate local config via `/discord:access` |
| approved/ IPC broken (no pairing confirmation) | LOW | Manually add senderId to allowFrom in the correct access.json; no DM confirmation but access works |
| Project dir env var not set (new session after config change) | MEDIUM | Add `CLAUDE_PROJECT_DIR` to the plugin launch invocation; restart session |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Wrong cwd / project dir discovery | Phase 1: server-side scoping | Boot log shows correct project path; local file loads |
| Plugin cache overwrite | Phase 1: code residency decision | Simulate cache clear; feature still works |
| Shared bot race on saveAccess | Phase 1: document concurrency model | Two simultaneous pairings don't corrupt access.json |
| Backward compat break | Phase 1: fallback logic | Session without env var behaves identically to v0 |
| Skill-server desync | Phase 2: skill update | group add writes to the file server is reading |
| approved/ IPC mismatch | Phase 2: skill update | Pairing confirmation DM fires after pair command |
| Silent fallback with no log | Phase 1: observability | Boot stderr clearly states which file is active |

---

## Sources

- Direct code inspection: `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/server.ts` — lines 32–36 (STATE_DIR/ACCESS_FILE constants), 184–190 (saveAccess), 314–354 (checkApprovals polling), 166–178 (STATIC mode snapshot)
- Direct code inspection: `~/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/skills/access/SKILL.md` — hardcoded `~/.claude/channels/discord/access.json` path throughout
- Project context: `.planning/PROJECT.md` — "Key challenge: the server's cwd is set to CLAUDE_PLUGIN_ROOT, not the project directory"
- Project context: `.planning/PROJECT.md` — "Plugin cache: Files in ~/.claude/plugins/cache/ may be overwritten on plugin updates"
- General: MCP server stdio transport design — server process is spawned per session with no shared memory

---

*Pitfalls research for: MCP plugin project-local config scoping (Discord)*
*Researched: 2026-03-23*
