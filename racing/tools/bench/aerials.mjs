#!/usr/bin/env node
// Real, clean oblique aerials for the map loading screen, separate from
// chooser beauty shots. Rebuild after track/art changes.
import { join } from 'node:path'
import { serve, browser, ensureExport, isError, REPO } from './lib.mjs'
await ensureExport()
const server = await serve()
const b = await browser()
try {
  for (const track of ['meadow', 'mine', 'frost']) {
    const page = await b.newPage({ viewport: { width: 1280, height: 720 } })
    const errors = []
    page.on('console', m => { if (isError(m.text())) errors.push(m.text()) })
    page.on('pageerror', e => errors.push(String(e)))
    await page.goto(`${server.url}/racing/index.html?track=${track}&quality=low&map&oblique&clean`)
    await page.waitForFunction(() => window.__mapReady, null, { timeout: 240000 })
    if (errors.length) throw new Error(errors.join('\n'))
    await page.screenshot({ path: join(REPO, `public/tracks/aerial-${track}.jpg`), type: 'jpeg', quality: 86 })
    console.log(`${track}: clean actual Web aerial, no script/browser errors`)
    await page.close()
  }
} finally { await b.close(); server.close() }
