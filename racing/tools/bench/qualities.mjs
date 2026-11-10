#!/usr/bin/env node
// Integration checks for the real Web quality sweep and legacy single sample.
import assert from 'node:assert/strict'
import { mkdir, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { serve, browser, ensureExport, isError } from './lib.mjs'

await ensureExport()
const server = await serve()
const b = await browser()
const out = 'racing/tools/bench/out/qualities'
await mkdir(out, { recursive: true })
try {
  for (const scenario of ['sweep', 'interrupted', 'single']) {
    const page = await b.newPage({ viewport: { width: 640, height: 360 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true })
    const errors = []
    await page.addInitScript(() => localStorage.setItem('kw_quality', 'medium'))
    page.on('console', m => { if (isError(m.text())) { errors.push(m.text()); console.error(m.text()) } })
    page.on('pageerror', e => errors.push(String(e)))
    console.log(`Starting ${scenario}`)
    await page.goto(`${server.url}/racing/index.html?autodrive&bench=1&quality=low${scenario === 'single' ? '' : '&benchqualities'}`)
    if (scenario === 'interrupted') {
      await page.waitForFunction(() => window.__benchStartedAt, null, { timeout: 180000 })
      // Resize after a sample starts; the benchmark must not silently accept it.
      await page.setViewportSize({ width: 600, height: 360 })
    }
    await page.waitForFunction(() => window.__bench, null, { timeout: 240000, polling: 250 })
    const report = await page.evaluate(() => window.__bench)
    assert.deepEqual(errors, [])
    assert.equal(report.valid, scenario !== 'interrupted')
    assert.equal(report.partial, false)
    if (scenario === 'single') {
      assert.equal(report.schema, 2)
      assert.equal(report.quality, 'low')
    } else {
      assert.equal(report.schema, 3)
      assert.equal(report.rounds, 2)
      assert.equal(report.requested_seconds_per_sample, 1)
      assert.deepEqual(report.results.map(r => r.quality), ['low', 'medium', 'high', 'low', 'medium', 'high'])
      assert.deepEqual(report.results.map(r => r.round), [1, 1, 1, 2, 2, 2])
      assert.deepEqual(report.results.map(r => r.phase), [1, 2, 3, 4, 5, 6])
      assert.ok(report.results.every(r => r.frames > 0 && r.wall_frames_ms.length > 0))
      assert.ok(report.results.every(r => r.duration_clock === 'wall' && r.wall_race_s >= 1))
      assert.ok(report.results[2].scale_3d > report.results[0].scale_3d)
      if (scenario === 'sweep') assert.equal(report.results[0].scale_3d, report.results[3].scale_3d)
      assert.equal(report.different_track_sections, true)
      assert.ok(report.results[1].start_progress.offset_m !== report.results[0].start_progress.offset_m)
      assert.equal(await page.evaluate(() => localStorage.getItem('kw_quality')), 'medium')
    }
    await writeFile(join(out, `${scenario}.json`), JSON.stringify(report, null, 2))
    if (scenario === 'sweep') await page.screenshot({ path: join(out, 'phone-summary.png') })
    console.log(`PASS ${scenario}: valid=${report.valid}, schema=${report.schema}, no browser/script errors`)
    await page.close()
  }
} finally { await b.close(); server.close() }
