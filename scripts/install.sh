#!/usr/bin/env bash
# Install claude_code_channels: apply patches and register SessionStart hooks.
# Idempotent — safe to run multiple times.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SETTINGS="$HOME/.claude/settings.json"
PLUGIN_BASE="$HOME/.claude/plugins/cache/claude-plugins-official/discord"

echo "claude-code-channels: installing..." >&2

# --- Pre-flight: check what's already installed ---
patch_was_installed=false
hooks_was_installed=false

# Check if discord patch is already applied
if [[ -d "$PLUGIN_BASE" ]]; then
  LATEST_VERSION=$(ls -1 "$PLUGIN_BASE" 2>/dev/null | sort -V | tail -1)
  if [[ -n "$LATEST_VERSION" ]]; then
    SERVER_TS="$PLUGIN_BASE/$LATEST_VERSION/server.ts"
    MCP_JSON="$PLUGIN_BASE/$LATEST_VERSION/.mcp.json"
    SKILL_MD="$PLUGIN_BASE/$LATEST_VERSION/skills/access/SKILL.md"
    all_patched=true
    grep -qF "discord-local-scoping patch applied" "$SERVER_TS" 2>/dev/null || all_patched=false
    grep -qF "DISCORD_PROJECT_DIR" "$MCP_JSON" 2>/dev/null || all_patched=false
    grep -qF "## Scope resolution" "$SKILL_MD" 2>/dev/null || all_patched=false
    grep -qF "quote-reply context patch applied" "$SERVER_TS" 2>/dev/null || all_patched=false
    $all_patched && patch_was_installed=true
  fi
fi

# Check if hooks are already registered
if [[ -f "$SETTINGS" ]]; then
  hooks_was_installed=$(python3 -c "
import json, sys
try:
    with open('$SETTINGS') as f:
        settings = json.load(f)
    hooks = settings.get('hooks', {})
    for group in hooks.get('SessionStart', []):
        for h in group.get('hooks', []):
            if 'apply-discord-patch.sh' in h.get('command', ''):
                print('true')
                sys.exit(0)
except Exception:
    pass
print('false')
" 2>/dev/null) || hooks_was_installed=false
fi

if $patch_was_installed && [[ "$hooks_was_installed" == "true" ]]; then
  echo "claude-code-channels: already installed" >&2
  exit 0
fi

# --- 1. Apply the discord patch ---
patch_installed_now=false
if $patch_was_installed; then
  echo "claude-code-channels: discord patch — already installed" >&2
else
  bash "$SCRIPT_DIR/apply-discord-patch.sh"
  patch_installed_now=true
  echo "claude-code-channels: discord patch — installed" >&2
fi

# --- 2. Add SessionStart hooks to settings.json ---
hooks_installed_now=false
if [[ "$hooks_was_installed" == "true" ]]; then
  echo "claude-code-channels: SessionStart hooks — already installed" >&2
else
  if [[ ! -f "$SETTINGS" ]]; then
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

hooks = settings.setdefault('hooks', {})
session_start = hooks.setdefault('SessionStart', [])

# Remove legacy greeting hook if present (greeting now handled by server.ts)
for group in session_start:
    hook_list = group.get('hooks', [])
    group['hooks'] = [
        h for h in hook_list
        if 'discord-session-greeting.sh' not in h.get('command', '')
    ]

# Add to first group, or create one
if not session_start:
    session_start.append({"hooks": []})
hook_list = session_start[0].setdefault('hooks', [])
hook_list.append(patch_hook)

print(json.dumps(settings, indent=2))
PYEOF
  ) && python_exit=0 || python_exit=$?

  if [[ $python_exit -eq 2 ]]; then
    echo "claude-code-channels: ERROR — failed to parse $SETTINGS" >&2
    exit 1
  elif [[ -n "$updated" ]]; then
    echo "$updated" > "$SETTINGS"
    hooks_installed_now=true
    echo "claude-code-channels: SessionStart hooks — installed" >&2
  fi
fi

echo "claude-code-channels: install complete" >&2
echo "  Restart Claude Code to pick up changes." >&2
