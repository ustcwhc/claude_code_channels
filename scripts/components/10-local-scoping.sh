#!/usr/bin/env bash

apply() {
  local plugin_dir="$1"
  local server_ts="$plugin_dir/server.ts"
  local marker_start="// --- claude-code-channels: local-scoping start ---"
  local marker_end="// --- claude-code-channels: local-scoping end ---"

  [[ -f "$server_ts" ]] || return 3

  backup_file "$server_ts" || return 3

  local js_status=0
  SERVER_TS="$server_ts" run_js '
    const fs = require("fs");
    const serverPath = process.env.SERVER_TS;
    let src = fs.readFileSync(serverPath, "utf8");

    src = src.replace(
      /import \{ ([^}]+) \} from '\''path'\''/,
      (_, imports) => {
        const parts = imports.split(",").map(part => part.trim()).filter(Boolean);
        if (!parts.includes("dirname")) parts.push("dirname");
        if (!parts.includes("basename")) parts.push("basename");
        return `import { ${parts.join(", ")} } from '\''path'\''`;
      },
    );

    const blockStart = "// --- claude-code-channels: local-scoping start ---";
    const blockEnd = "// --- claude-code-channels: local-scoping end ---";

    const envAnchor = "const ENV_FILE = join(STATE_DIR, '\''.env'\'')";
    if (!src.includes(envAnchor)) {
      process.stderr.write("discord-channel: ENV_FILE anchor not found in server.ts\n");
      process.exit(3);
    }
    const resolveBlock = `

// --- claude-code-channels: local-scoping start ---
function normalizeProjectDir(value: string | undefined): string | undefined {
  if (!value) return undefined
  const trimmed = value.trim()
  if (!trimmed || trimmed.startsWith("--") || trimmed.includes("$" + "{")) return undefined
  return trimmed
}

function projectDirFromArgv(): string | undefined {
  const flagIndex = process.argv.indexOf('\''--discord-project-dir'\'')
  if (flagIndex === -1) return undefined
  return normalizeProjectDir(process.argv[flagIndex + 1])
}

const PROJECT_DIR = normalizeProjectDir(process.argv[process.argv.indexOf('\''--discord-project-dir'\'') + 1]) || normalizeProjectDir(process.env.DISCORD_PROJECT_DIR) || projectDirFromArgv() || undefined

function resolveAccessFile(): { path: string; scope: '\''local'\'' | '\''global'\'' } {
  if (PROJECT_DIR) {
    const candidate = join(PROJECT_DIR, '\''.claude'\'', '\''channels'\'', '\''discord'\'', '\''access.json'\'')
    try {
      statSync(candidate)
      return { path: candidate, scope: '\''local'\'' }
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code
      if (code === '\''ENOENT'\'') {
        process.stderr.write(\`discord channel: local access.json not found at \${candidate}; falling back to global config \${ACCESS_FILE}\\n\`)
      } else {
        process.stderr.write(\`discord channel: failed to inspect local access.json at \${candidate}: \${err}; falling back to global config \${ACCESS_FILE}\\n\`)
      }
      return { path: ACCESS_FILE, scope: '\''global'\'' }
    }
  }
  return { path: ACCESS_FILE, scope: '\''global'\'' }
}

const { path: ACTIVE_ACCESS_FILE, scope: ACTIVE_SCOPE } = resolveAccessFile()
process.stderr.write(\`discord channel: using \${ACTIVE_SCOPE} config \${ACTIVE_ACCESS_FILE}\\n\`)
// --- claude-code-channels: local-scoping end ---
`;
    if (src.includes(blockStart) && src.includes(blockEnd)) {
      const startIndex = src.indexOf(blockStart);
      const endIndex = src.indexOf(blockEnd);
      src = src.slice(0, startIndex) + resolveBlock.trim() + src.slice(endIndex + blockEnd.length);
    } else {
      src = src.replace(envAnchor, `${envAnchor}${resolveBlock}`);
    }

    const legacyStart = "\n// discord-local-scoping patch applied\n";
    const legacyEnd = "\n// Load ~/.claude/channels/discord/.env into process.env. Real env wins.\n";
    const legacyStartIndex = src.indexOf(legacyStart);
    const legacyEndIndex = src.indexOf(legacyEnd);
    if (legacyStartIndex !== -1 && legacyEndIndex !== -1 && legacyEndIndex > legacyStartIndex) {
      src = src.slice(0, legacyStartIndex) + "\n" + src.slice(legacyEndIndex);
    }

    src = src.replace(
      "const raw = readFileSync(ACCESS_FILE, '\''utf8'\'')",
      "const raw = readFileSync(ACTIVE_ACCESS_FILE, '\''utf8'\'')",
    );

    src = src.replace(
      "if ((err as NodeJS.ErrnoException).code === '\''ENOENT'\'') return defaultAccess()",
      "if ((err as NodeJS.ErrnoException).code === '\''ENOENT'\'') { process.stderr.write(`discord channel: ${ACTIVE_SCOPE} access file missing at ${ACTIVE_ACCESS_FILE}; using default empty config\\n`); return defaultAccess() }",
    );

    src = src.replace(
      "try { renameSync(ACCESS_FILE, `${ACCESS_FILE}.corrupt-${Date.now()}`) } catch {}",
      "if (ACTIVE_SCOPE === '\''local'\'') { process.stderr.write(`discord channel: local access.json is corrupt - fix or delete ${ACTIVE_ACCESS_FILE}\\n`); process.exit(1) }\n    try { renameSync(ACTIVE_ACCESS_FILE, `${ACTIVE_ACCESS_FILE}.corrupt-${Date.now()}`) } catch {}",
    );

    src = src.replace(
      "mkdirSync(STATE_DIR, { recursive: true, mode: 0o700 })",
      "mkdirSync(dirname(ACTIVE_ACCESS_FILE), { recursive: true, mode: 0o700 })",
    );
    src = src.replace(
      "const tmp = ACCESS_FILE + '\''.tmp'\''",
      "const tmp = ACTIVE_ACCESS_FILE + '\''.tmp'\''",
    );
    src = src.replace(
      "renameSync(tmp, ACCESS_FILE)",
      "renameSync(tmp, ACTIVE_ACCESS_FILE)",
    );

    if (src === fs.readFileSync(serverPath, "utf8")) {
      process.stderr.write("discord-channel: no local scoping changes applied\n");
      process.exit(2);
    }

    fs.writeFileSync(serverPath, src);
  ' || js_status=$?

  if [[ "$js_status" -eq 2 ]]; then
    return 2
  fi
  [[ "$js_status" -eq 0 ]] || return 1

  return 0
}

revert() {
  local plugin_dir="$1"
  local server_ts="$plugin_dir/server.ts"

  [[ -f "$server_ts" ]] || return 3
  restore_file "$server_ts" && return 0
  return 2
}
