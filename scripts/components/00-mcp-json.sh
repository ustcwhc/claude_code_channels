#!/usr/bin/env bash

apply() {
  local plugin_dir="$1"
  local mcp_json="$plugin_dir/.mcp.json"

  [[ -f "$mcp_json" ]] || return 3

  backup_file "$mcp_json" || return 3

  local js_status=0
  MCP_JSON="$mcp_json" run_js '
    const fs = require("fs");
    const mcpPath = process.env.MCP_JSON;
    const mcp = JSON.parse(fs.readFileSync(mcpPath, "utf8"));
    const discord = mcp.mcpServers?.discord;
    if (!discord) {
      process.stderr.write("discord-channel: missing mcpServers.discord\n");
      process.exit(1);
    }
    const desiredCommand = "sh";
    const desiredArgs = [
      "-c",
      "exec bun run --cwd \"$1\" --shell=bun --silent start -- --discord-project-dir \"$DISCORD_PROJECT_DIR\"",
      "sh",
      "${CLAUDE_PLUGIN_ROOT}"
    ];
    if (
      discord.command === desiredCommand &&
      JSON.stringify(discord.args ?? []) === JSON.stringify(desiredArgs) &&
      !discord.env
    ) {
      process.exit(2);
    }
    discord.command = desiredCommand;
    discord.args = desiredArgs;
    delete discord.env;
    fs.writeFileSync(mcpPath, JSON.stringify(mcp, null, 2) + "\n");
  ' || js_status=$?

  if [[ "$js_status" -eq 2 ]]; then
    return 2
  fi
  [[ "$js_status" -eq 0 ]] || return 1

  return 0
}

revert() {
  local plugin_dir="$1"
  local mcp_json="$plugin_dir/.mcp.json"

  [[ -f "$mcp_json" ]] || return 3
  restore_file "$mcp_json" && return 0
  return 2
}
