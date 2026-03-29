# Claude Code Channels — Project-Local Discord Access

An upgrade to the [Claude Code](https://claude.com/claude-code) official Discord channel plugin that adds project-local channel scoping, startup context loading, richer media handling, and auto-resume for channel-enabled sessions.

## How It Works

- `scripts/install.sh` patches the installed official Discord plugin's `server.ts`, `.mcp.json`, and access skill (`SKILL.md`).
- `scripts/uninstall.sh` restores the original plugin files and removes the SessionStart hook.
- The install script registers a global `SessionStart` hook so patches are re-applied automatically whenever the plugin cache is refreshed.
- A lightweight Claude launcher wrapper injects `DISCORD_PROJECT_DIR` from the current working directory for `--channels` sessions, so the official Discord plugin gets a concrete project path even when Claude does not expand `${CLAUDE_PROJECT_DIR}` reliably.
- The patched server tries `./.claude/channels/discord/access.json` for that project first.
- Startup greetings are only sent for sessions detected as `claude --channels plugin:discord@claude-plugins-official`, with `DISCORD_STARTUP_GREETING` available as a manual override.
- Startup context precedence is: resumed session summary first, project memory/dream second, true fresh start only if neither exists.
- If project memory exists at `~/.claude/projects/<escaped-project-path>/memory/MEMORY.md`, the patched server loads it at startup, injects it into the Discord session as background context, and can include it in the startup greeting.
- Voice messages, video files, and PDFs are auto-downloaded on inbound messages so the session can inspect them immediately; other attachments remain on-demand via `download_attachment`.
- The installer registers both a shell helper and a `~/.local/bin/claude` wrapper so `claude --channels ...` auto-resumes the latest saved session for the current folder even when Claude is launched outside an interactive zsh shell.

### Scope Resolution Order

1. If `DISCORD_PROJECT_DIR` is set, the session first checks `<PROJECT_DIR>/.claude/channels/discord/access.json`
2. If that local file exists, it is used for the session
3. If that local file is missing or cannot be inspected, the server warns and falls back to `~/.claude/channels/discord/access.json`
4. If `DISCORD_PROJECT_DIR` is not set, the session uses `~/.claude/channels/discord/access.json`

## Prerequisites

- [Claude Code](https://claude.com/claude-code) CLI installed
- [Bun](https://bun.sh) installed
- The official Discord channel plugin already set up and paired

Follow the official Discord channel guide here:
[Claude Code Channels](https://code.claude.com/docs/en/channels)

## Installation

### 1. Clone this repo

```bash
git clone https://github.com/ustcwhc/claude_code_channels.git
cd claude_code_channels
```

### 2. Run the installer

```bash
./scripts/install.sh
```

This patches the installed Discord plugin in `~/.claude/plugins/cache/claude-plugins-official/discord/<version>/` and `~/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/discord`, creates backup copies of the original files, registers the `SessionStart` hook in `~/.claude/settings.json`, updates `~/.zshrc`, and installs a `~/.local/bin/claude` wrapper so `claude --channels ...` resumes the latest saved session for the current folder automatically and passes the real project directory through to the official Discord plugin.

When you run the installer interactively, it also offers a transcription backend menu:
- `Local whisper-cli` for fully local transcription
- `OpenAI Whisper API` for better multilingual transcription, using `OPENAI_API_KEY` and `whisper-1`
- if an `OPENAI_API_KEY` already exists in your shell environment or `~/.claude/channels/discord/.env`, the installer asks whether to keep it or replace it
- the OpenAI submenu includes a `Go back` option so you can switch back to `Local whisper-cli` before applying anything

The installer stores the selection in `~/.claude/channels/discord/.env` via:
- `DISCORD_TRANSCRIBE_BACKEND=local` or `openai-whisper`
- `DISCORD_OPENAI_TRANSCRIBE_MODEL=whisper-1` when OpenAI is selected
- optionally `OPENAI_API_KEY=...` if you choose to save it there

The installer is idempotent:
- running it again skips already-applied components
- if the Discord plugin is not installed yet, it still registers the hook so future installs get patched automatically

### 3. Create a project-local access config

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

### 4. Start Claude Code

Start your session with channels enabled from the project directory:

```bash
claude --channels plugin:discord@claude-plugins-official
```

When the Discord gateway connects, the patched plugin:
- logs which config path it is using
- logs the connected channel IDs for the session
- loads the current project's Claude memory/dream file when present and uses it as hidden startup context
- sends a greeting message to each configured channel only for sessions detected as `--channels plugin:discord@claude-plugins-official`

When you launch Claude with `--channels`:
- `claude --channels plugin:discord@claude-plugins-official` auto-resumes the latest saved session for the current folder when one exists
- the wrapper exports `DISCORD_PROJECT_DIR` from the current working directory so the official Discord plugin can resolve the local `access.json`
- plain `claude` behavior is unchanged
- if you already pass `--resume`, `--continue`, or `--session-id`, the wrapper leaves your command alone
- set `CLAUDE_CHANNELS_AUTO_RESUME_DISABLE=1` to bypass the wrapper temporarily

### 5. Add to `.gitignore`

The local access config contains Discord channel and user IDs, so add it to your project's `.gitignore`:

```gitignore
.claude/channels/
```

## Usage

Use the `/discord:access` skill as usual. The patched skill is scope-aware:

| Command | Behavior |
|---------|----------|
| `/discord:access` | Shows status with scope banner (local/global) |
| `/discord:access group add <id>` | Prompts for local/global scope, DM policy, mention requirement, and optional `allowFrom` IDs, and when writing local config also seeds `CLAUDE.md` with a channel-reply rule |
| `/discord:access group add <id> --local` | Adds to project-local config |
| `/discord:access group add <id> --global` | Adds to global config |
| `/discord:access group rm <id>` | Searches both local and global, removes where found |

DM-related commands (`pair`, `deny`, `allow`, `remove`, `policy`) always operate on the global config since DMs are user-level, not project-level.

When `/discord:access group add <id>` writes a project-local config, it also creates or updates [`CLAUDE.md`](/Users/haocheng_mini/Documents/projects/claude_code_channels/CLAUDE.md) in that project with an important operating rule: messages that came from Discord or Telegram must be answered back in that channel, not left only in the Claude Code CLI.

For inbound attachments:
- voice messages, video files, and PDFs are downloaded automatically into `~/.claude/channels/discord/inbox/`
- voice and video are transcribed before the first reply, and PDFs are converted to text when possible
- other attachment types still appear as metadata and can be fetched explicitly with `download_attachment(chat_id, message_id)`
- when `DISCORD_TRANSCRIBE_BACKEND=openai-whisper`, voice and video audio transcription uses OpenAI's transcription API instead of local `whisper-cli`

## Architecture

```text
claude_code_channels/
├── scripts/
│   ├── install.sh
│   ├── uninstall.sh
│   ├── apply-discord-patch.sh
│   ├── helpers/
│   │   └── claude-auto-resume.sh
│   ├── lib/
│   │   └── common.sh
│   └── components/
│       ├── 00-mcp-json.sh
│       ├── 10-local-scoping.sh
│       ├── 20-skill-access.sh
│       ├── 30-greeting.sh
│       ├── 35-project-memory.sh
│       └── 40-readable-attachments.sh
├── patches/
│   └── SKILL.md
├── CLAUDE.md
└── README.md
```

## Uninstall

To remove the patch and hook:

```bash
./scripts/uninstall.sh
```

This restores the original plugin files from backups, removes the `SessionStart` hook from `~/.claude/settings.json`, removes the zsh auto-resume wrapper block from `~/.zshrc`, and restores `~/.local/bin/claude` to the original Claude binary symlink. It does not delete your project-local `access.json` files.

## Constraints

- No new dependencies
- Global behavior remains available when no local project config exists
- All sessions share one Discord bot token; routing is done per-session via config scoping

## License

MIT
