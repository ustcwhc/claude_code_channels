# Feature Research

**Domain:** Project-scoped configuration for CLI tool plugins (MCP server upgrade)
**Researched:** 2026-03-23
**Confidence:** HIGH (well-established ecosystem patterns; cross-referenced git, npm, ESLint, direnv)

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist based on every other CLI tool with local config. Missing these = the feature feels broken or half-baked.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Local config file at a predictable path | git uses `.git/config`, npm uses `.npmrc`, ESLint uses `.eslintrc` — users expect a dotfile in the project root or a `.claude/` subdirectory | LOW | PROJECT.md already decided: `./.claude/channels/discord/access.json` |
| Local config completely replaces global (no silent merge) | Isolation is the whole point — cross-project bleed is the bug being fixed. git's local config *overrides* global values per-key. The PROJECT.md decision of "full replacement" matches this mental model | LOW | Already decided. Merge would require per-key precedence rules that add complexity with no clear user benefit for this use case |
| Explicit scope prompt at config write time | When running `group add`, the user must choose local vs global. No silent defaulting — git requires you to pass `--global` explicitly, local is the default. Users expect to be asked | LOW | The UX moment where scope is set. A bad default here causes hard-to-debug cross-project leakage |
| Status command shows which config is active | `git config --list --show-origin` shows where each value comes from. Users running multiple sessions need to know at a glance whether the current session is local or global | LOW | `/discord:access` (no args) must show "using local: ./.claude/channels/discord/access.json" or "using global: ~/.claude/channels/discord/access.json" |
| Fallback to global when no local config exists | npm falls back up the directory tree; git falls back to `~/.gitconfig`. Sessions without a local config must work exactly as before — zero regression | LOW | Already in requirements. Critical for backward compatibility |
| `group rm` operates on the correct file | When you remove a channel group, it must edit whichever file the group lives in. Editing the wrong file leaves ghost entries or silently fails | MEDIUM | Requires knowing at `rm` time whether the active config is local or global — same logic as server startup |

### Differentiators (Competitive Advantage)

Features that improve the experience beyond basic correctness. Not required for the feature to work, but meaningfully reduce friction.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| `--local` / `--global` flags on `group add` | Avoids the interactive prompt for scripting and power users. git supports both `--local` and `--global` flags. Lets users wire up a project in one command without answering prompts | LOW | Optional enhancement to the scope prompt. Does not replace the prompt — just allows bypass. Useful for project dotfile setup scripts |
| Show config file path in status output | Helps users who clone a repo, find an existing local config, and need to know where it came from. Not just "local" but the full resolved path | LOW | Costs one line of output. Reduces "wait, which file am I editing?" confusion |
| `group add` with `--local` as default for new sessions | When running inside a project directory (env var passed), default scope for `group add` should be local, not global. Matches git's "local is default when in a repo" behavior | LOW | Only relevant once project-dir discovery is solved. Can be deferred if the prompt already makes scope explicit |
| Warn when a global channel group is also in local config | Duplicate group entries across local and global could confuse users auditing their config. A warning at status-check time ("channel X also appears in global config, but local config takes precedence") prevents silent confusion | LOW | Low-cost safety net. Purely informational — no action required |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Merge local + global access.json | Seems more flexible — why not use global groups AND local ones? | Unpredictable precedence at runtime. If the same channel ID appears in both, which wins? Per-key merge requires a full precedence model, documentation, and user mental overhead. The isolation guarantee is lost | Full replacement (already decided in PROJECT.md). If you need global groups in a project, copy them to the local file. Explicit is better than implicit |
| Auto-detect project dir from cwd of the skill process | "Just use cwd" feels simpler than passing an env var | The skill runs inside Claude Code, which may have a different cwd than the project root. The MCP server's cwd is `CLAUDE_PLUGIN_ROOT`, not the project. Silent wrong-dir detection causes config to be written to the wrong place with no error | Pass project dir via env var explicitly (already identified as the correct approach in PROJECT.md) |
| Per-channel-group scope (some groups local, some global) | Fine-grained control | Requires tracking which file each group came from at runtime, merging at read time, and knowing where to write at edit time. Breaks the simple "one file wins" mental model | Project isolation is binary: either the whole session is project-scoped or it isn't. Keep the model simple |
| Config inheritance / directory tree walk (npm-style) | npm walks up to find `.npmrc`. Seems convenient for monorepos | For Discord channel routing, "close enough" project detection is dangerous — a workspace root config leaking into a sub-package session is the bug we're fixing. Deterministic > convenient here | Explicit env var. The session's project dir is known at startup; don't walk |
| GUI or web interface for managing local config | Lower barrier for non-technical users | Scope creep. The plugin is a developer tool used via terminal. A GUI adds infrastructure, auth, and maintenance cost with no clear payoff for this audience | Keep the skill-based CLI approach; improve `--flags` for scripting |

## Feature Dependencies

