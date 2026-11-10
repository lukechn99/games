#!/usr/bin/env node
// Real Web wiring/negative checks. --full also races all three laps; this
// can take tens of minutes on SwiftShader. Real-route coverage is tested
// separately by tests/benchmark_halves.gd at fixed physics speed in CI.
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
  const scenarios = process.argv.includes('--full') ? ['halves', 'medium-interrupted', 'interrupted', 'single'] : ['medium-interrupted', 'interrupted', 'single']
  for (const scenario of scenarios) {
    const page = await b.newPage({ viewport: { width: 640, height: 360 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true })
    const errors = []
    let signalError
    const broken = new Promise(resolve => { signalError = resolve })
    const onError = text => { errors.push(text); console.error(text); signalError() }
    const waitFor = async (fn, timeout) => {
      await Promise.race([page.waitForFunction(fn, null, { timeout, polling: 250 }), broken])
      assert.deepEqual(errors, [])
    }
    await page.addInitScript(() => localStorage.setItem('kw_quality', 'high'))
    page.on('console', m => { if (isError(m.text())) onError(m.text()) })
    page.on('pageerror', e => onError(String(e)))
    console.log(`Starting ${scenario}`)
    await page.goto(`${server.url}/racing/index.html?autodrive&quality=low&${scenario === 'single' ? 'bench=1' : scenario === 'medium-interrupted' ? 'benchmedium' : 'benchqualities'}`)
    if (scenario.endsWith('interrupted')) {
      await waitFor(() => window.__benchStartedAt, 300000)
      await page.setViewportSize({ width: 600, height: 360 })
    }
    await waitFor(() => window.__bench, scenario === 'halves' ? 3600000 : 300000)
    const report = await page.evaluate(() => window.__bench)
    assert.deepEqual(errors, [])
    assert.equal(report.valid, !scenario.endsWith('interrupted'))
    assert.equal(report.partial, scenario.endsWith('interrupted'))
    if (scenario === 'single') {
      assert.equal(report.schema, 2)
      assert.equal(report.quality, 'low')
    } else {
      assert.equal(report.schema, 4)
      assert.equal(report.mode, scenario === 'medium-interrupted' ? 'medium_ablation' : 'track_halves')
      assert.equal(await page.evaluate(() => localStorage.getItem('kw_quality')), 'high')
      if (scenario === 'medium-interrupted') assert.deepEqual(report.order, ['Medium base', 'Medium AA off', 'Medium 900k cap', 'Medium 900k cap', 'Medium AA off', 'Medium base'])
      if (scenario === 'halves') {
        assert.deepEqual(report.results.map(r => r.quality), ['low', 'medium', 'high', 'high', 'medium', 'low'])
        assert.deepEqual(report.results.map(r => r.half), [1, 2, 1, 2, 1, 2])
        assert.deepEqual(report.results.map(r => r.lap), [1, 1, 2, 2, 3, 3])
        assert.ok(report.results.every(r => r.frames > 1 && r.duration_clock === 'track_half'))
        assert.ok(Object.values(report.route_evidence).every(r => r.cave))
      } else {
        assert.ok(report.errors.includes('viewport resized'))
      }
    }
    await writeFile(join(out, `${scenario}.json`), JSON.stringify(report, null, 2))
    await page.screenshot({ path: join(out, `${scenario}.png`) })
    console.log(`PASS ${scenario}: valid=${report.valid}, schema=${report.schema}, no browser/script errors`)
    await page.close()
  }
} finally { await b.close(); server.close() }
