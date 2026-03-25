#!/usr/bin/env bash
# discord-local-scoping apply script
# Idempotent — safe to run multiple times. Fires from Claude Code SessionStart hook.
# Applies local-scoping changes to the discord plugin cache (latest version).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_BASE="$HOME/.claude/plugins/cache/claude-plugins-official/discord"

# Find the latest plugin version directory
if [[ ! -d "$PLUGIN_BASE" ]]; then
  echo "discord-channel: plugin not installed — skipping" >&2
  exit 0
fi

LATEST_VERSION=$(ls -1 "$PLUGIN_BASE" | sort -V | tail -1)
if [[ -z "$LATEST_VERSION" ]]; then
  echo "discord-channel: no plugin versions found — skipping" >&2
  exit 0
fi

PLUGIN_DIR="$PLUGIN_BASE/$LATEST_VERSION"
SERVER_TS="$PLUGIN_DIR/server.ts"
MCP_JSON="$PLUGIN_DIR/.mcp.json"
SKILL_MD="$PLUGIN_DIR/skills/access/SKILL.md"

MARKER="// discord-local-scoping patch applied"
SKILL_MARKER="## Scope resolution"
MCP_MARKER="DISCORD_PROJECT_DIR"

# Check what's already applied
server_patched=false
mcp_patched=false
skill_patched=false
grep -qF "$MARKER" "$SERVER_TS" 2>/dev/null && server_patched=true
grep -qF "$MCP_MARKER" "$MCP_JSON" 2>/dev/null && mcp_patched=true
grep -qF "$SKILL_MARKER" "$SKILL_MD" 2>/dev/null && skill_patched=true

if $server_patched && $mcp_patched && $skill_patched; then
  echo "discord-channel: patch already applied to $LATEST_VERSION — skipping" >&2
  exit 0
fi

echo "discord-channel: applying local-scoping patch to $LATEST_VERSION..." >&2

# Apply server.ts changes if needed
if ! $server_patched && [[ -f "$SERVER_TS" ]]; then
  # Inject resolveAccessFile() after the STATE_DIR/ACCESS_FILE/APPROVED_DIR/ENV_FILE block
  # We use a bun script for reliable insertion since patch files break across versions
  bun -e "
    const fs = require('fs');
    let src = fs.readFileSync('$SERVER_TS', 'utf8');

    // Add dirname import
    if (!src.includes('dirname')) {
      src = src.replace(
        /import \{ join, sep \} from 'path'/,
        \"import { join, sep, dirname } from 'path'\"
      );
    }

    // Insert resolveAccessFile after ENV_FILE line
    const insertAfter = \"const ENV_FILE = join(STATE_DIR, '.env')\";
    if (!src.includes(insertAfter)) {
      process.stderr.write('discord-channel: could not find ENV_FILE anchor in server.ts — skipping server.ts patch\n');
      process.exit(0);
    }
    const resolveBlock = \`

// discord-local-scoping patch applied
// Project dir: injected via sh wrapper in .mcp.json that captures \\\$PWD before --cwd changes it.
const PROJECT_DIR = process.env.DISCORD_PROJECT_DIR || undefined

function resolveAccessFile() {
  if (PROJECT_DIR) {
    const candidate = join(PROJECT_DIR, '.claude', 'channels', 'discord', 'access.json')
    try {
      statSync(candidate)
      return { path: candidate, scope: 'local' }
    } catch (e) {
      if (e.code !== 'ENOENT') {
        process.stderr.write('discord channel: error checking local access.json: ' + e + '\\\\n')
      }
    }
  }
  return { path: ACCESS_FILE, scope: 'global' }
}

const { path: ACTIVE_ACCESS_FILE, scope: ACTIVE_SCOPE } = resolveAccessFile()
if (ACTIVE_SCOPE === 'local') {
  process.stderr.write('discord channel: using local config ' + ACTIVE_ACCESS_FILE + '\\\\n')
} else {
  process.stderr.write('discord channel: using global config ' + ACTIVE_ACCESS_FILE + '\\\\n')
}
\`;
    src = src.replace(insertAfter, insertAfter + resolveBlock);

    // Replace ACCESS_FILE with ACTIVE_ACCESS_FILE in readAccessFile
    src = src.replace(
      /const raw = readFileSync\(ACCESS_FILE,/,
      'const raw = readFileSync(ACTIVE_ACCESS_FILE,'
    );

    // Add corrupt-local handling
    src = src.replace(
      /try \{ renameSync\(ACCESS_FILE,/,
      \"if (typeof ACTIVE_SCOPE !== 'undefined' && ACTIVE_SCOPE === 'local') { process.stderr.write('discord channel: local access.json is corrupt — fix or delete ' + ACTIVE_ACCESS_FILE + '\\\\\\\\n'); process.exit(1); }\\n    try { renameSync(ACTIVE_ACCESS_FILE,\"
    );

    // Replace in saveAccess
    src = src.replace(
      /mkdirSync\(STATE_DIR, \{ recursive: true/,
      'mkdirSync(dirname(ACTIVE_ACCESS_FILE), { recursive: true'
    );
    src = src.replace(
      /const tmp = ACCESS_FILE \+ '\.tmp'/,
      \"const tmp = ACTIVE_ACCESS_FILE + '.tmp'\"
    );
    src = src.replace(
      /renameSync\(tmp, ACCESS_FILE\)/,
      'renameSync(tmp, ACTIVE_ACCESS_FILE)'
    );

    fs.writeFileSync('$SERVER_TS', src);
  "
  echo "discord-channel: server.ts patched" >&2
fi

# Apply .mcp.json changes if needed
if ! $mcp_patched && [[ -f "$MCP_JSON" ]]; then
  bun -e "
    const fs = require('fs');
    const mcp = JSON.parse(fs.readFileSync('$MCP_JSON', 'utf8'));
    const discord = mcp.mcpServers.discord;
    // Use sh wrapper to capture PWD before --cwd changes it
    const pluginRoot = '\${CLAUDE_PLUGIN_ROOT}';
    discord.command = 'sh';
    discord.args = ['-c', 'DISCORD_PROJECT_DIR=\$PWD exec bun run --cwd \\'' + pluginRoot + '\\' --shell=bun --silent start'];
    delete discord.env;
    fs.writeFileSync('$MCP_JSON', JSON.stringify(mcp, null, 2) + '\\n');
  "
  echo "discord-channel: .mcp.json patched" >&2
fi

# Apply SKILL.md changes if needed — copy full patched version from repo
if ! $skill_patched && [[ -f "$SKILL_MD" ]]; then
  PATCHED_SKILL="$REPO_DIR/patches/SKILL.md"
  if [[ -f "$PATCHED_SKILL" ]]; then
    cp "$PATCHED_SKILL" "$SKILL_MD"
    echo "discord-channel: SKILL.md patched" >&2
  else
    echo "discord-channel: patches/SKILL.md not found in repo — skipping SKILL.md patch" >&2
  fi
fi

echo "discord-channel: patch complete for version $LATEST_VERSION" >&2
