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
REPLY_MARKER="// quote-reply context patch applied"

# Check what's already applied
server_patched=false
mcp_patched=false
skill_patched=false
reply_patched=false
grep -qF "$MARKER" "$SERVER_TS" 2>/dev/null && server_patched=true
grep -qF "$MCP_MARKER" "$MCP_JSON" 2>/dev/null && mcp_patched=true
grep -qF "$SKILL_MARKER" "$SKILL_MD" 2>/dev/null && skill_patched=true
grep -qF "$REPLY_MARKER" "$SERVER_TS" 2>/dev/null && reply_patched=true

if $server_patched && $mcp_patched && $skill_patched && $reply_patched; then
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
// Project dir: injected via .mcp.json env block using CLAUDE_PROJECT_DIR variable substitution.
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

    // Log listening channels on ready and send greeting
    src = src.replace(
      /client\.once\('ready', c => \{\s*\n\s*process\.stderr\.write\(\`discord channel: gateway connected as \$\{c\.user\.tag\}\\\\n\`\)\s*\n\s*\}\)/,
      \`client.once('ready', async c => {
  process.stderr.write(\\\`discord channel: gateway connected as \\\${c.user.tag}\\\\n\\\`)
  const access = loadAccess()
  const groupIds = Object.keys(access.groups)
  if (groupIds.length > 0) {
    process.stderr.write(\\\`discord channel: listening to \\\${groupIds.length} channel(s): \\\${groupIds.join(', ')}\\\\n\\\`)
    const projectName = PROJECT_DIR ? PROJECT_DIR.split('/').pop() : 'unknown project'
    for (const id of groupIds) {
      try {
        const ch = await client.channels.fetch(id)
        if (ch && ch.isTextBased() && 'send' in ch) {
          await (ch as any).send(\\\`session started — listening on **\\\${projectName}**\\\`)
        }
      } catch (e) {
        process.stderr.write(\\\`discord channel: failed to greet \\\${id}: \\\${e}\\\\n\\\`)
      }
    }
  } else {
    process.stderr.write(\\\`discord channel: no group channels configured\\\\n\\\`)
  }
})\`
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
    // Use CLAUDE_PROJECT_DIR env var substitution — Claude Code expands this
    // before launching the process, so it's reliable regardless of cwd changes.
    discord.command = 'bun';
    discord.args = ['run', '--cwd', '\${CLAUDE_PLUGIN_ROOT}', '--shell=bun', '--silent', 'start'];
    discord.env = { DISCORD_PROJECT_DIR: '\${CLAUDE_PROJECT_DIR}' };
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

# Apply quote-reply context patch — includes referenced message content in notifications
if ! $reply_patched && [[ -f "$SERVER_TS" ]]; then
  bun -e "
    const fs = require('fs');
    let src = fs.readFileSync('$SERVER_TS', 'utf8');

    // Find the notification block in handleInbound and inject referenced message fetching before it.
    // We look for the 'mcp.notification({' call that sends 'notifications/claude/channel'
    // and wrap it with logic to fetch the referenced message.

    const anchor = \"  mcp.notification({\\n    method: 'notifications/claude/channel',\";
    if (!src.includes(anchor)) {
      // Try alternate spacing
      const anchor2 = \"mcp.notification({\\n    method: 'notifications/claude/channel',\";
      if (!src.includes(anchor2)) {
        process.stderr.write('discord-channel: could not find notification anchor for quote-reply patch — skipping\\n');
        process.exit(0);
      }
    }

    // Replace the notification section to add referenced message context.
    // The original code (around the notification call):
    //   const content = msg.content || (atts.length > 0 ? '(attachment)' : '')
    //   mcp.notification({ method: 'notifications/claude/channel', params: { content, meta: { ... } } })
    //
    // We inject code between content assignment and the notification to:
    // 1. Check msg.reference for a quoted message
    // 2. Fetch the referenced message content
    // 3. Add reply_to_id, reply_to_user, reply_to_content to meta

    const oldContentLine = \"const content = msg.content || (atts.length > 0 ? '(attachment)' : '')\";
    if (!src.includes(oldContentLine)) {
      process.stderr.write('discord-channel: could not find content assignment for quote-reply patch — skipping\\n');
      process.exit(0);
    }

    // Make handleInbound async-aware for the referenced message fetch
    // and add the reply context fields to meta
    const newBlock = oldContentLine + \`

  // quote-reply context patch applied
  // When the user quote-replies to a message, fetch the referenced message
  // and include its content in the notification metadata.
  let reply_to_id = undefined
  let reply_to_user = undefined
  let reply_to_content = undefined
  if (msg.reference && msg.reference.messageId) {
    try {
      const refMsg = await msg.channel.messages.fetch(msg.reference.messageId)
      reply_to_id = refMsg.id
      reply_to_user = refMsg.author.username
      const preview = refMsg.content.length > 500 ? refMsg.content.slice(0, 500) + '...' : refMsg.content
      reply_to_content = preview
    } catch (e) {
      process.stderr.write('discord channel: failed to fetch referenced message: ' + e + '\\\\n')
    }
  }
\`;

    src = src.replace(oldContentLine, newBlock);

    // Now add the reply fields to the meta object in the notification
    const oldMeta = \"...(atts.length > 0 ? { attachment_count: String(atts.length), attachments: atts.join('; ') } : {}),\";
    if (src.includes(oldMeta)) {
      src = src.replace(
        oldMeta,
        oldMeta + \`
        ...(reply_to_id ? { reply_to_id, reply_to_user, reply_to_content } : {}),\`
      );
    } else {
      process.stderr.write('discord-channel: could not find meta spread for reply fields — reply context will not be included\\n');
    }

    fs.writeFileSync('$SERVER_TS', src);
  "
  echo "discord-channel: quote-reply context patched" >&2
fi

echo "discord-channel: patch complete for version $LATEST_VERSION" >&2
