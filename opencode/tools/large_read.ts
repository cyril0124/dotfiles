import { tool } from "@opencode-ai/plugin"
import { resolve, extname } from "path"
import { stat } from "fs/promises"
import { createReadStream } from "fs"
import { createInterface } from "readline"

const BINARY_EXTENSIONS = new Set([
  ".zip", ".tar", ".gz", ".exe", ".dll", ".so", ".class",
  ".jar", ".war", ".7z", ".doc", ".docx", ".xls", ".xlsx",
  ".ppt", ".pptx", ".odt", ".ods", ".odp", ".bin", ".dat",
  ".obj", ".o", ".a", ".lib", ".wasm", ".pyc", ".pyo",
  ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".ico", ".webp",
  ".mp3", ".mp4", ".avi", ".mov", ".mkv", ".flv",
  ".pdf", ".woff", ".woff2", ".ttf", ".eot",
])

function isBinaryByExtension(filepath: string): boolean {
  return BINARY_EXTENSIONS.has(extname(filepath).toLowerCase())
}

async function isBinaryByContent(filepath: string): Promise<boolean> {
  const file = Bun.file(filepath)
  const buffer = await file.arrayBuffer()
  const bytes = new Uint8Array(buffer.slice(0, 4096))

  if (bytes.length === 0) return false

  let nonPrintable = 0
  for (let i = 0; i < bytes.length; i++) {
    if (bytes[i] === 0) return true
    if (bytes[i] < 9 || (bytes[i] > 13 && bytes[i] < 32)) nonPrintable++
  }
  return nonPrintable / bytes.length > 0.3
}

async function readLines(
  filepath: string,
  opts: { offset: number; limit: number | undefined },
): Promise<{ lines: string[]; totalLines: number; hasMore: boolean }> {
  return new Promise((resolve, reject) => {
    const stream = createReadStream(filepath, { encoding: "utf8" })
    const rl = createInterface({ input: stream, crlfDelay: Infinity })

    const lines: string[] = []
    let totalLines = 0
    let hasMore = false

    rl.on("line", (line: string) => {
      totalLines++
      if (totalLines < opts.offset) return
      if (opts.limit !== undefined && lines.length >= opts.limit) {
        hasMore = true
        return
      }
      lines.push(line)
    })

    rl.on("close", () => {
      stream.destroy()
      resolve({ lines, totalLines, hasMore })
    })

    stream.on("error", (err: Error) => {
      rl.close()
      reject(err)
    })
  })
}

export default tool({
  description: `Read a file without the line count or byte size limits of the built-in read tool (which caps at 2000 lines / 50 KB). Reads the full file by default; use offset and limit for range reads. Only use this tool when the user explicitly asks for large_read or requests reading a file that exceeds the built-in read tool's limits. For normal files, prefer the built-in read tool.`,
  args: {
    filePath: tool.schema.string().describe("Absolute or relative path to the file"),
    offset: tool.schema.number().optional().describe("Line number to start reading from (1-indexed). Defaults to 1."),
    limit: tool.schema.number().optional().describe("Maximum number of lines to read. Defaults to all remaining lines."),
  },
  async execute(args, context) {
    const filepath = args.filePath.startsWith("/")
      ? args.filePath
      : resolve(context.directory, args.filePath)

    let fileStat
    try {
      fileStat = await stat(filepath)
    } catch {
      return `Error: File not found: ${filepath}`
    }

    if (fileStat.isDirectory()) {
      return `Error: ${filepath} is a directory. Use the built-in read tool for directories.`
    }

    if (isBinaryByExtension(filepath)) {
      return `Error: Cannot read binary file: ${filepath}`
    }

    if (await isBinaryByContent(filepath)) {
      return `Error: Cannot read binary file: ${filepath}`
    }

    if (args.offset !== undefined && args.offset < 1) {
      return `Error: offset must be >= 1, got ${args.offset}`
    }

    const offset = args.offset ?? 1
    let result
    try {
      result = await readLines(filepath, { offset, limit: args.limit })
    } catch (err: any) {
      return `Error: Failed to read file: ${err.message}`
    }

    if (result.totalLines === 0) {
      return `<path>${filepath}</path>\n<type>file</type>\n<content>\n(Empty file)\n</content>`
    }

    if (offset > result.totalLines) {
      return `Error: offset ${offset} is out of range (file has ${result.totalLines} lines)`
    }

    const lastLine = offset + result.lines.length - 1

    let output = `<path>${filepath}</path>\n<type>file</type>\n<content>\n`
    output += result.lines.map((line, i) => `${offset + i}: ${line}`).join("\n")

    if (result.hasMore) {
      output += `\n\n(Showing lines ${offset}-${lastLine} of ${result.totalLines}. Use offset=${lastLine + 1} to continue.)`
    } else {
      output += `\n\n(End of file - total ${result.totalLines} lines)`
    }
    output += "\n</content>"

    return output
  },
})