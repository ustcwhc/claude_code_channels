# Claude Code Channels — Project-Local Discord Access

An upgrade to the [Claude Code](https://claude.com/claude-code) official Discord channel plugin that adds **project-local channel scoping**. When multiple Claude Code sessions run in different project directories, each session only receives Discord messages from channels paired to that specific project — no cross-talk.

## How It Works

- `scripts/install.sh` patches the installed Discord plugin's `server.ts`, `.mcp.json`, and access skill (`SKILL.md`).
- `scripts/uninstall.sh` restores the original plugin files and removes the SessionStart hook.
- The install script registers a global **SessionStart hook** so patches are re-applied automatically whenever the plugin cache is refreshed.
- When Claude Code provides `CLAUDE_PROJECT_DIR` to the plugin process, the patched server tries `./.claude/channels/discord/access.json` for that project first.
- On gateway connect, the patched server logs the resolved project/channel info and sends a greeting message to each configured Discord channel for that session.
- Voice messages, video files, and PDFs are auto-downloaded on inbound messages so the session can inspect them immediately; other attachments remain on-demand via `download_attachment`.

### Scope Resolution Order

1. If `DISCORD_PROJECT_DIR` is set by Claude Code, the session first checks `<PROJECT_DIR>/.claude/channels/discord/access.json`
2. If that local file exists, it is used for the session
3. If that local file is missing or cannot be inspected, the server warns and falls back to `~/.claude/channels/discord/access.json`
4. If `DISCORD_PROJECT_DIR` is not set, the session uses `~/.claude/channels/discord/access.json`

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

### 3. Run the installer

```bash
./scripts/install.sh
```

This patches the installed Discord plugin in `~/.claude/plugins/cache/claude-plugins-official/discord/<version>/`, creates backup copies of the original files, and registers the SessionStart hook in `~/.claude/settings.json`.

When you run the installer interactively, it also offers a transcription backend menu:
- `Local whisper-cli` for fully local transcription
- `OpenAI Whisper API` for better multilingual transcription, using `OPENAI_API_KEY` and `whisper-1`

The installer stores the selection in `~/.claude/channels/discord/.env` via:
- `DISCORD_TRANSCRIBE_BACKEND=local` or `openai-whisper`
- `DISCORD_OPENAI_TRANSCRIBE_MODEL=whisper-1` when OpenAI is selected
- optionally `OPENAI_API_KEY=...` if you choose to save it there

The installer is **idempotent**:
- running it again skips already-applied components
- if the Discord plugin is not installed yet, it still registers the hook so future installs get patched automatically

### 4. Create a project-local access config

If you want a project-specific Discord channel, create the local access file in that project:

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

Then add project-local channels with:

```bash
/discord:access group add <channelId> --local
```

Important behavior:
- on startup, the plugin checks the project-local `./.claude/channels/discord/access.json` first
- if the local `access.json` is missing, the server warns and falls back to the global config
- if the local `access.json` is corrupt, the server exits with an error and tells you to fix or delete it

### 5. Start Claude Code

Start your session with channels enabled from the project directory:

```bash
claude --channels plugin:discord@claude-plugins-official
```

When the Discord gateway connects, the patched plugin:
- logs which config path it is using
- logs the connected channel IDs for the session
- sends a greeting message to each configured channel

### 6. Add to `.gitignore`

The local access config contains Discord channel and user IDs, so add it to your project's `.gitignore`:

```
.claude/channels/
```

## Uninstall

To remove the patch and hook:

```bash
./scripts/uninstall.sh
```

This restores the original plugin files from backups and removes the SessionStart hook from `~/.claude/settings.json`. It does **not** delete your project-local `access.json` files.

## Usage

Use the `/discord:access` skill as usual. The patched skill is scope-aware:

| Command | Behavior |
|---------|----------|
| `/discord:access` | Shows status with scope banner (local/global) |
| `/discord:access group add <id>` | Prompts for local vs global scope |
| `/discord:access group add <id> --local` | Adds to project-local config |
| `/discord:access group add <id> --global` | Adds to global config |
| `/discord:access group rm <id>` | Searches both local and global, removes where found |

DM-related commands (`pair`, `deny`, `allow`, `remove`, `policy`) always operate on the global config since DMs are user-level, not project-level.

At session startup, the patched server also:
- writes the resolved config path to stderr
- writes the connected channel IDs to stderr
- sends `Claude Code session connected (project: <name>)` to each configured channel when a project name is available

For inbound attachments:
- voice messages, video files, and PDFs are downloaded automatically into `~/.claude/channels/discord/inbox/` and surfaced in message metadata as readable attachments
- other attachment types still appear as metadata and can be fetched explicitly with `download_attachment(chat_id, message_id)`
- when `DISCORD_TRANSCRIBE_BACKEND=openai-whisper`, voice and video audio transcription use OpenAI's transcription API instead of local `whisper-cli`

## Architecture

```
claude_code_channels/
├── scripts/
│   ├── install.sh                    # Main installer + hook registration
│   ├── uninstall.sh                  # Restore backups + remove hook
│   ├── apply-discord-patch.sh        # Compatibility wrapper to install.sh
│   ├── lib/
│   │   └── common.sh                 # Shared helpers, backups, hook editing
│   └── components/
│       ├── 00-mcp-json.sh            # Inject DISCORD_PROJECT_DIR into .mcp.json
│       ├── 10-local-scoping.sh       # Patch server.ts for project-local access.json
│       ├── 20-skill-access.sh        # Install patched access skill
│       ├── 30-greeting.sh            # Session greeting + channel/project logging
│       └── 40-readable-attachments.sh # Auto-download voice/video/PDF attachments
├── patches/
│   ├── discord-local-scoping.patch   # Reference diff from the earlier approach
│   └── SKILL.md                      # Full patched access skill with scope-awareness
├── CLAUDE.md                         # Project config for Claude Code sessions
└── README.md
```

## Constraints

- **No new dependencies** — works with the existing Bun + discord.js stack
- **Global behavior preserved** — sessions without project-local mode still use `~/.claude/channels/discord/access.json`
- **Single bot token** — all sessions share one Discord bot; routing is done per-session via config scoping

## License

MIT
