#!/usr/bin/env bash

set -euo pipefail

REAL_BINARY=""
ARGS=()
CHANNELS_DISCORD_ENABLED=false

while (($# > 0)); do
  case "$1" in
    --real-binary)
      REAL_BINARY="${2:-}"
      shift 2
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$REAL_BINARY" ]]; then
  echo "claude-auto-resume: missing --real-binary" >&2
  exit 1
fi

should_auto_resume=false
has_explicit_resume=false

for arg in "${ARGS[@]}"; do
  case "$arg" in
    --channels)
      should_auto_resume=true
      ;;
    plugin:discord@claude-plugins-official)
      CHANNELS_DISCORD_ENABLED=true
      ;;
    --resume|-r|--continue|-c|--session-id)
      has_explicit_resume=true
      ;;
  esac
done

if [[ "$should_auto_resume" != true || "$has_explicit_resume" == true ]]; then
  if [[ "$should_auto_resume" == true ]]; then
    cwd="$(pwd -P)"
    DISCORD_PROJECT_DIR="$cwd" exec "$REAL_BINARY" "${ARGS[@]}"
  fi
  exec "$REAL_BINARY" "${ARGS[@]}"
fi

case "${ARGS[0]:-}" in
  agents|auth|auto-mode|doctor|install|mcp|plugin|plugins|setup-token|update|upgrade)
    cwd="$(pwd -P)"
    DISCORD_PROJECT_DIR="$cwd" exec "$REAL_BINARY" "${ARGS[@]}"
    ;;
esac

cwd="$(pwd -P)"
project_key="$(printf '%s' "$cwd" | sed 's/[^[:alnum:]]/-/g')"
session_dir="$HOME/.claude/projects/$project_key"

latest_session_id=""
latest_mtime=0

if [[ -d "$session_dir" ]]; then
  shopt -s nullglob
  session_files=("$session_dir"/*.jsonl)
  shopt -u nullglob

  for session_file in "${session_files[@]}"; do
    session_id="$(basename "$session_file" .jsonl)"
    if [[ ! "$session_id" =~ ^[0-9a-fA-F-]{36}$ ]]; then
      continue
    fi

    mtime="$(stat -f %m "$session_file" 2>/dev/null || echo 0)"
    if (( mtime > latest_mtime )); then
      latest_mtime="$mtime"
      latest_session_id="$session_id"
    fi
  done
fi

if [[ -n "$latest_session_id" ]]; then
  echo "claude-auto-resume: resuming latest session $latest_session_id for $cwd" >&2
  DISCORD_PROJECT_DIR="$cwd" \
  DISCORD_RESUMED_SESSION_ID="$latest_session_id" \
  DISCORD_AUTO_RESUMED=1 \
  exec "$REAL_BINARY" --resume "$latest_session_id" "${ARGS[@]}"
fi

DISCORD_PROJECT_DIR="$cwd" exec "$REAL_BINARY" "${ARGS[@]}"
