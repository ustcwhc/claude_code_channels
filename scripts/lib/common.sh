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
AUTO_RESUME_HELPER_PATH="$SCRIPT_DIR/helpers/claude-auto-resume.sh"
ZSHRC_PATH="${ZDOTDIR:-$HOME}/.zshrc"
CLAUDE_BIN_PATH="$HOME/.local/bin/claude"
CLAUDE_BIN_REAL_PATH_FILE="$DISCORD_STATE_DIR/claude-real-binary-path"
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

log_error() {
  if [[ -t 2 ]]; then
    printf '\033[31mdiscord-channel: %s\033[0m\n' "$*" >&2
  else
    echo "discord-channel: $*" >&2
  fi
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

mask_secret() {
  local value="$1"
  local len=${#value}
  if (( len <= 8 )); then
    printf '%s\n' "$value"
  else
    printf '%s***%s\n' "${value:0:4}" "${value: -4}"
  fi
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

  while true; do
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
        return 0
        ;;
      2)
        local shell_openai_key saved_openai_key effective_openai_key key_source
        shell_openai_key="${OPENAI_API_KEY:-}"
        saved_openai_key="$(read_env_var "OPENAI_API_KEY" 2>/dev/null || true)"
        effective_openai_key="$shell_openai_key"
        key_source="shell environment"
        if [[ -z "$effective_openai_key" && -n "$saved_openai_key" ]]; then
          effective_openai_key="$saved_openai_key"
          key_source="$DISCORD_ENV_PATH"
        fi

        if [[ -n "$effective_openai_key" ]]; then
          printf 'Found existing OPENAI_API_KEY from %s: %s\n' "$key_source" "$(mask_secret "$effective_openai_key")" >&2
          printf '  1. Keep existing key (recommended)\n' >&2
          printf '  2. Enter a new key and save it to %s\n' "$DISCORD_ENV_PATH" >&2
          printf '  3. Continue without changing the saved key\n' >&2
          printf '  4. Go back\n' >&2
          printf 'Select [1-4, default 1]: ' >&2

          local key_choice
          IFS= read -r key_choice || return 0
          key_choice="${key_choice:-1}"

          case "$key_choice" in
            1)
              log "install: keeping existing OPENAI_API_KEY from $key_source"
              ;;
            2)
              printf 'Enter new OPENAI_API_KEY to save for Discord transcription: ' >&2
              local openai_key
              IFS= read -r openai_key || true
              if [[ -n "$openai_key" ]]; then
                upsert_env_var "OPENAI_API_KEY" "$openai_key" || return 1
                log "install: saved OPENAI_API_KEY to $DISCORD_ENV_PATH"
              else
                log "install: no new OPENAI_API_KEY entered; keeping existing value"
              fi
              ;;
            3)
              log "install: leaving OPENAI_API_KEY unchanged"
              ;;
            4)
              continue
              ;;
            *)
              log "install: invalid OPENAI_API_KEY selection '$key_choice' - returning to transcription backend menu"
              continue
              ;;
          esac
        else
          printf 'OpenAI API key not found in shell env or %s\n' "$DISCORD_ENV_PATH" >&2
          printf '  1. Enter OPENAI_API_KEY now and save it\n' >&2
          printf '  2. Continue without saving a key\n' >&2
          printf '  3. Go back\n' >&2
          printf 'Select [1-3, default 1]: ' >&2

          local missing_key_choice
          IFS= read -r missing_key_choice || return 0
          missing_key_choice="${missing_key_choice:-1}"

          case "$missing_key_choice" in
            1)
              printf 'Enter OPENAI_API_KEY to save for Discord transcription (leave blank to skip): ' >&2
              local openai_key
              IFS= read -r openai_key || true
              if [[ -n "$openai_key" ]]; then
                upsert_env_var "OPENAI_API_KEY" "$openai_key" || return 1
                log "install: saved OPENAI_API_KEY to $DISCORD_ENV_PATH"
              else
                log "install: OPENAI_API_KEY not saved; OpenAI Whisper backend will require the key in your environment"
              fi
              ;;
            2)
              log "install: OPENAI_API_KEY not saved; OpenAI Whisper backend will require the key in your environment"
              ;;
            3)
              continue
              ;;
            *)
              log "install: invalid OPENAI_API_KEY selection '$missing_key_choice' - returning to transcription backend menu"
              continue
              ;;
          esac
        fi

        upsert_env_var "DISCORD_TRANSCRIBE_BACKEND" "openai-whisper" || return 1
        upsert_env_var "DISCORD_OPENAI_TRANSCRIBE_MODEL" "$current_model" || return 1
        log "install: configured OpenAI Whisper transcription backend (model: $current_model)"
        return 0
        ;;
      3)
        log "install: keeping existing transcription backend ($current_backend)"
        return 0
        ;;
      *)
        log "install: invalid transcription backend selection '$choice' - keeping current setting ($current_backend)"
        return 0
        ;;
    esac
  done
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

