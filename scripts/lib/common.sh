#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_BASE="$HOME/.claude/plugins/cache/claude-plugins-official/discord"
MARKETPLACE_PLUGIN_DIR="$HOME/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/discord"
SETTINGS_PATH="$HOME/.claude/settings.json"
DISCORD_STATE_DIR="${DISCORD_STATE_DIR:-$HOME/.claude/channels/discord}"
DISCORD_ENV_PATH="$DISCORD_STATE_DIR/.env"
INSTALL_SCRIPT_PATH="$SCRIPT_DIR/install.sh"
HOOK_TIMEOUT=15
BACKUP_SUFFIX=".claude-code-channels.orig"
PLUGIN_DIR=""
PLUGIN_TARGETS=()
JS_RUNTIME="${BUN_PATH:-}"

if [[ -z "$JS_RUNTIME" ]]; then
  if command -v bun >/dev/null 2>&1; then
    JS_RUNTIME="$(command -v bun)"
  elif command -v node >/dev/null 2>&1; then
    JS_RUNTIME="$(command -v node)"
  else
    JS_RUNTIME=""
  fi
fi

log() {
  echo "discord-channel: $*" >&2
}

run_js() {
  local code="$1"
  if [[ -z "$JS_RUNTIME" ]]; then
    log "neither bun nor node is available on PATH"
    return 127
  fi
  "$JS_RUNTIME" -e "$code"
}

ensure_plugin_targets() {
  PLUGIN_TARGETS=()

  if [[ -d "$PLUGIN_BASE" ]]; then
    local latest_version
    latest_version="$(ls -1 "$PLUGIN_BASE" 2>/dev/null | sort -V | tail -1)"
    if [[ -n "$latest_version" && -d "$PLUGIN_BASE/$latest_version" ]]; then
      PLUGIN_TARGETS+=( "$PLUGIN_BASE/$latest_version" )
    fi
  fi

  if [[ -d "$MARKETPLACE_PLUGIN_DIR" ]]; then
    PLUGIN_TARGETS+=( "$MARKETPLACE_PLUGIN_DIR" )
  fi

  if [[ "${#PLUGIN_TARGETS[@]}" -eq 0 ]]; then
    log "no Discord plugin target found in cache or marketplace checkout - skipping"
    return 1
  fi

  PLUGIN_DIR="${PLUGIN_TARGETS[0]}"
  return 0
}

backup_file() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  if [[ ! -f "${file}${BACKUP_SUFFIX}" ]]; then
    cp "$file" "${file}${BACKUP_SUFFIX}"
  fi
}

restore_file() {
  local file="$1"
  if [[ -f "${file}${BACKUP_SUFFIX}" ]]; then
    cp "${file}${BACKUP_SUFFIX}" "$file"
    rm -f "${file}${BACKUP_SUFFIX}"
    return 0
  fi
  return 1
}

remove_backup() {
  local file="$1"
  rm -f "${file}${BACKUP_SUFFIX}"
}

read_env_var() {
  local key="$1"
  [[ -f "$DISCORD_ENV_PATH" ]] || return 1
  awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1) }' "$DISCORD_ENV_PATH" | tail -1
}

upsert_env_var() {
  local key="$1"
  local value="$2"

  mkdir -p "$DISCORD_STATE_DIR"
  touch "$DISCORD_ENV_PATH"
  chmod 600 "$DISCORD_ENV_PATH" 2>/dev/null || true

  DISCORD_ENV_PATH="$DISCORD_ENV_PATH" ENV_KEY="$key" ENV_VALUE="$value" run_js '
    const fs = require("fs");
    const envPath = process.env.DISCORD_ENV_PATH;
    const key = process.env.ENV_KEY;
    const value = process.env.ENV_VALUE ?? "";

    const lines = fs.existsSync(envPath) ? fs.readFileSync(envPath, "utf8").split("\n").filter(Boolean) : [];
    const filtered = lines.filter(line => !line.startsWith(`${key}=`));
    filtered.push(`${key}=${value}`);
    fs.writeFileSync(envPath, filtered.join("\n") + "\n", { mode: 0o600 });
  ' || return 1
}

