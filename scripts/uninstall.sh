#!/usr/bin/env bash
# Uninstall claude_code_channels patches.
# Removes patched plugin files (Claude Code re-downloads clean copies on next start)
# and removes the SessionStart hooks from ~/.claude/settings.json.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_BASE="$HOME/.claude/plugins/cache/claude-plugins-official/discord"
SETTINGS="$HOME/.claude/settings.json"

echo "claude-code-channels: uninstalling..." >&2

# --- 1. Remove patched plugin version directories ---
if [[ -d "$PLUGIN_BASE" ]]; then
  for version_dir in "$PLUGIN_BASE"/*/; do
    [[ -d "$version_dir" ]] || continue
    server_ts="$version_dir/server.ts"
    if grep -qF "discord-local-scoping patch applied" "$server_ts" 2>/dev/null; then
      version=$(basename "$version_dir")
      rm -rf "$version_dir"
      echo "claude-code-channels: removed patched plugin version $version" >&2
      echo "  (Claude Code will re-download a clean copy on next start with --channels)" >&2
    fi
  done
else
  echo "claude-code-channels: plugin not installed — nothing to remove" >&2
fi

# --- 2. Remove SessionStart hooks from settings.json ---
if [[ -f "$SETTINGS" ]]; then
  # Remove hook entries that reference this repo's scripts
  updated=$(python3 -c "
import json, sys

with open('$SETTINGS') as f:
    settings = json.load(f)

repo_dir = '$REPO_DIR'
changed = False

session_start = settings.get('hooks', {}).get('SessionStart', [])
for group in session_start:
    hooks = group.get('hooks', [])
    original_len = len(hooks)
    group['hooks'] = [
        h for h in hooks
        if repo_dir not in h.get('command', '')
    ]
    if len(group['hooks']) != original_len:
        changed = True

# Remove empty hook groups
settings['hooks']['SessionStart'] = [
    g for g in session_start if g.get('hooks')
]
# Remove empty SessionStart if no groups left
if not settings['hooks']['SessionStart']:
    del settings['hooks']['SessionStart']

if changed:
    print(json.dumps(settings, indent=2))
else:
    sys.exit(1)
" 2>/dev/null)

  if [[ $? -eq 0 && -n "$updated" ]]; then
    echo "$updated" > "$SETTINGS"
    echo "claude-code-channels: removed SessionStart hooks from settings.json" >&2
  else
    echo "claude-code-channels: no hooks found in settings.json — skipping" >&2
  fi
else
  echo "claude-code-channels: settings.json not found — skipping" >&2
fi

echo "claude-code-channels: uninstall complete" >&2
echo "  Restart Claude Code to pick up changes." >&2
echo "  Project-local access.json files (if any) are left in place." >&2
