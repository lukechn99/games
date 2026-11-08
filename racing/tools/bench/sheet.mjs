#!/usr/bin/env node
// Several game views as ONE small image (a contact sheet), so a visual
// check costs one picture instead of many.
//
//   node racing/tools/bench/sheet.mjs out.png "label|query|seconds" ...
//   e.g. sheet.mjs /tmp/s.png "mine start|autodrive&track=mine|12" \
//                             "mine tunnel|track=mine&cam=600,0,2.5,20|9"
//     --w N     tile width in pixels (default 400; tiles are 16:9)
//     --cols N  tiles per row (default 3)
// Views load two at a time; each is captured after its seconds.
import { serve, browser, ensureExport } from './lib.mjs'

const argv = process.argv.slice(2)
const opt = (f, d) => (argv.includes(f) ? Number(argv[argv.indexOf(f) + 1]) : d)
const w = opt('--w', 400)
const cols = opt('--cols', 3)
const rest = argv.filter((a, i) => !a.startsWith('--') && !['--w', '--cols'].includes(argv[i - 1]))
const [out, ...specs] = rest
if (!out || !specs.length) {
  console.log('usage: sheet.mjs out.png "label|query|seconds" ...')
  process.exit(2)
}
await ensureExport()
const { url, close } = await serve()
const b = await browser()
const shots = new Array(specs.length)
const one = async (i) => {
  const [label, query, s] = specs[i].split('|')
  const ctx = await b.newContext({ viewport: { width: 960, height: 540 } })
  const p = await ctx.newPage()
  await p.goto(`${url}/racing/index.html?${query || ''}`)
  await p.waitForTimeout(Number(s || 15) * 1000)
  shots[i] = { label, png: (await p.screenshot({ type: 'jpeg', quality: 80 })).toString('base64') }
  await ctx.close()
}
for (let i = 0; i < specs.length; i += 2) await Promise.all([one(i), i + 1 < specs.length ? one(i + 1) : null])
// Tile them in a page and capture that.
const h = Math.round((w * 9) / 16)
const rows = Math.ceil(shots.length / cols)
const page = await (await b.newContext({ viewport: { width: cols * w, height: rows * (h + 18) } })).newPage()
await page.setContent(`<body style="margin:0;background:#111;display:grid;grid-template-columns:repeat(${cols},${w}px);font:13px sans-serif;color:#fff">` +
  shots.map((s) => `<div><img src="data:image/jpeg;base64,${s.png}" style="width:${w}px;height:${h}px;display:block"><div style="height:18px;padding-left:4px">${s.label}</div></div>`).join('') + '</body>')
await page.screenshot({ path: out })
await b.close()
close()
console.log(`${out}: ${shots.length} views, ${cols * w}×${rows * (h + 18)}`)
