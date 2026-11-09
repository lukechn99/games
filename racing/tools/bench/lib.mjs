// Shared by the bench tools: a static server for public/, a headless
// browser that renders WebGL in software, and a check that the web export
// in public/racing is newer than the game's sources (re-exporting if not).
import { createServer } from 'node:http'
import { readFile, stat, readdir, mkdir, copyFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { join, extname, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { homedir } from 'node:os'
import { chromium } from 'playwright-core'

export const REPO = join(dirname(fileURLToPath(import.meta.url)), '../../..')
export const GAME = join(REPO, 'racing')
const PUBLIC = join(REPO, 'public')
const GODOT = process.env.GODOT || join(homedir(), 'godot/godot')

const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.jpg': 'image/jpeg', '.json': 'application/json', '.css': 'text/css' }

/** Serves public/ on a free port. Returns { url, close }. */
export async function serve() {
  const server = createServer(async (req, res) => {
    let path = decodeURIComponent(new URL(req.url, 'http://x').pathname)
    if (path.endsWith('/')) path += 'index.html'
    try {
      const body = await readFile(join(PUBLIC, path))
      // Godot's threads need these; harmless otherwise.
      res.writeHead(200, { 'Content-Type': TYPES[extname(path)] || 'application/octet-stream', 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp' })
      res.end(body)
    } catch {
      res.writeHead(404).end()
    }
  })
  await new Promise((r) => server.listen(0, '127.0.0.1', r))
  return { url: `http://127.0.0.1:${server.address().port}`, close: () => server.close() }
}

/** A headless Chrome with software WebGL (no GPU here). */
export async function browser() {
  const args = ['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist']
  const executablePath = ['/usr/bin/google-chrome', '/usr/bin/chromium'].find(existsSync)
  return chromium.launch({ executablePath, args })
}

async function newest(dir, exts) {
  let t = 0
  for (const e of await readdir(dir, { withFileTypes: true })) {
    if (e.name.startsWith('.') || e.name === 'tools' || e.name === 'tests') continue
    const p = join(dir, e.name)
    if (e.isDirectory()) t = Math.max(t, await newest(p, exts))
    else if (exts.includes(extname(e.name))) t = Math.max(t, (await stat(p)).mtimeMs)
  }
  return t
}

/** Re-exports the game to public/racing when a source is newer than it. */
export async function ensureExport({ force = false, log = console.log } = {}) {
  const pck = join(PUBLIC, 'racing/index.pck')
  const src = await newest(GAME, ['.gd', '.gdshader', '.tscn', '.tres', '.glb', '.png', '.jpg', '.woff2', '.godot', '.cfg', '.js'])
  const built = existsSync(pck) ? (await stat(pck)).mtimeMs : 0
  if (!force && built > src) return false
  log('exporting the game (sources changed)…')
  const t0 = Date.now()
  await mkdir(dirname(pck), { recursive: true })
  execFileSync(GODOT, ['--headless', '--path', GAME, '--import'], { stdio: 'ignore' })
  execFileSync(GODOT, ['--headless', '--path', GAME, '--export-release', 'Web', join(PUBLIC, 'racing/index.html')], { stdio: 'ignore' })
  for (const file of ['tilt.js', 'net.js']) await copyFile(join(GAME, 'web', file), join(PUBLIC, 'racing', file))
  log(`  exported in ${((Date.now() - t0) / 1000).toFixed(0)} s`)
  return true
}

/** Console lines that mean something broke. */
export function isError(text) {
  return /SCRIPT ERROR|USER ERROR|^ERROR|Uncaught|Parse Error|Invalid (call|access|get|set)/.test(text)
}
