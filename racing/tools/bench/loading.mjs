#!/usr/bin/env node
// Hold engine downloads to review the actual loading shell before it disappears.
import { mkdir } from 'node:fs/promises'
import { join } from 'node:path'
import { serve, browser, ensureExport, REPO } from './lib.mjs'
await ensureExport()
const server = await serve()
const b = await browser()
const out = join(REPO, 'racing/tools/bench/out/loading')
await mkdir(out, { recursive: true })
try {
  for (const track of ['meadow', 'mine', 'frost']) {
    const page = await b.newPage({ viewport: { width: 1280, height: 720 } })
    let release
    const gate = new Promise(resolve => { release = resolve })
    await page.route(/\.(wasm|pck)(\?|$)/, async route => { await gate; await route.abort() })
    try {
      await page.goto(`${server.url}/racing/index.html?track=${track}`, { waitUntil: 'domcontentloaded' })
      await page.waitForSelector('.racing-loading-caption')
      await page.evaluate(async () => {
        const preload = document.querySelector('link[as="image"]')
        const image = new Image()
        image.src = preload.href
        await image.decode()
        await document.querySelector('.racing-loading-caption img').decode()
        await new Promise(requestAnimationFrame)
      })
      await page.screenshot({ path: join(out, `${track}.png`) })
      console.log(`${track}: actual loading shell captured`)
    } finally { release(); await page.close() }
  }
} finally { await b.close(); server.close() }