```
[Scope prompt in group add]
    └──requires──> [Project dir env var discovery]
                       └──required before──> [Server reads local config at startup]

[group rm on correct file]
    └──requires──> [Server/skill knows which file is active]
                       └──same mechanism as──> [Server reads local config at startup]

[Status shows active config]
    └──requires──> [Server/skill knows which file is active]

[--local/--global flags]
    └──enhances──> [Scope prompt in group add]
    └──requires──> [Project dir env var discovery]

[Warn on duplicate groups]
    └──requires──> [Status shows active config]
    └──enhances──> [Status shows active config]
```

### Dependency Notes

- **Project dir env var discovery blocks everything:** All scoping features depend on the server/skill knowing the project directory at startup. This is the foundational problem to solve first — the server's cwd is `CLAUDE_PLUGIN_ROOT`, not the project. Nothing else works correctly without this.
- **Status command is a forcing function:** Implementing "show which file is active" forces you to correctly implement the local-vs-global resolution logic. Build status first — it validates the core mechanism before you build `group add` scope prompting on top of it.
- **`group rm` scope awareness depends on the same mechanism as startup:** The server must resolve local-vs-global at boot; the skill must use the same resolution at edit time. These should share logic, not be implemented twice.
- **`--local/--global` flags enhance but don't replace the prompt:** The flags are a power-user shortcut. The interactive prompt remains the primary UX for users who don't know which scope they want.

## MVP Definition

### Launch With (v1)

Minimum viable — what's needed for project-local scoping to work correctly.

- [ ] Project dir passed via env var to server and skill — foundation for all other scoping
- [ ] Server reads local access.json at startup if it exists, else falls back to global — core routing behavior
- [ ] `group add` prompts for local vs global scope — the UX moment where isolation is set up
- [ ] Status command (`/discord:access` no args) shows which file is active and its path — required for debugging and confidence
- [ ] `group rm` operates on the correct file — correctness requirement; editing the wrong file is silent data corruption

### Add After Validation (v1.x)

Add once the core local/global split is working and in use.

- [ ] `--local` / `--global` flags on `group add` — triggered when users start scripting project setup in dotfiles
- [ ] Warning when a channel group appears in both local and global config — triggered by user confusion reports
- [ ] Show full resolved path in status output (already low effort, could fold into v1)

### Future Consideration (v2+)

Defer until there's evidence of need.

- [ ] Default scope inferred from whether a local config already exists — adds magic, prefer explicit until patterns emerge
- [ ] `config init` command to scaffold a local access.json — useful if project dotfile workflows become common

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Project dir via env var | HIGH | LOW | P1 |
| Server reads local config, falls back to global | HIGH | LOW | P1 |
| `group add` scope prompt (local vs global) | HIGH | LOW | P1 |
| Status shows active file | HIGH | LOW | P1 |
| `group rm` on correct file | HIGH | MEDIUM | P1 |
| `--local` / `--global` flags | MEDIUM | LOW | P2 |
| Show full path in status | MEDIUM | LOW | P2 |
| Warn on duplicate groups | LOW | LOW | P3 |

**Priority key:**
- P1: Must have for launch — feature is non-functional or unsafe without it
- P2: Should have — polish and power-user ergonomics
- P3: Nice to have — informational improvement

## Competitor Feature Analysis

Drawn from established CLI tools with local/global config split.

| Feature | git config | npm .npmrc | ESLint | Our Approach |
|---------|------------|------------|--------|--------------|
| Local config location | `.git/config` (auto-detected from repo root) | `.npmrc` in cwd, walks up to home | `.eslintrc` in project root | `.claude/channels/discord/access.json` in project root — explicit, not auto-walked |
| Global config location | `~/.gitconfig` | `~/.npmrc` | `~/.eslintrc` (deprecated) | `~/.claude/channels/discord/access.json` |
| Resolution strategy | Local overrides global per-key | Local overrides global per-key | Nearest config wins, can extend parent | Local replaces global entirely — simpler, full isolation |
| Explicit scope flag | `--local` / `--global` / `--system` | `--location` | N/A (file-based) | `--local` / `--global` on `group add` (v1.x) |
| Status / introspection | `git config --list --show-origin` | `npm config list` | N/A | `/discord:access` shows active file + contents |
| Config bootstrapping | Auto-created on `git init` | Created by `npm init` | User creates file | Created by skill when user chooses "local" scope |

**Key divergence from ecosystem norms:** git and npm merge local + global (local wins on conflicts). We use full replacement. This is intentional — for message routing, partial isolation is worse than no isolation. A channel that routes to the wrong session is harder to debug than a missing channel group.

## Sources

- git config documentation: `git config --help` (local/global/system hierarchy) — HIGH confidence, well-known behavior
- npm .npmrc resolution: npm docs on config files — HIGH confidence, well-known behavior
- ESLint configuration cascade: eslint.org/docs — MEDIUM confidence (ESLint v9 changed flat config; hierarchy behavior is from v8 docs)
- PROJECT.md decisions (local-replaces-global, env var for project dir) — HIGH confidence, authoritative for this project
- server.ts implementation: `DISCORD_STATE_DIR` env var pattern already present — HIGH confidence, read from source

---
*Feature research for: project-scoped configuration — Claude Code Discord channel plugin*
*Researched: 2026-03-23*