configure_transcription_backend() {
  [[ -t 0 && -t 1 ]] || return 0

  local current_backend
  current_backend="$(read_env_var "DISCORD_TRANSCRIBE_BACKEND" 2>/dev/null || true)"
  local current_model
  current_model="$(read_env_var "DISCORD_OPENAI_TRANSCRIBE_MODEL" 2>/dev/null || true)"
  [[ -n "$current_backend" ]] || current_backend="local"
  [[ -n "$current_model" ]] || current_model="whisper-1"

  log "install: choose transcription backend"
  printf '  1. Local whisper-cli (current: %s)\n' "$([[ "$current_backend" == "local" ]] && echo "selected" || echo "not selected")" >&2
  printf '  2. OpenAI Whisper API (better multilingual support) (current: %s)\n' "$([[ "$current_backend" == "openai-whisper" ]] && echo "selected" || echo "not selected")" >&2
  printf '  3. Keep current setting (%s)\n' "$current_backend" >&2
  printf 'Select [1-3, default 3]: ' >&2

  local choice
  IFS= read -r choice || return 0
  choice="${choice:-3}"

  case "$choice" in
    1)
      upsert_env_var "DISCORD_TRANSCRIBE_BACKEND" "local" || return 1
      log "install: configured local whisper-cli transcription backend"
      ;;
    2)
      upsert_env_var "DISCORD_TRANSCRIBE_BACKEND" "openai-whisper" || return 1
      upsert_env_var "DISCORD_OPENAI_TRANSCRIBE_MODEL" "$current_model" || return 1

      if [[ -z "${OPENAI_API_KEY:-}" ]] && [[ -z "$(read_env_var "OPENAI_API_KEY" 2>/dev/null || true)" ]]; then
        printf 'OpenAI API key not found in shell env or %s\n' "$DISCORD_ENV_PATH" >&2
        printf 'Enter OPENAI_API_KEY to save for Discord transcription (leave blank to skip): ' >&2
        local openai_key
        IFS= read -r openai_key || true
        if [[ -n "$openai_key" ]]; then
          upsert_env_var "OPENAI_API_KEY" "$openai_key" || return 1
          log "install: saved OPENAI_API_KEY to $DISCORD_ENV_PATH"
        else
          log "install: OPENAI_API_KEY not saved; OpenAI Whisper backend will require the key in your environment"
        fi
      fi

      log "install: configured OpenAI Whisper transcription backend (model: $current_model)"
      ;;
    3)
      log "install: keeping existing transcription backend ($current_backend)"
      ;;
    *)
      log "install: invalid transcription backend selection '$choice' - keeping current setting ($current_backend)"
      ;;
  esac
}

register_session_hook() {
  mkdir -p "$(dirname "$SETTINGS_PATH")"

  local temp_settings
  temp_settings="$(mktemp)"

  if [[ -f "$SETTINGS_PATH" ]]; then
    cp "$SETTINGS_PATH" "$temp_settings"
  else
    printf '{\n  "hooks": {}\n}\n' > "$temp_settings"
  fi

  SETTINGS_INPUT="$temp_settings" INSTALL_SCRIPT_PATH="$INSTALL_SCRIPT_PATH" HOOK_TIMEOUT="$HOOK_TIMEOUT" run_js '
    const fs = require("fs");
    const path = process.env.SETTINGS_INPUT;
    const installScriptPath = process.env.INSTALL_SCRIPT_PATH;
    const timeout = Number(process.env.HOOK_TIMEOUT);

    let settings = {};
    try {
      settings = JSON.parse(fs.readFileSync(path, "utf8"));
    } catch (err) {
      process.stderr.write(`discord-channel: failed to parse ${path}: ${err}\n`);
      process.exit(1);
    }

    settings.hooks ??= {};
    settings.hooks.SessionStart ??= [{ hooks: [] }];
    const sessionStart = Array.isArray(settings.hooks.SessionStart) ? settings.hooks.SessionStart : [{ hooks: [] }];
    if (sessionStart.length === 0) sessionStart.push({ hooks: [] });
    sessionStart[0].hooks ??= [];

    const command = `bash "${installScriptPath}"`;
    const hooks = sessionStart[0].hooks.filter(hook => !String(hook.command ?? "").includes("claude_code_channels/scripts/install.sh") && !String(hook.command ?? "").includes("claude_code_channels/scripts/apply-discord-patch.sh"));
    hooks.push({ type: "command", command, timeout });
    sessionStart[0].hooks = hooks;
    settings.hooks.SessionStart = sessionStart;

    fs.writeFileSync(path, JSON.stringify(settings, null, 2) + "\n");
  ' || return 1

  mv "$temp_settings" "$SETTINGS_PATH"
  log "registered SessionStart hook in $SETTINGS_PATH"
}

remove_session_hook() {
  [[ -f "$SETTINGS_PATH" ]] || return 0

  local temp_settings
  temp_settings="$(mktemp)"
  cp "$SETTINGS_PATH" "$temp_settings"

  SETTINGS_INPUT="$temp_settings" run_js '
    const fs = require("fs");
    const path = process.env.SETTINGS_INPUT;

    let settings = {};
    try {
      settings = JSON.parse(fs.readFileSync(path, "utf8"));
    } catch (err) {
      process.stderr.write(`discord-channel: failed to parse ${path}: ${err}\n`);
      process.exit(1);
    }

    const sessionStart = settings.hooks?.SessionStart;
    if (!Array.isArray(sessionStart) || sessionStart.length === 0) {
      fs.writeFileSync(path, JSON.stringify(settings, null, 2) + "\n");
      process.exit(0);
    }

    for (const block of sessionStart) {
      if (!Array.isArray(block.hooks)) continue;
      block.hooks = block.hooks.filter(hook => !String(hook.command ?? "").includes("claude_code_channels/scripts/install.sh") && !String(hook.command ?? "").includes("claude_code_channels/scripts/apply-discord-patch.sh"));
    }

    fs.writeFileSync(path, JSON.stringify(settings, null, 2) + "\n");
  ' || return 1

  mv "$temp_settings" "$SETTINGS_PATH"
  log "removed SessionStart hook from $SETTINGS_PATH"
}