register_claude_wrapper() {
  mkdir -p "$(dirname "$ZSHRC_PATH")"
  touch "$ZSHRC_PATH"

  local start_marker="# >>> claude_code_channels auto-resume >>>"
  local end_marker="# <<< claude_code_channels auto-resume <<<"
  local snippet
  snippet="$(cat <<EOF
$start_marker
claude() {
  if [[ -n "\${CLAUDE_CHANNELS_AUTO_RESUME_DISABLE:-}" ]]; then
    command claude "\$@"
    return \$?
  fi

  local helper="$AUTO_RESUME_HELPER_PATH"
  local real_claude
  real_claude="\$(readlink "\$HOME/.local/bin/claude" 2>/dev/null || printf '%s' "\$HOME/.local/bin/claude")"

  if [[ -x "\$helper" ]]; then
    "\$helper" --real-binary "\$real_claude" "\$@"
  else
    command claude "\$@"
  fi
}
$end_marker
EOF
)"

  ZSHRC_PATH="$ZSHRC_PATH" START_MARKER="$start_marker" END_MARKER="$end_marker" SNIPPET="$snippet" run_js '
    const fs = require("fs");
    const path = process.env.ZSHRC_PATH;
    const startMarker = process.env.START_MARKER;
    const endMarker = process.env.END_MARKER;
    const snippet = process.env.SNIPPET;

    const src = fs.existsSync(path) ? fs.readFileSync(path, "utf8") : "";
    const start = src.indexOf(startMarker);
    const end = src.indexOf(endMarker);
    let next = src;

    if (start !== -1 && end !== -1 && end >= start) {
      next = src.slice(0, start) + snippet + src.slice(end + endMarker.length);
    } else {
      next = src.replace(/\s*$/, "");
      if (next.length > 0) next += "\n\n";
      next += snippet + "\n";
    }

    fs.writeFileSync(path, next);
  ' || return 1

  chmod +x "$AUTO_RESUME_HELPER_PATH" 2>/dev/null || true
  log "registered zsh claude auto-resume wrapper in $ZSHRC_PATH"
}

remove_claude_wrapper() {
  [[ -f "$ZSHRC_PATH" ]] || return 0

  local start_marker="# >>> claude_code_channels auto-resume >>>"
  local end_marker="# <<< claude_code_channels auto-resume <<<"

  ZSHRC_PATH="$ZSHRC_PATH" START_MARKER="$start_marker" END_MARKER="$end_marker" run_js '
    const fs = require("fs");
    const path = process.env.ZSHRC_PATH;
    const startMarker = process.env.START_MARKER;
    const endMarker = process.env.END_MARKER;

    const src = fs.readFileSync(path, "utf8");
    const start = src.indexOf(startMarker);
    const end = src.indexOf(endMarker);
    if (start === -1 || end === -1 || end < start) {
      process.exit(0);
    }

    const next = (src.slice(0, start) + src.slice(end + endMarker.length)).replace(/\n{3,}/g, "\n\n");
    fs.writeFileSync(path, next.replace(/\s*$/, "\n"));
  ' || return 1

  log "removed zsh claude auto-resume wrapper from $ZSHRC_PATH"
}

register_claude_binary_wrapper() {
  mkdir -p "$DISCORD_STATE_DIR" "$(dirname "$CLAUDE_BIN_PATH")"

  local real_claude=""
  if [[ -L "$CLAUDE_BIN_PATH" ]]; then
    real_claude="$(readlink "$CLAUDE_BIN_PATH" 2>/dev/null || true)"
  elif [[ -f "$CLAUDE_BIN_REAL_PATH_FILE" ]]; then
    real_claude="$(cat "$CLAUDE_BIN_REAL_PATH_FILE" 2>/dev/null || true)"
  fi

  if [[ -z "$real_claude" || ! -x "$real_claude" ]]; then
    log "skipping binary wrapper registration because real Claude binary could not be resolved"
    return 0
  fi

  printf '%s\n' "$real_claude" > "$CLAUDE_BIN_REAL_PATH_FILE"

  local temp_wrapper
  temp_wrapper="$(mktemp)"
  cat > "$temp_wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail

HELPER="$AUTO_RESUME_HELPER_PATH"
REAL_BINARY="$(cat "$CLAUDE_BIN_REAL_PATH_FILE" 2>/dev/null || printf '%s' "$real_claude")"

if [[ -x "\$HELPER" && -n "\$REAL_BINARY" ]]; then
  exec "\$HELPER" --real-binary "\$REAL_BINARY" "\$@"
fi

exec "$real_claude" "\$@"
EOF

  chmod +x "$temp_wrapper"
  mv "$temp_wrapper" "$CLAUDE_BIN_PATH"
  log "registered claude binary wrapper at $CLAUDE_BIN_PATH"
}

remove_claude_binary_wrapper() {
  local real_claude=""
  if [[ -f "$CLAUDE_BIN_REAL_PATH_FILE" ]]; then
    real_claude="$(cat "$CLAUDE_BIN_REAL_PATH_FILE" 2>/dev/null || true)"
  fi

  if [[ -n "$real_claude" && -x "$real_claude" ]]; then
    rm -f "$CLAUDE_BIN_PATH"
    ln -s "$real_claude" "$CLAUDE_BIN_PATH"
    log "restored Claude binary symlink at $CLAUDE_BIN_PATH"
  fi

  rm -f "$CLAUDE_BIN_REAL_PATH_FILE"
}
