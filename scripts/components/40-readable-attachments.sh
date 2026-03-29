#!/usr/bin/env bash

apply() {
  local plugin_dir="$1"
  local server_ts="$plugin_dir/server.ts"
  local upgraded_marker="const TRANSCRIBE_BACKEND = process.env.DISCORD_TRANSCRIBE_BACKEND"

  [[ -f "$server_ts" ]] || return 3
  grep -qF "$upgraded_marker" "$server_ts" 2>/dev/null && return 2
  [[ -f "${server_ts}${BACKUP_SUFFIX}" ]] || return 3

  SERVER_TS="$server_ts" run_js '
    const fs = require("fs");
    const serverPath = process.env.SERVER_TS;
    let src = fs.readFileSync(serverPath, "utf8");

    src = src.replace(
      /import \{ ([^}]+) \} from [\"\x27]path[\"\x27]/,
      (_, imports) => {
        const parts = imports.split(",").map(part => part.trim()).filter(Boolean);
        if (!parts.includes("extname")) parts.push("extname");
        return `import { ${parts.join(", ")} } from "path"`;
      },
    );

    const osImportMatch = src.match(/import \{ homedir \} from [\"\x27]os[\"\x27]/);
    if (!osImportMatch) {
      process.stderr.write("discord-channel: os import anchor not found in server.ts\n");
      process.exit(3);
    }
    if (!src.includes(`import { spawnSync } from "child_process"`)) {
      src = src.replace(osImportMatch[0], `${osImportMatch[0]}\nimport { spawnSync } from "child_process"`);
    }

    const safeAttNameAnchor = `function safeAttName(att: Attachment): string {
  return (att.name ?? att.id).replace(/[\\[\\]\\r\\n;]/g, "\x27_\x27")
}
`.replace(/"\x27/g, "\x27").replace(/\x27"/g, "\x27");
    if (!src.includes(safeAttNameAnchor)) {
      process.stderr.write("discord-channel: safeAttName anchor not found in server.ts\n");
      process.exit(3);
    }

    const blockStart = "// --- claude-code-channels: readable-attachments start ---";
    const blockEnd = "// --- claude-code-channels: readable-attachments end ---";
    const helperBlock = `

// --- claude-code-channels: readable-attachments start ---
function attachmentKind(att: Attachment): "voice" | "video" | "pdf" | "audio" | "image" | "file" {
  const contentType = (att.contentType ?? "").toLowerCase()
  const name = (att.name ?? "").toLowerCase()

  if (contentType === "application/pdf" || name.endsWith(".pdf")) return "pdf"
  if (contentType.startsWith("video/") || /\\.(mp4|mov|m4v|webm|mkv)$/i.test(name)) return "video"

  const duration = (att as Attachment & { duration?: number | null }).duration
  if (contentType.startsWith("audio/") && (duration != null || /\\.(ogg|oga|mp3|wav|m4a|aac|flac)$/i.test(name))) {
    return "voice"
  }

  if (contentType.startsWith("audio/")) return "audio"
  if (contentType.startsWith("image/")) return "image"
  return "file"
}

function isReadableAttachment(att: Attachment): boolean {
  const kind = attachmentKind(att)
  return kind === "voice" || kind === "video" || kind === "pdf"
}

function describeAttachment(att: Attachment): string {
  const kind = attachmentKind(att)
  const kb = (att.size / 1024).toFixed(0)
  return \`\${safeAttName(att)} (\${kind}, \${att.contentType ?? "unknown"}, \${kb}KB)\`
}

const TRANSCRIBE_BACKEND = process.env.DISCORD_TRANSCRIBE_BACKEND ?? "local"
const WHISPER_MODEL = process.env.DISCORD_WHISPER_MODEL ?? join(homedir(), ".claude", "models", "ggml-base.en.bin")
const WHISPER_CLI = process.env.DISCORD_WHISPER_CLI ?? "/opt/homebrew/bin/whisper-cli"
const FFMPEG_CLI = process.env.DISCORD_FFMPEG_CLI ?? "/opt/homebrew/bin/ffmpeg"
const PDFTOTEXT_CLI = process.env.DISCORD_PDFTOTEXT_CLI ?? "/opt/homebrew/bin/pdftotext"
const OPENAI_API_KEY = process.env.OPENAI_API_KEY
const OPENAI_TRANSCRIBE_MODEL = process.env.DISCORD_OPENAI_TRANSCRIBE_MODEL ?? "whisper-1"

function commandReady(path: string): boolean {
  try {
    statSync(path)
    return true
  } catch {
    return false
  }
}

function readableTextPathFor(path: string, suffix: string): string {
  const ext = extname(path)
  const base = ext.length > 0 ? path.slice(0, -ext.length) : path
  return \`\${base}.\${suffix}\`
}

function extractPdfText(path: string): string | undefined {
  if (!commandReady(PDFTOTEXT_CLI)) return undefined

  const txtPath = readableTextPathFor(path, "pdf.txt")
  const result = spawnSync(PDFTOTEXT_CLI, [path, txtPath], { encoding: "utf8" })
  if (result.status !== 0) {
    process.stderr.write(\`discord channel: pdftotext failed for \${path}: \${result.stderr || result.stdout || "unknown error"}\\n\`)
    return undefined
  }
  return txtPath
}

function convertMediaToWav(path: string, suffix: string): string | undefined {
  if (!commandReady(FFMPEG_CLI)) return undefined
  const wavPath = readableTextPathFor(path, \`\${suffix}.tmp.wav\`)
  const ffmpeg = spawnSync(
    FFMPEG_CLI,
    ["-i", path, "-ar", "16000", "-ac", "1", wavPath, "-y", "-loglevel", "error"],
    { encoding: "utf8" },
  )
  if (ffmpeg.status !== 0) {
    process.stderr.write(\`discord channel: ffmpeg failed for \${path}: \${ffmpeg.stderr || ffmpeg.stdout || "unknown error"}\\n\`)
    try { rmSync(wavPath, { force: true }) } catch {}
    return undefined
  }
  return wavPath
}

function transcribeWithLocalWhisper(wavPath: string): string | undefined {
  if (!commandReady(WHISPER_CLI) || !commandReady(WHISPER_MODEL)) return undefined
  const whisper = spawnSync(
    WHISPER_CLI,
    ["-m", WHISPER_MODEL, "-f", wavPath, "--no-timestamps"],
    { encoding: "utf8" },
  )
  if (whisper.status !== 0) {
    process.stderr.write(\`discord channel: whisper failed for \${wavPath}: \${whisper.stderr || whisper.stdout || "unknown error"}\\n\`)
    return undefined
  }

  return (whisper.stdout ?? "")
    .split("\\n")
    .filter(line => line.length > 0 && !/^(whisper_|ggml_|load_|system_info|main:)/.test(line))
    .join("\\n")
    .trim()
}

async function transcribeWithOpenAI(wavPath: string): Promise<string | undefined> {
  if (!OPENAI_API_KEY) return undefined

  const form = new FormData()
  form.append("model", OPENAI_TRANSCRIBE_MODEL)
  form.append("response_format", "text")
  form.append("file", new Blob([readFileSync(wavPath)]), basename(wavPath))

  const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: {
      Authorization: \`Bearer \${OPENAI_API_KEY}\`,
    },
    body: form,
  })

  const text = (await response.text()).trim()
  if (!response.ok) {
    process.stderr.write(\`discord channel: OpenAI transcription failed for \${wavPath}: \${text || response.statusText}\\n\`)
    return undefined
  }

  return text
}

async function transcribeMedia(path: string, suffix: string): Promise<string | undefined> {
  const wavPath = convertMediaToWav(path, suffix)
  if (!wavPath) return undefined

  const transcriptPath = readableTextPathFor(path, \`\${suffix}.transcript.txt\`)
  const transcript =
    TRANSCRIBE_BACKEND === "openai-whisper"
      ? await transcribeWithOpenAI(wavPath)
      : transcribeWithLocalWhisper(wavPath)
  try { rmSync(wavPath, { force: true }) } catch {}

  if (!transcript) return undefined
  writeFileSync(transcriptPath, transcript + "\\n")
  return transcriptPath
}

async function extractVideoArtifacts(path: string): Promise<string | undefined> {
  if (!commandReady(FFMPEG_CLI)) return undefined

  const framesPattern = readableTextPathFor(path, "video.frame-%02d.jpg")
  const framesPrefix = readableTextPathFor(path, "video.frame-")
  const manifestPath = readableTextPathFor(path, "video.manifest.txt")
  const ffmpeg = spawnSync(
    FFMPEG_CLI,
    ["-i", path, "-vf", "fps=1,scale=960:-1", "-frames:v", "4", framesPattern, "-y", "-loglevel", "error"],
    { encoding: "utf8" },
  )
  if (ffmpeg.status !== 0) {
    process.stderr.write(\`discord channel: ffmpeg frame extraction failed for \${path}: \${ffmpeg.stderr || ffmpeg.stdout || "unknown error"}\\n\`)
  }

  const baseDir = dirname(path)
  const frameFiles = readdirSync(baseDir)
    .filter(name => name.startsWith(basename(framesPrefix)) && name.endsWith(".jpg"))
    .sort()
    .map(name => join(baseDir, name))

  const transcriptPath = await transcribeMedia(path, "video")
  const lines: string[] = []
  if (frameFiles.length > 0) {
    lines.push("Extracted video frames:")
    lines.push(...frameFiles)
  }
  if (transcriptPath) {
    try {
      const transcript = readFileSync(transcriptPath, "utf8").trim()
      if (transcript) {
        if (lines.length > 0) lines.push("")
        lines.push("Extracted video audio transcript:")
        lines.push(transcript)
      }
    } catch {}
  }

  if (lines.length === 0) return undefined
  writeFileSync(manifestPath, lines.join("\\n") + "\\n")
  return manifestPath
}

async function extractReadableText(kind: ReturnType<typeof attachmentKind>, path: string): Promise<string | undefined> {
  if (kind === "pdf") return extractPdfText(path)
  if (kind === "voice") return transcribeMedia(path, "voice")
  if (kind === "video") return extractVideoArtifacts(path)
  return undefined
}

function readableAttachmentText(entries: string[]): string[] {
  const texts: string[] = []
  for (const entry of entries) {
    const sep = entry.indexOf(" => ")
    if (sep === -1) continue

    const label = entry.slice(0, sep)
    const rest = entry.slice(sep + 4)
    const sourceMarker = " (source: "
    const sourceIndex = rest.indexOf(sourceMarker)
    const extractedPath = sourceIndex === -1 ? rest : rest.slice(0, sourceIndex)

    try {
      const text = readFileSync(extractedPath, "utf8").trim()
      if (!text) continue
      texts.push(\`\${label}: \${text}\`)
    } catch {}
  }
  return texts
}

async function downloadReadableAttachments(msg: Message): Promise<string[]> {
  const downloads: string[] = []
  for (const att of msg.attachments.values()) {
    if (!isReadableAttachment(att)) continue
    const kind = attachmentKind(att)
    const path = await downloadAttachment(att)
    const extractedTextPath = await extractReadableText(kind, path)
    downloads.push(
      extractedTextPath
        ? \`\${describeAttachment(att)} => \${extractedTextPath} (source: \${path})\`
        : \`\${describeAttachment(att)} => \${path}\`,
    )
  }
  return downloads
}
// --- claude-code-channels: readable-attachments end ---
`;

    if (src.includes(blockStart) && src.includes(blockEnd)) {
      const startIndex = src.indexOf(blockStart);
      const endIndex = src.indexOf(blockEnd);
      src = src.slice(0, startIndex) + helperBlock.trim() + src.slice(endIndex + blockEnd.length);
    } else {
      src = src.replace(safeAttNameAnchor, `${safeAttNameAnchor}${helperBlock}`);
    }

    const instructionVariants = [
      `If the tag has attachment_count, the attachments attribute lists name/type/size — call download_attachment(chat_id, message_id) to fetch them.`,
      `If the tag has attachment_count, the attachments attribute lists name/type/size. Voice messages, video files, and PDFs are auto-downloaded when possible and exposed via readable_attachment_count/readable_attachments in the tag metadata; call download_attachment(chat_id, message_id) for any other attachments you want to inspect.`,
      `If the tag has attachment_count, the attachments attribute lists name/type/size. Voice messages, video files, and PDFs are auto-downloaded when possible and exposed via readable_attachment_count/readable_attachments in the tag metadata; when extraction succeeds, readable_attachments points to transcript/text files that are ready to Read. Call download_attachment(chat_id, message_id) for any other attachments you want to inspect.`,
      `If the tag has attachment_count, the attachments attribute lists name/type/size. Voice messages, video files, and PDFs are auto-downloaded when possible and exposed via readable_attachment_count/readable_attachments in the tag metadata; when extraction succeeds, readable_attachments points to transcript/text files that are ready to Read. If the delivered message content includes a [Readable attachments] block, treat that extracted text as part of the user message and do not say you cannot process the attachment type. Call download_attachment(chat_id, message_id) for any other attachments you want to inspect.`,
      `If the tag has attachment_count, the attachments attribute lists name/type/size. Voice messages, video files, and PDFs are auto-downloaded when possible and exposed via readable_attachment_count/readable_attachments in the tag metadata; when extraction succeeds, readable_attachments points to transcript/text files that are ready to Read. For video attachments, extracted frame paths and any audio transcript are included there. If the delivered message content includes a [Readable attachments] block, treat that extracted text as part of the user message and do not say you cannot process the attachment type. For videos, inspect the extracted frame paths before claiming you cannot understand the visuals. Call download_attachment(chat_id, message_id) for any other attachments you want to inspect.`,
      `If the tag has attachment_count, the attachments attribute lists name/type/size. Voice messages, video files, and PDFs are auto-downloaded when possible and exposed via readable_attachment_count/readable_attachments in the tag metadata; when extraction succeeds, readable_attachments points to transcript/text files that are ready to Read. For video attachments, extracted frame paths and any audio transcript are included there. If the delivered message content includes a [Readable attachments] block, treat that extracted text as part of the user message, inspect any referenced artifacts before replying, and do not say you cannot process the attachment type. For videos, inspect the extracted frame paths before claiming you cannot understand the visuals. Send exactly one final reply per inbound Discord message unless the user explicitly asked for incremental progress updates. Call download_attachment(chat_id, message_id) for any other attachments you want to inspect.`,
    ];
    const instructionsNew = `If the tag has attachment_count, the attachments attribute lists name/type/size. Voice messages, video files, and PDFs are auto-downloaded when possible and exposed via readable_attachment_count/readable_attachments in the tag metadata; when extraction succeeds, readable_attachments points to transcript/text files that are ready to Read. For video attachments, extracted frame paths and any audio transcript are included there. If the delivered message content includes a [Readable attachments] block, treat that extracted text as part of the user message, inspect any referenced artifacts before replying, and do not say you cannot process the attachment type. For videos, inspect the extracted frame paths before claiming you cannot understand the visuals. Send exactly one final reply per inbound Discord message unless the user explicitly asked for incremental progress updates. Call download_attachment(chat_id, message_id) for any other attachments you want to inspect.`;
    const matchedInstruction = instructionVariants.find(value => src.includes(value));
    if (!matchedInstruction) {
      process.stderr.write("discord-channel: instructions anchor not found in server.ts\n");
      process.exit(3);
    }
    src = src.replace(matchedInstruction, instructionsNew);

    const downloadToolVariants = [
      `Download attachments from a specific Discord message to the local inbox. Use after fetch_messages shows a message has attachments (marked with +Natt). Returns file paths ready to Read.`,
      `Download attachments from a specific Discord message to the local inbox. Use after fetch_messages shows a message has attachments (marked with +Natt), or when you want files beyond the auto-downloaded voice/video/PDF set. Returns file paths ready to Read.`,
    ];
    const downloadToolNew = `Download attachments from a specific Discord message to the local inbox. Use after fetch_messages shows a message has attachments (marked with +Natt), or when you want files beyond the auto-downloaded voice/video/PDF set. Returns file paths ready to Read.`;
    const matchedDownloadTool = downloadToolVariants.find(value => src.includes(value));
    if (!matchedDownloadTool) {
      process.stderr.write("discord-channel: download_attachment description anchor not found in server.ts\n");
      process.exit(3);
    }
    src = src.replace(matchedDownloadTool, downloadToolNew);

    const fetchMessagesPattern = / {18}const who = m\.author\.id === me \? [\"\x27]me[\"\x27] : m\.author\.username\n(?: {18}const attKinds = \[\.\.\.new Set\(\[\.\.\.m\.attachments\.values\(\)\]\.map\(attachmentKind\)\)\]\n)? {18}const atts = m\.attachments\.size > 0 \? ` \+\$\{m\.attachments\.size\}att(?:\$\{attKinds\.length > 0 \? ` \[\$\{attKinds\.join\(","\)\}\]` : [\"\x27]{2}\})?` : [\"\x27]{2}/;
    if (!fetchMessagesPattern.test(src)) {
      process.stderr.write("discord-channel: fetch_messages attachment anchor not found in server.ts\n");
      process.exit(3);
    }
    src = src.replace(
      fetchMessagesPattern,
      `                  const who = m.author.id === me ? 'me' : m.author.username
                  const attKinds = [...new Set([...m.attachments.values()].map(attachmentKind))]
                  const atts = m.attachments.size > 0 ? \` +\${m.attachments.size}att\${attKinds.length > 0 ? \` [\${attKinds.join(",")}]\` : ""}\` : ""`,
    );

    const inboundNew = `  // List all attachments in meta, and eagerly extract text for the file
  // types the model can inspect most reliably before delivering the turn.
  const atts: string[] = []
  for (const att of msg.attachments.values()) {
    atts.push(describeAttachment(att))
  }

  let readableAtts: string[] = []
  if (msg.attachments.size > 0) {
    try {
      readableAtts = await downloadReadableAttachments(msg)
    } catch (err) {
      process.stderr.write(\`discord channel: failed to auto-download readable attachments for \${msg.id}: \${err}\\n\`)
    }
  }

  const readableKinds = [...new Set([...msg.attachments.values()].filter(isReadableAttachment).map(attachmentKind))]
  const readableTexts = readableAttachmentText(readableAtts)

  // Attachment listing goes in meta only — an in-content annotation is
  // forgeable by any allowlisted sender typing that string.
  const attachmentTranscriptBlock =
    readableTexts.length > 0
      ? \`\\n\\n[Readable attachments]\\n\${readableTexts.join("\\n")}\`
      : ""
  const baseContent =
    msg.content ||
    (readableKinds.length > 0
      ? \`(\${readableKinds.join("/")} attachment)\`
      : (atts.length > 0 ? "(attachment)" : ""))
  const content =
    readableTexts.length > 0
      ? \`[Readable attachments - inspect before replying]\\n\${readableTexts.join("\\n")}\\n\\n[Original message]\\n\${baseContent}\`
      : baseContent`;
    const inboundPattern = /  \/\/ List all attachments in meta[\s\S]*?  const content =[\s\S]*?\n\n  mcp\.notification\(\{/;
    const legacyPattern = /  \/\/ Attachments are listed \(name\/type\/size\) but not downloaded[\s\S]*?  const content = msg\.content \|\| \(atts\.length > 0 \? [\"\x27]\(attachment\)[\"\x27] : [\"\x27]{2}\)\n\n  mcp\.notification\(\{/;
    if (!inboundPattern.test(src) && !legacyPattern.test(src)) {
      process.stderr.write("discord-channel: inbound attachment anchor not found in server.ts\n");
      process.exit(3);
    }
    if (inboundPattern.test(src)) {
      src = src.replace(inboundPattern, `${inboundNew}\n\n  mcp.notification({`);
    } else {
      src = src.replace(legacyPattern, `${inboundNew}\n\n  mcp.notification({`);
    }

    const metaPattern = /        \.\.\.\(atts\.length > 0 \? \{ attachment_count: String\(atts\.length\), attachments: atts\.join\([\"\x27]; [\"\x27]\) \} : \{\}\),\n(?:        \.\.\.\(readableAtts\.length > 0 \? \{ readable_attachment_count: String\(readableAtts\.length\), readable_attachments: readableAtts\.join\([\"\x27]; [\"\x27]\) \} : \{\}\),\n)?/;
    if (!metaPattern.test(src)) {
      process.stderr.write("discord-channel: attachment meta anchor not found in server.ts\n");
      process.exit(3);
    }
    src = src.replace(
      metaPattern,
      `        ...(atts.length > 0 ? { attachment_count: String(atts.length), attachments: atts.join("; ") } : {}),
        ...(readableAtts.length > 0 ? { readable_attachment_count: String(readableAtts.length), readable_attachments: readableAtts.join("; ") } : {}),`,
    );
    src = src.replace(
      /        \.\.\.\(readableAtts\.length > 0 \? \{ readable_attachment_count: String\(readableAtts\.length\), readable_attachments: readableAtts\.join\("; "\) \} : \{\}\),\n        \.\.\.\(readableAtts\.length > 0 \? \{ readable_attachment_count: String\(readableAtts\.length\), readable_attachments: readableAtts\.join\("; "\) \} : \{\}\),/,
      `        ...(readableAtts.length > 0 ? { readable_attachment_count: String(readableAtts.length), readable_attachments: readableAtts.join("; ") } : {}),`,
    );

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
