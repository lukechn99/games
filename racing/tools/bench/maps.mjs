#!/usr/bin/env node
// Repeatable map surface review, with readiness-based screenshots (no guessed
// sleep). node racing/tools/bench/maps.mjs [output-directory] [meadow|mine|frost]
// Saves individual full-size views and a contact sheet. Guides are off in the
// surface views so they cannot hide seams or missing paint.
import { mkdir, writeFile } from 'node:fs/promises'
import { resolve, join } from 'node:path'
import { serve, browser, ensureExport, isError } from './lib.mjs'

const out = resolve(process.argv[2] || 'racing/tools/bench/out/maps')
const tracks = process.argv[3] ? [process.argv[3]] : ['meadow', 'mine', 'frost']
if (tracks.some(t => !['meadow', 'mine', 'frost'].includes(t))) throw new Error('Unknown track')
await mkdir(out, { recursive: true })
await ensureExport()
const server = await serve()
const b = await browser()
const shots = []
try {
  for (const track of tracks) {
    const views = [{ name: 'whole', query: 'map' }, { name: 'terrain', query: 'map&oblique' }]
    if (track === 'frost') views.push(
      { name: 'entry-before-lake', query: 'map=entry' },
      { name: 'exit-after-lake', query: 'map=exit' },
      { name: 'exit-guides', query: 'map=exit&guides=on' },
      { name: 'exit-terrain', query: 'map=exit&oblique' },
    )
    // Reuse the loaded scene: views exercise the same controls as a person,
    // without repeatedly compiling shaders in the software browser.
    const ctx = await b.newContext({ viewport: { width: 1280, height: 800 } })
    const page = await ctx.newPage()
    const errors = []
    page.on('console', m => { if (isError(m.text())) errors.push(m.text()) })
    page.on('pageerror', e => errors.push(String(e)))
    try {
      await page.goto(`${server.url}/racing/index.html?track=${track}&quality=low&map`)
      await page.waitForFunction(() => window.__mapReady, null, { timeout: 180_000 })
      for (const { name, query } of views) {
        const preset = query.includes('map=entry') ? 'entry' : query.includes('map=exit') ? 'exit' : 'whole'
        const desired = { preset, oblique: query.includes('oblique'), guides: query.includes('guides=on') }
        await page.keyboard.press(preset === 'entry' ? '2' : preset === 'exit' ? '3' : '1')
        await page.waitForFunction(p => window.__mapState?.preset === p, preset)
        for (const [key, field] of [['o', 'oblique'], ['l', 'guides']]) {
          if (await page.evaluate(f => window.__mapState[f], field) !== desired[field]) {
            await page.keyboard.press(key)
            await page.waitForFunction(({ field, value }) => window.__mapState[field] === value, { field, value: desired[field] })
          }
        }
        if (errors.length) throw new Error(errors.join('\n'))
        const file = `${track}-${name}.png`
        const png = await page.screenshot({ path: join(out, file) })
        shots.push({ name: `${track} ${name}`, file, data: png.toString('base64') })
        console.log(file)
      }
    } finally { await ctx.close() }
  }
  const page = await b.newPage({ viewport: { width: 1280, height: Math.ceil(shots.length / 2) * 424 } })
  const body = `<body style="margin:0;background:#151923;color:white;font:16px sans-serif;display:grid;grid-template-columns:repeat(2,640px)">${shots.map(s => `<div><img width="640" height="400" src="data:image/png;base64,${s.data}" style="display:block"><div style="height:24px">${s.name}</div></div>`).join('')}</body>`
  await page.setContent(body)
  await page.screenshot({ path: join(out, 'contact-sheet.png') })
  await writeFile(join(out, 'index.html'), `<title>Map review</title><body style="background:#151923;color:white;font:18px sans-serif">${shots.map(s => `<h2>${s.name}</h2><a href="${s.file}"><img src="${s.file}" style="max-width:100%"></a>`).join('')}`)
  console.log(`Map review: ${out}/index.html`)
} finally {
  await b.close()
  server.close()
}
