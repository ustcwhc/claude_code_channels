#!/usr/bin/env bash
# discord-local-scoping apply script
# Idempotent — safe to run multiple times. Fires from Claude Code SessionStart hook.
# Applies patches/discord-local-scoping.patch to the discord plugin cache.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="$SCRIPT_DIR/../patches/discord-local-scoping.patch"
SERVER_TS="$HOME/.claude/plugins/cache/claude-plugins-official/discord/0.0.1/server.ts"
MARKER="// discord-local-scoping patch applied"

# Already applied?
if grep -qF "$MARKER" "$SERVER_TS" 2>/dev/null; then
  echo "discord-channel: patch already applied — skipping" >&2
  exit 0
fi

# Patch file present?
if [[ ! -f "$PATCH_FILE" ]]; then
  echo "discord-channel: patch file not found at $PATCH_FILE — skipping" >&2
  exit 0
fi

# Plugin installed?
if [[ ! -f "$SERVER_TS" ]]; then
  echo "discord-channel: server.ts not found — plugin not installed, skipping" >&2
  exit 0
fi

cd "$HOME"
if patch -p0 < "$PATCH_FILE"; then
  echo "discord-channel: local-scoping patch applied successfully" >&2
else
  echo "discord-channel: patch failed — check $PATCH_FILE" >&2
  exit 1
fi
