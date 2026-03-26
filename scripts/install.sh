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

try:
    with open(settings_path) as f:
        settings = json.load(f)
except (json.JSONDecodeError, OSError) as e:
    print(f"PARSE_ERROR: {e}", file=sys.stderr)
    sys.exit(2)

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

# Check across ALL hook groups for existing entries (mirrors uninstall.sh)
all_commands = []
for group in session_start:
    all_commands.extend(h.get('command', '') for h in group.get('hooks', []))

has_patch = any('apply-discord-patch.sh' in c for c in all_commands)
has_greeting = any('discord-session-greeting.sh' in c for c in all_commands)

if has_patch and has_greeting:
    # Already fully installed — signal no-change with empty output
    sys.exit(0)

# Add to first group, or create one
if not session_start:
    session_start.append({"hooks": []})
hook_list = session_start[0].setdefault('hooks', [])

if not has_patch:
    hook_list.append(patch_hook)
if not has_greeting:
    hook_list.append(greeting_hook)

print(json.dumps(settings, indent=2))
PYEOF
) && python_exit=0 || python_exit=$?

if [[ $python_exit -eq 2 ]]; then
  echo "claude-code-channels: ERROR — failed to parse $SETTINGS" >&2
  exit 1
elif [[ -n "$updated" ]]; then
  echo "$updated" > "$SETTINGS"
  echo "claude-code-channels: added SessionStart hooks to settings.json" >&2
else
  echo "claude-code-channels: hooks already registered — skipping" >&2
fi

echo "claude-code-channels: install complete" >&2
echo "  Restart Claude Code to pick up changes." >&2
