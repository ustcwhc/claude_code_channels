# Claude Code Channels — Project-Local Discord Access

An upgrade to the [Claude Code](https://claude.com/claude-code) official Discord channel plugin that adds **project-local channel scoping**. When multiple Claude Code sessions run in different project directories, each session only receives Discord messages from channels paired to that specific project — no cross-talk.

## How It Works

- A unified diff patch modifies the Discord plugin's `server.ts`, `.mcp.json`, and access skill (`SKILL.md`).
- On startup, the patched server checks for a **project-local** `access.json` inside the current project directory. If found, it uses that instead of the global config.
- A **SessionStart hook** re-applies the patch automatically whenever the plugin cache is refreshed (e.g., after plugin updates).

### Scope Resolution Order

1. If `<PROJECT_DIR>/.claude/channels/discord/access.json` exists → **local** (project-scoped)
2. Otherwise → `~/.claude/channels/discord/access.json` (global, original behavior)

## Prerequisites

- [Claude Code](https://claude.com/claude-code) CLI installed (v2.1.80 or later)
- [Bun](https://bun.sh) installed
- The official **Discord channel plugin** fully set up and working — follow the [Discord section of the Claude Code Channels guide](https://code.claude.com/docs/en/channels) to create a Discord bot, install the plugin, configure your token, and pair your account **before** applying this patch

## Installation

### 1. Set up the official Discord channel plugin

Follow the official guide at **https://code.claude.com/docs/en/channels** (Discord tab):

1. **Create a Discord bot** — go to the [Discord Developer Portal](https://discord.com/developers/applications), create an application, and copy the bot token
2. **Enable Message Content Intent** — in your bot's settings under Privileged Gateway Intents
3. **Invite the bot to your server** — via OAuth2 URL Generator with `bot` scope and required permissions (View Channels, Send Messages, Read Message History, etc.)
4. **Install the plugin** — run `/plugin install discord@claude-plugins-official` in Claude Code
5. **Configure your token** — run `/discord:configure <token>`
6. **Start with channels enabled** — `claude --channels plugin:discord@claude-plugins-official`
7. **Pair your account** — DM your bot, then run `/discord:access pair <code>`

Once the base Discord channel is working, proceed to install the project-local scoping patch below.

### 2. Clone this repo

```bash
git clone https://github.com/ustcwhc/claude_code_channels.git
cd claude_code_channels
```

### 3. Run the patch script

```bash
./scripts/apply-discord-patch.sh
```

This applies the local-scoping patch to your installed Discord plugin (in `~/.claude/plugins/cache/`). The script is **idempotent** — safe to run multiple times.

### 4. Set up the SessionStart hook

Add the following to your Claude Code settings so the patch is automatically re-applied after plugin updates:

**Option A: Project-level** — add to `.claude/settings.json` in your project:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/claude_code_channels/scripts/apply-discord-patch.sh",
            "timeout": 15
          }
        ]
      }
    ]
  }
}
```

**Option B: Global (recommended)** — add to `~/.claude/settings.json` to apply across all projects:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/claude_code_channels/scripts/apply-discord-patch.sh",
            "timeout": 15
          }
        ]
      }
    ]
  }
}
```

Replace `/path/to/claude_code_channels` with the actual absolute path where you cloned this repo.

> **Note:** If you already have a `SessionStart` hook in your settings, add the new hook entry to the existing `"hooks"` array rather than replacing it.

### 5. Create a project-local access config

In your project directory, create the local access file:

```bash
mkdir -p .claude/channels/discord
cat > .claude/channels/discord/access.json << 'EOF'
{
  "dmPolicy": "pairing",
  "allowFrom": [],
  "pending": {},
  "groups": {}
}
EOF
```

Then use `/discord:access group add <channelId> --local` to add channels scoped to this project.

### 6. Add to `.gitignore`

The local access config contains Discord channel/user IDs — add it to your project's `.gitignore`:

```
.claude/channels/
```

## Usage

Once installed, the Discord plugin automatically uses project-local config when available. Use the `/discord:access` skill as usual — it now supports scope-aware operations:

| Command | Behavior |
|---------|----------|
| `/discord:access` | Shows status with scope banner (local/global) |
| `/discord:access group add <id>` | Prompts for local vs global scope |
| `/discord:access group add <id> --local` | Adds to project-local config |
| `/discord:access group add <id> --global` | Adds to global config |
| `/discord:access group rm <id>` | Searches both local and global, removes where found |

DM-related commands (`pair`, `deny`, `allow`, `remove`, `policy`) always operate on the global config since DMs are user-level, not project-level.

## Architecture

```
claude_code_channels/
├── patches/
│   ├── discord-local-scoping.patch    # Unified diff for reference (server.ts, .mcp.json, SKILL.md)
│   └── SKILL.md                       # Full patched access skill with scope-awareness
├── scripts/
│   └── apply-discord-patch.sh         # Idempotent apply script (SessionStart hook target)
├── CLAUDE.md                          # Project config for Claude Code sessions
└── README.md
```

## Constraints

- **No new dependencies** — works with the existing Bun + discord.js stack
- **Backward compatible** — projects without a local `access.json` work exactly as before
- **Single bot token** — all sessions share one Discord bot; routing is done per-session via config scoping

## License

MIT
