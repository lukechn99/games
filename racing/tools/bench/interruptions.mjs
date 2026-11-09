#!/usr/bin/env node
// Rendered integration check: browser interruption -> Godot callback -> an
// invalid benchmark, even when the interruption lasts less than one frame.
import assert from 'node:assert/strict'
import { serve, browser, ensureExport, isError } from './lib.mjs'

await ensureExport()
const server = await serve()
const b = await browser()
try {
  const page = await b.newPage({ viewport: { width: 960, height: 540 } })
  const errors = []
  page.on('console', (m) => { if (isError(m.text())) errors.push(m.text()) })
  page.on('pageerror', (e) => errors.push(String(e)))
  await page.goto(`${server.url}/racing/index.html?track=frost&quality=low&autodrive&bench=3`)
  await page.waitForFunction(() => window.__benchStartedAt, null, { timeout: 180000 })
  const suspended = await page.evaluate(() => {
    window.dispatchEvent(new Event('blur'))
    const held = window.racingMobile.suspended
    window.dispatchEvent(new Event('focus'))
    document.dispatchEvent(new Event('touchcancel'))
    return held
  })
  assert.equal(suspended, true)
  await page.waitForFunction(() => window.__bench, null, { timeout: 180000 })
  const result = await page.evaluate(() => window.__bench)
  assert.equal(result.valid, false, 'brief interruptions must invalidate the run')
  assert.ok(result.interruptions >= 3)
  assert.equal(result.partial, false)
  assert.deepEqual(errors, [])
  console.log(`PASS: rendered run recorded ${result.interruptions} interruptions, invalid=true, no script/browser errors`)
} finally {
  await b.close()
  server.close()
}
