#!/usr/bin/env bash
# Install claude_code_channels: apply patches and register SessionStart hooks.
# Idempotent — safe to run multiple times.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SETTINGS="$HOME/.claude/settings.json"

echo "claude-code-channels: installing..." >&2

# --- 1. Apply the discord patch ---
bash "$SCRIPT_DIR/apply-discord-patch.sh"

# --- 2. Add SessionStart hooks to settings.json ---
if [[ ! -f "$SETTINGS" ]]; then
  # Create minimal settings.json if it doesn't exist
  echo '{}' > "$SETTINGS"
  echo "claude-code-channels: created $SETTINGS" >&2
fi

updated=$(python3 - "$SETTINGS" "$REPO_DIR" <<'PYEOF'
import json, sys

settings_path = sys.argv[1]
repo_dir = sys.argv[2]

with open(settings_path) as f:
    settings = json.load(f)

patch_hook = {
    "type": "command",
    "command": f'bash "{repo_dir}/scripts/apply-discord-patch.sh"',
    "timeout": 15
}
greeting_hook = {
    "type": "command",
    "command": f'bash "{repo_dir}/scripts/discord-session-greeting.sh"',
    "timeout": 10
}

hooks = settings.setdefault('hooks', {})
session_start = hooks.setdefault('SessionStart', [])

# Find the first hook group, or create one
if not session_start:
    session_start.append({"hooks": []})
group = session_start[0]
hook_list = group.setdefault('hooks', [])

# Check if already installed (by matching command substring)
existing_commands = [h.get('command', '') for h in hook_list]
changed = False

if not any('apply-discord-patch.sh' in c for c in existing_commands):
    hook_list.append(patch_hook)
    changed = True

if not any('discord-session-greeting.sh' in c for c in existing_commands):
    hook_list.append(greeting_hook)
    changed = True

if changed:
    print(json.dumps(settings, indent=2))
else:
    sys.exit(1)
PYEOF
) || true

if [[ -n "$updated" ]]; then
  echo "$updated" > "$SETTINGS"
  echo "claude-code-channels: added SessionStart hooks to settings.json" >&2
else
  echo "claude-code-channels: hooks already registered — skipping" >&2
fi

echo "claude-code-channels: install complete" >&2
echo "  Restart Claude Code to pick up changes." >&2
