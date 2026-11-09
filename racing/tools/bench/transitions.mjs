#!/usr/bin/env node
// Rotation DOM checks plus captures of the real animated camera handoff.
import assert from 'node:assert/strict'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { join, resolve } from 'node:path'
import { serve, browser, ensureExport, isError, GAME } from './lib.mjs'

const out = resolve(process.argv[2] || 'racing/tools/bench/out/transitions')
await mkdir(out, { recursive: true })
await ensureExport()
const server = await serve()
const b = await browser()
const captures = []
try {
  // Deliberately keep an old portrait canvas while the physical screen reports
  // landscape, as can happen during a mobile iframe's orientation transition.
  const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true })
  const page = await ctx.newPage()
  await page.setContent('<meta name="viewport" content="width=device-width,user-scalable=no,initial-scale=1"><canvas id="canvas" style="width:390px;height:844px"></canvas>')
  await page.evaluate(() => {
    const orientation = Object.assign(new EventTarget(), { type: 'portrait-primary' })
    Object.defineProperty(screen, 'orientation', { value: orientation })
    Object.defineProperty(window, 'DeviceMotionEvent', { value: undefined })
  })
  await page.addScriptTag({ content: await readFile(join(GAME, 'web/landscape.js'), 'utf8') })
  await page.addScriptTag({ content: await readFile(join(GAME, 'web/tilt.js'), 'utf8') })
  assert.equal(await page.locator('#racing-rotate').isVisible(), true)
  await page.screenshot({ path: join(out, 'portrait-prompt.png') })
  const hiddenImmediately = await page.evaluate(() => {
    screen.orientation.type = 'landscape-primary'
    screen.orientation.dispatchEvent(new Event('change'))
    return getComputedStyle(document.getElementById('racing-rotate')).display === 'none'
  })
  assert.equal(hiddenImmediately, true)
  await page.setViewportSize({ width: 844, height: 390 })
  const bounds = await page.locator('#canvas').boundingBox()
  assert.ok(Math.abs(bounds.width - 844) < 0.5)
  assert.ok(Math.abs(bounds.height - 390) < 0.5)
  // Back to portrait, including a smaller viewport with browser bars visible.
  await page.setViewportSize({ width: 320, height: 480 })
  await page.evaluate(() => {
    screen.orientation.type = 'portrait-primary'
    screen.orientation.dispatchEvent(new Event('change'))
  })
  const card = await page.locator('#racing-rotate').boundingBox()
  const text = await page.locator('#racing-rotate > div').boundingBox()
  assert.ok(Math.abs(card.width - 320) < 0.5)
  assert.ok(Math.abs(card.height - 480) < 0.5)
  assert.ok(text.x >= 0 && text.y >= 0 && text.x + text.width <= 320 && text.y + text.height <= 480)
  await page.screenshot({ path: join(out, 'portrait-small.png') })
  await ctx.close()
  console.log('PASS: prompt hides synchronously on rotation, visible bounds fit, canvas CSS resizes before the engine')

  const game = await b.newPage({ viewport: { width: 960, height: 540 } })
  const errors = []
  game.on('console', m => { if (isError(m.text())) { errors.push(m.text()); console.error(m.text()) } })
  game.on('pageerror', e => errors.push(String(e)))
  await game.goto(`${server.url}/racing/index.html?autodrive&intro&introreview&track=frost&quality=low`)
  for (let i = 0; i < 4; i++) {
    await game.waitForFunction(i => window.__introFrame?.index === i || window.__introReport, i, { timeout: 180000, polling: 100 })
    // Let the held pose reach the compositor before reading the pixels.
    await game.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))
    const frame = await game.evaluate(() => window.__introFrame)
    const file = i === 3 ? 'frost-chase-handoff.png' : `frost-descent-${i + 1}.png`
    const png = await game.screenshot({ path: join(out, file) })
    captures.push({ label: i === 3 ? 'Chase-camera handoff' : `Descent ${(frame.t * 100).toFixed(1)}%`, png: png.toString('base64') })
    console.log(`captured ${file} at ${(frame.t * 100).toFixed(1)}%`)
    if (i < 3) await game.evaluate(() => { window.__introHold = false })
  }
  const report = await game.evaluate(() => window.__introReport)
  assert.ok(report.handoff_jump_m < 0.001)
  assert.ok(report.samples.at(-1).rest_distance < 0.001)
  assert.deepEqual(errors, [])
  await writeFile(join(out, 'intro-trace.json'), JSON.stringify(report, null, 2))
  await game.close()
  const sheet = await b.newPage({ viewport: { width: 1280, height: 768 } })
  const html = `<body style="margin:0;background:#171c2e;color:white;font:18px sans-serif;display:grid;grid-template-columns:640px 640px">${captures.map(c => `<div><img width="640" height="360" src="data:image/png;base64,${c.png}" style="display:block"><div style="height:24px">${c.label}</div></div>`).join('')}</body>`
  await sheet.setContent(html)
  await sheet.screenshot({ path: join(out, 'descent-review.png') })
  console.log(`PASS: rendered Frost camera handoff ${report.handoff_jump_m.toFixed(6)} m, no browser/script errors. Captures: ${out}`)
} finally {
  await b.close()
  server.close()
}
