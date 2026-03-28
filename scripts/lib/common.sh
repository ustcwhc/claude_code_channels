#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_BASE="$HOME/.claude/plugins/cache/claude-plugins-official/discord"
MARKETPLACE_PLUGIN_DIR="$HOME/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/discord"
SETTINGS_PATH="$HOME/.claude/settings.json"
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
