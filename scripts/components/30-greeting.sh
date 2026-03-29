#!/usr/bin/env bash

apply() {
  local plugin_dir="$1"
  local server_ts="$plugin_dir/server.ts"
  local upgraded_marker='function shouldSendStartupGreeting(): boolean {'

  [[ -f "$server_ts" ]] || return 3
  grep -qF "$upgraded_marker" "$server_ts" 2>/dev/null && return 2
  [[ -f "${server_ts}${BACKUP_SUFFIX}" ]] || return 3

  SERVER_TS="$server_ts" run_js '
    const fs = require("fs");
    const serverPath = process.env.SERVER_TS;
    let src = fs.readFileSync(serverPath, "utf8");
    const blockStart = "// --- claude-code-channels: greeting start ---";
    const blockEnd = "// --- claude-code-channels: greeting end ---";

    const readyAnchor = "client.once('\''ready'\'', c => {\n  process.stderr.write(`discord channel: gateway connected as ${c.user.tag}\\n`)\n})";
    if (!src.includes(blockStart) && !src.includes(readyAnchor)) {
      process.stderr.write("discord-channel: ready anchor not found in server.ts\n");
      process.exit(3);
    }

    const greetingBlock = `

// --- claude-code-channels: greeting start ---
function startupChannelIds(): string[] {
  return Object.keys(loadAccess().groups ?? {})
}

async function sendStartupGreeting(): Promise<void> {
  if (!shouldSendStartupGreeting()) {
    process.stderr.write("discord channel: startup greeting skipped because this session was not started with --channels plugin:discord@claude-plugins-official\\n")
    return
  }

  if (!PROJECT_DIR) {
    process.stderr.write("discord channel: startup greeting skipped because no discord project directory was provided\\n")
    return
  }

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

function processInfo(pid: number): { ppid: number; command: string } | undefined {
  if (!Number.isFinite(pid) || pid <= 1) return undefined
  const result = spawnSync("ps", ["-o", "ppid=,command=", "-p", String(pid)], { encoding: "utf8" })
  if (result.status !== 0) return undefined
  const line = (result.stdout ?? "")
    .split("\\n")
    .map(value => value.trim())
    .find(Boolean)
  if (!line) return undefined
  const match = line.match(/^(\\d+)\\s+(.*)$/)
  if (!match) return undefined
  return { ppid: Number(match[1]), command: match[2] }
}

function shouldSendStartupGreeting(): boolean {
  const override = (process.env.DISCORD_STARTUP_GREETING ?? "").trim().toLowerCase()
  if (["1", "true", "yes", "on"].includes(override)) return true
  if (["0", "false", "no", "off"].includes(override)) return false

  let pid = process.ppid
  for (let depth = 0; depth < 6 && pid > 1; depth++) {
    const info = processInfo(pid)
    if (!info) break
    if (info.command.includes("--channels") && info.command.includes("plugin:discord@claude-plugins-official")) {
      return true
    }
    pid = info.ppid
  }
  return false
}
// --- claude-code-channels: greeting end ---
`;

    if (src.includes(blockStart) && src.includes(blockEnd)) {
      const startIndex = src.indexOf(blockStart);
      const endIndex = src.indexOf(blockEnd) + blockEnd.length;
      src = src.slice(0, startIndex) + greetingBlock.trim() + src.slice(endIndex);
      fs.writeFileSync(serverPath, src);
      process.exit(0);
    }

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
