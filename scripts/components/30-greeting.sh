#!/usr/bin/env bash

apply() {
  local plugin_dir="$1"
  local server_ts="$plugin_dir/server.ts"
  local marker_start="// --- claude-code-channels: greeting start ---"

  [[ -f "$server_ts" ]] || return 3
  grep -qF "$marker_start" "$server_ts" 2>/dev/null && return 2
  [[ -f "${server_ts}${BACKUP_SUFFIX}" ]] || return 3

  SERVER_TS="$server_ts" run_js '
    const fs = require("fs");
    const serverPath = process.env.SERVER_TS;
    let src = fs.readFileSync(serverPath, "utf8");

    const readyAnchor = "client.once('\''ready'\'', c => {\n  process.stderr.write(`discord channel: gateway connected as ${c.user.tag}\\n`)\n})";
    if (!src.includes(readyAnchor)) {
      process.stderr.write("discord-channel: ready anchor not found in server.ts\n");
      process.exit(3);
    }

    const greetingBlock = `

// --- claude-code-channels: greeting start ---
function startupChannelIds(): string[] {
  return Object.keys(loadAccess().groups ?? {})
}

async function sendStartupGreeting(): Promise<void> {
  const channelIds = startupChannelIds()
  if (channelIds.length === 0) {
    process.stderr.write('\''discord channel: no configured channel ids for this session\\n'\'')
    return
  }

  process.stderr.write(\`discord channel: connected channel ids \${channelIds.join(", ")}\\n\`)
  const projectName = PROJECT_DIR ? basename(PROJECT_DIR) : undefined
  const greeting = projectName
    ? \`Claude Code session connected (project: \${projectName})\`
    : '\''Claude Code session connected'\''

  for (const channelId of channelIds) {
    try {
      const channel = await fetchTextChannel(channelId)
      if ('\''send'\'' in channel) {
        await channel.send(greeting)
      }
      process.stderr.write(\`discord channel: startup greeting sent to \${channelId}\\n\`)
    } catch (err) {
      process.stderr.write(\`discord channel: failed to send startup greeting to \${channelId}: \${err}\\n\`)
    }
  }
}
// --- claude-code-channels: greeting end ---
`;

    const readyReplacement = `${greetingBlock}
client.once('\''ready'\'', c => {
  process.stderr.write(\`discord channel: gateway connected as \${c.user.tag}\\n\`)
  process.stderr.write(\`discord channel: project directory \${PROJECT_DIR ?? '\''(not set)'\''}\\n\`)
  void sendStartupGreeting()
})`;

    src = src.replace(readyAnchor, readyReplacement);
    fs.writeFileSync(serverPath, src);
  ' || return 1

  return 0
}

revert() {
  local plugin_dir="$1"
  local server_ts="$plugin_dir/server.ts"

  [[ -f "$server_ts" ]] || return 3
  restore_file "$server_ts" && return 0
  return 2
}
