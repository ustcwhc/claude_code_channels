#!/usr/bin/env bash

apply() {
  local plugin_dir="$1"
  local server_ts="$plugin_dir/server.ts"
  local upgraded_marker='const STARTUP_STATUS_GREETING = RESUMED_SESSION_GREETING'

  [[ -f "$server_ts" ]] || return 3
  grep -qF "$upgraded_marker" "$server_ts" 2>/dev/null && return 2
  [[ -f "${server_ts}${BACKUP_SUFFIX}" ]] || return 3

  SERVER_TS="$server_ts" run_js '
    const fs = require("fs");
    const serverPath = process.env.SERVER_TS;
    let src = fs.readFileSync(serverPath, "utf8");

    const blockStart = "// --- claude-code-channels: project-memory start ---";
    const blockEnd = "// --- claude-code-channels: project-memory end ---";
    const insertAnchor = "// --- claude-code-channels: local-scoping end ---";
    if (!src.includes(insertAnchor)) {
      process.stderr.write("discord-channel: project-memory anchor not found in server.ts\n");
      process.exit(3);
    }

    const helperBlock = `

// --- claude-code-channels: project-memory start ---
const MAX_PROJECT_MEMORY_CHARS = Number(process.env.DISCORD_PROJECT_MEMORY_CHARS ?? "12000")
const MAX_PROJECT_MEMORY_GREETING_CHARS = Number(process.env.DISCORD_PROJECT_MEMORY_GREETING_CHARS ?? "3000")
const MAX_RESUMED_CONVERSATION_CHARS = Number(process.env.DISCORD_RESUMED_CONVERSATION_CHARS ?? "4000")

function claudeProjectStateDir(projectDir: string): string {
  return join(homedir(), ".claude", "projects", projectDir.replace(/[^A-Za-z0-9]/g, "-"))
}

function loadProjectMemoryInstruction(): string | undefined {
  if (!PROJECT_DIR) return undefined

  const memoryPath = join(claudeProjectStateDir(PROJECT_DIR), "memory", "MEMORY.md")
  try {
    let text = readFileSync(memoryPath, "utf8").trim()
    if (!text) return undefined

    let truncated = false
    if (text.length > MAX_PROJECT_MEMORY_CHARS) {
      text = text.slice(-MAX_PROJECT_MEMORY_CHARS)
      truncated = true
    }

    process.stderr.write("discord channel: loaded project memory from " + memoryPath + (truncated ? " (truncated)" : "") + "\\n")
    return [
      "Project startup context from local memory/dream state.",
      "This is background context for the current project, not a Discord user message. Use it to inform replies, and do not send a Discord reply just because this context exists.",
      "Source: " + memoryPath,
      truncated ? "Only the most recent portion is included below." : "",
      "",
      text,
    ].filter(Boolean).join("\\n")
  } catch (err) {
    const code = err?.code
    if (code !== "ENOENT") {
      process.stderr.write("discord channel: failed to read project memory from " + memoryPath + ": " + err + "\\n")
    }
    return undefined
  }
}

function loadProjectMemoryGreeting(): string | undefined {
  if (!PROJECT_DIR) return undefined

  const memoryPath = join(claudeProjectStateDir(PROJECT_DIR), "memory", "MEMORY.md")
  try {
    let text = readFileSync(memoryPath, "utf8").trim()
    if (!text) {
      return "Did not find previous dream content. This is a fresh start."
    }

    let truncated = false
    if (text.length > MAX_PROJECT_MEMORY_GREETING_CHARS) {
      text = text.slice(-MAX_PROJECT_MEMORY_GREETING_CHARS)
      truncated = true
    }

    return [
      "Loaded previous project dream:",
      text,
      truncated ? "(Dream content truncated to the most recent portion.)" : "",
    ].filter(Boolean).join("\\n\\n")
  } catch (err) {
    const code = err?.code
    if (code === "ENOENT") {
      return "Did not find previous dream content. This is a fresh start."
    }
    return undefined
  }
}

function collectTextParts(value: unknown, parts: string[]): void {
  if (value == null) return
  if (typeof value === "string") {
    const trimmed = value.trim()
    if (trimmed) parts.push(trimmed)
    return
  }
  if (Array.isArray(value)) {
    for (const entry of value) {
      collectTextParts(entry, parts)
    }
    return
  }
  if (typeof value !== "object") return

  const record = value as Record<string, unknown>
  const directText = typeof record.text === "string"
    ? record.text
    : typeof record.content === "string"
      ? record.content
      : typeof record.message === "string"
        ? record.message
        : undefined
  if (directText) {
    const trimmed = directText.trim()
    if (trimmed) parts.push(trimmed)
  }

  if (Array.isArray(record.content)) collectTextParts(record.content, parts)
  if (Array.isArray(record.message)) collectTextParts(record.message, parts)

  for (const [key, nested] of Object.entries(record)) {
    if (["text", "content", "message", "thinking", "signature", "input", "usage", "toolUseResult"].includes(key)) {
      continue
    }
    if (nested && typeof nested === "object") {
      collectTextParts(nested, parts)
    }
  }
}

function extractEntryText(entry: Record<string, unknown>): string | undefined {
  const parts: string[] = []
  collectTextParts(entry.message, parts)
  if (parts.length === 0 && entry.type === "user") {
    collectTextParts(entry, parts)
  }
  const text = parts.join("\\n\\n").trim()
  return text || undefined
}

function compactConversationText(text: string): string {
  return text
    .replace(/<command-message>[\\s\\S]*?<\\/command-message>/g, "")
    .replace(/<command-name>[\\s\\S]*?<\\/command-name>/g, "")
    .replace(/\\n{3,}/g, "\\n\\n")
    .trim()
}

function loadResumedConversationGreeting(): string | undefined {
  if (!PROJECT_DIR) return undefined

  const sessionId = (process.env.DISCORD_RESUMED_SESSION_ID ?? "").trim()
  if (!sessionId) return undefined

  const sessionPath = join(claudeProjectStateDir(PROJECT_DIR), sessionId + ".jsonl")
  try {
    const lines = readFileSync(sessionPath, "utf8")
      .split("\\n")
      .map(line => line.trim())
      .filter(Boolean)

    let latestUser: string | undefined
    let latestAssistant: string | undefined

    for (const line of lines) {
      let entry: Record<string, unknown>
      try {
        entry = JSON.parse(line)
      } catch {
        continue
      }

      if (entry.isSidechain === true) continue
      const type = entry.type
      const role = typeof entry.message === "object" && entry.message && "role" in entry.message
        ? (entry.message as { role?: unknown }).role
        : undefined
      const text = extractEntryText(entry)
      if (!text) continue

      if (type === "user" || role === "user") {
        latestUser = compactConversationText(text)
        continue
      }

      if (type === "assistant" || role === "assistant") {
        latestAssistant = compactConversationText(text)
      }
    }

    if (!latestUser && !latestAssistant) return undefined

    const sections = [
      latestUser ? "Latest user message:\\n" + latestUser : undefined,
      latestAssistant ? "Latest Claude reply:\\n" + latestAssistant : undefined,
    ].filter(Boolean)

    let combined = sections.join("\\n\\n")
    let truncated = false
    if (combined.length > MAX_RESUMED_CONVERSATION_CHARS) {
      combined = combined.slice(-MAX_RESUMED_CONVERSATION_CHARS).trim()
      truncated = true
    }

    return [
      "Loaded latest resumed conversation:",
      combined,
      truncated ? "(Latest conversation truncated to the most recent portion.)" : "",
    ].filter(Boolean).join("\\n\\n")
  } catch (err) {
    process.stderr.write("discord channel: failed to read resumed session " + sessionId + " from " + sessionPath + ": " + err + "\\n")
    return undefined
  }
}

const PROJECT_MEMORY_INSTRUCTION = loadProjectMemoryInstruction()
const PROJECT_MEMORY_GREETING = loadProjectMemoryGreeting()
const RESUMED_SESSION_GREETING = loadResumedConversationGreeting()
const STARTUP_CONTEXT_INSTRUCTION = RESUMED_SESSION_GREETING ?? PROJECT_MEMORY_INSTRUCTION
const STARTUP_STATUS_GREETING =
  RESUMED_SESSION_GREETING ??
  PROJECT_MEMORY_GREETING ??
  "Did not find previous dream content. This is a fresh start."
// --- claude-code-channels: project-memory end ---
`;

    if (src.includes(blockStart) && src.includes(blockEnd)) {
      const startIndex = src.indexOf(blockStart);
      const endIndex = src.indexOf(blockEnd) + blockEnd.length;
      src = src.slice(0, startIndex) + helperBlock.trim() + src.slice(endIndex);
    } else {
      src = src.replace(insertAnchor, `${insertAnchor}${helperBlock}`);
    }

    const introPattern = / {6}[\"\x27]The sender reads Discord, not this session\. Anything you want them to see must go through the reply tool — your transcript output never reaches their chat\.[\"\x27],\n {6}[\"\x27]{2},\n/;
    if (!introPattern.test(src)) {
      process.stderr.write("discord-channel: project-memory instructions anchor not found in server.ts\n");
      process.exit(3);
    }
    src = src.replace(
      introPattern,
      `      "The sender reads Discord, not this session. Anything you want them to see must go through the reply tool — your transcript output never reaches their chat.",\n      "",\n      STARTUP_CONTEXT_INSTRUCTION,\n      "",\n`,
    );

    src = src.replace(
      `      STARTUP_CONTEXT_INSTRUCTION,\n      "",\n      PROJECT_MEMORY_INSTRUCTION,\n      "",\n`,
      `      STARTUP_CONTEXT_INSTRUCTION,\n      "",\n`,
    );
    src = src.replace(
      /(STARTUP_CONTEXT_INSTRUCTION,\n\s+"",\n)(?:\s*STARTUP_CONTEXT_INSTRUCTION,\n\s+"",\n)+/g,
      "$1",
    );

    src = src.replace("    ].join('\\n'),", "    ].filter(Boolean).join('\\n'),");

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
