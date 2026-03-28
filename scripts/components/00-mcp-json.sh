#!/usr/bin/env bash

apply() {
  local plugin_dir="$1"
  local mcp_json="$plugin_dir/.mcp.json"
  local marker="DISCORD_PROJECT_DIR=\"$PWD\""

  [[ -f "$mcp_json" ]] || return 3
  grep -qF "$marker" "$mcp_json" 2>/dev/null && return 2

  backup_file "$mcp_json" || return 3

  MCP_JSON="$mcp_json" run_js '
    const fs = require("fs");
    const mcpPath = process.env.MCP_JSON;
    const mcp = JSON.parse(fs.readFileSync(mcpPath, "utf8"));
    const discord = mcp.mcpServers?.discord;
    if (!discord) {
      process.stderr.write("discord-channel: missing mcpServers.discord\n");
      process.exit(1);
    }
    discord.command = "sh";
    discord.args = [
      "-c",
      "DISCORD_PROJECT_DIR=\"$PWD\" exec bun run --cwd \"$1\" --shell=bun --silent start -- --discord-project-dir \"$DISCORD_PROJECT_DIR\"",
      "sh",
      "${CLAUDE_PLUGIN_ROOT}"
    ];
    delete discord.env;
    fs.writeFileSync(mcpPath, JSON.stringify(mcp, null, 2) + "\n");
  ' || return 1

  return 0
}

revert() {
  local plugin_dir="$1"
  local mcp_json="$plugin_dir/.mcp.json"

  [[ -f "$mcp_json" ]] || return 3
  restore_file "$mcp_json" && return 0
  return 2
}
