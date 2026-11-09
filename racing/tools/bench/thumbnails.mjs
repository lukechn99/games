#!/usr/bin/env node
// Actual Low-quality Web captures; rerun after track or art changes.
import { mkdir, readFile } from 'node:fs/promises'
import { join, resolve } from 'node:path'
import { serve, browser, ensureExport, isError, REPO } from './lib.mjs'

const out = resolve(process.argv[2] || join(REPO, 'public/tracks'))
await mkdir(out, { recursive: true })
await ensureExport()
const server = await serve()
const b = await browser()
try {
  for (const [name, query] of [
    ['meadow', 'cam=140,-18,8,22'],
    ['mine', 'track=mine&cam=100,28,14,40'],
    ['frost', 'track=frost&autodrive&intro&introt=0&introtrace'],
  ]) {
    const page = await b.newPage({ viewport: { width: 960, height: 540 } })
    const errors = []
    let ready
    let timer
    const warm = new Promise((resolve, reject) => {
      ready = resolve
      timer = setTimeout(() => reject(new Error(`${name}: shader warm-up timed out`)), 180000)
    })
    page.on('console', m => {
      if (isError(m.text())) errors.push(m.text())
      if (m.text().includes('shader warm-up:')) ready()
    })
    page.on('pageerror', e => errors.push(String(e)))
    try {
      await page.goto(`${server.url}/racing/index.html?quality=low&${query}`)
      await warm
      clearTimeout(timer)
      await page.evaluate(async () => {
        for (let i = 0; i < 10; i++) await new Promise(requestAnimationFrame)
      })
      if (errors.length) throw new Error(errors.join('\n'))
      await page.screenshot({ path: join(out, `${name}.jpg`), type: 'jpeg', quality: 88 })
      console.log(`${name}.jpg: actual Web capture, no script/browser errors`)
    } finally { clearTimeout(timer); await page.close() }
  }
  const page = await b.newPage({ viewport: { width: 960, height: 540 } })
  const panels = []
  for (const [name, label] of [['meadow', 'Meadow'], ['mine', 'Mine'], ['frost', 'Frost']]) {
    const data = (await readFile(join(out, `${name}.jpg`))).toString('base64')
    panels.push(`<div style="position:relative"><img src="data:image/jpeg;base64,${data}" style="width:320px;height:540px;object-fit:cover;display:block"><span style="position:absolute;bottom:0;left:0;right:0;padding:16px;background:#101820b8;color:white;font:600 24px sans-serif;text-align:center">${label}</span></div>`)
  }
  await page.setContent(`<body style="margin:0;display:flex;background:#101820">${panels.join('')}</body>`)
  await page.screenshot({ path: join(out, 'gp.jpg'), type: 'jpeg', quality: 88 })
  console.log('gp.jpg: composite of the three current track captures')
} finally { await b.close(); server.close() }
