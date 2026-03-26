#!/usr/bin/env bash
# Sends a greeting message to configured Discord channels on session start.
# Reads the active access.json (local if present, else global) and posts
# via Discord REST API using the bot token from ~/.claude/channels/discord/.env

set -euo pipefail

ENV_FILE="$HOME/.claude/channels/discord/.env"
GLOBAL_ACCESS="$HOME/.claude/channels/discord/access.json"

# Load bot token — sources a user-owned file in ~/.claude/ (trusted path)
if [[ ! -f "$ENV_FILE" ]]; then
  exit 0
fi
source "$ENV_FILE"
TOKEN="${DISCORD_BOT_TOKEN:-}"
if [[ -z "$TOKEN" ]]; then
  exit 0
fi

# Resolve access.json: local overrides global
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
ACCESS_FILE="$GLOBAL_ACCESS"
if [[ -n "$PROJECT_DIR" && -f "$PROJECT_DIR/.claude/channels/discord/access.json" ]]; then
  ACCESS_FILE="$PROJECT_DIR/.claude/channels/discord/access.json"
fi

if [[ ! -f "$ACCESS_FILE" ]]; then
  exit 0
fi

# Extract channel IDs from groups keys
CHANNEL_IDS=$(python3 -c "
import json, sys
with open('$ACCESS_FILE') as f:
    data = json.load(f)
for ch_id in data.get('groups', {}):
    print(ch_id)
" 2>/dev/null) || exit 0

if [[ -z "$CHANNEL_IDS" ]]; then
  exit 0
fi

# Derive project name from directory
if [[ -n "$PROJECT_DIR" ]]; then
  PROJECT_NAME="$(basename "$PROJECT_DIR")"
else
  PROJECT_NAME="unknown project"
fi

# Build JSON payload safely using jq to avoid injection from dir names
PAYLOAD=$(jq -nc --arg c "session started — listening on **${PROJECT_NAME}**" '{content: $c}')

# Send greeting to each channel — bounded delay per call, no orphan processes
while IFS= read -r CHANNEL_ID; do
  timeout 5 curl -sf -X POST \
    "https://discord.com/api/v10/channels/$CHANNEL_ID/messages" \
    -H "Authorization: Bot $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    >/dev/null 2>&1 || true
done <<< "$CHANNEL_IDS"
