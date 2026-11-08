#!/usr/bin/env node
// Races each track at each quality with a computer driving, and reports, in
// a few lines, how heavy it is to draw and whether anything went wrong,
// compared with the saved baseline (design doc 14.2).
//
//   node racing/tools/bench/bench.mjs                 every track, low + high
//   node racing/tools/bench/bench.mjs mine:low frost  just these (track[:quality])
//     --secs N      seconds of racing per run (default 30)
//     --sources     also list the biggest sources of draw calls
//     --update      save these results as the new baseline
//     --export      re-export the game even if it looks current
//
// Draw calls, triangles, objects, physics time, resets and stalls are
// reliable here. Frame rate is not: this machine draws in software, so
// treat fps as a real-device number only (open ?bench on that device).
import { writeFile, readFile, mkdir } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { serve, browser, ensureExport, isError } from './lib.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))
const BASELINE = join(HERE, 'baseline.json')
const LATEST = join(HERE, 'out/latest.json')

const argv = process.argv.slice(2)
const flag = (f) => argv.includes(f)
const opt = (f, d) => (argv.includes(f) ? argv[argv.indexOf(f) + 1] : d)
const secs = Number(opt('--secs', 30))
const named = argv.filter((a, i) => !a.startsWith('--') && argv[i - 1] !== '--secs')
const runs = (named.length ? named : ['meadow', 'mine', 'frost']).flatMap((n) => {
  const [track, q] = n.split(':')
  return (q ? [q] : ['low', 'high']).map((quality) => ({ track, quality, key: `${track}:${quality}` }))
})

// What counts as worse: [metric, allowed rise as a fraction, or absolute].
const WATCH = [['draws', 0.08], ['tris_k', 0.1], ['objects', 0.1], ['physics_ms', 0.25]]

await ensureExport({ force: flag('--export') })
const { url, close } = await serve()
const b = await browser()
const results = {}
for (const r of runs) {
  const t0 = Date.now()
  const page = await (await b.newContext({ viewport: { width: 960, height: 540 } })).newPage()
  const errors = []
  page.on('console', (m) => { if (isError(m.text())) errors.push(m.text().slice(0, 200)) })
  page.on('pageerror', (e) => errors.push(String(e).slice(0, 200)))
  const q = `autodrive&bench=${secs}&quality=${r.quality}` + (r.track === 'meadow' ? '' : `&track=${r.track}`)
  await page.goto(`${url}/racing/index.html?${q}`)
  try {
    await page.waitForFunction(() => window.__bench, null, { timeout: (secs * 6 + 120) * 1000, polling: 1000 })
    results[r.key] = { ...(await page.evaluate(() => window.__bench)), errors: errors.length, error_lines: errors.slice(0, 5), wall_s: Math.round((Date.now() - t0) / 1000) }
  } catch {
    results[r.key] = { failed: 'no result (timed out)', errors: errors.length, error_lines: errors.slice(0, 5) }
  }
  await page.context().close()
}
await b.close()
close()

await mkdir(dirname(LATEST), { recursive: true })
await writeFile(LATEST, JSON.stringify(results, null, 1))
const base = existsSync(BASELINE) ? JSON.parse(await readFile(BASELINE, 'utf8')) : {}

// The report: one line per run, then only what needs attention.
const pad = (s, n) => String(s).padStart(n)
console.log(`${'run'.padEnd(12)}${pad('draws', 7)}${pad('tris', 7)}${pad('obj', 6)}${pad('phys', 6)}${pad('reset', 6)}${pad('stuck', 6)}${pad('laps', 5)}${pad('err', 4)}`)
const problems = []
for (const r of runs) {
  const x = results[r.key]
  if (x.failed) {
    console.log(`${r.key.padEnd(12)}  FAILED: ${x.failed}`)
    problems.push(`${r.key}: ${x.failed}${x.error_lines.length ? ' — ' + x.error_lines[0] : ''}`)
    continue
  }
  const o = base[r.key]
  const delta = (m) => (o && o[m] != null && o[m] !== 0 ? ` ${x[m] >= o[m] ? '+' : ''}${Math.round(((x[m] - o[m]) / o[m]) * 100)}%` : '')
  console.log(`${r.key.padEnd(12)}${pad(x.draws, 7)}${pad(x.tris_k + 'k', 7)}${pad(x.objects, 6)}${pad(x.physics_ms.toFixed(1), 6)}${pad(x.resets, 6)}${pad(x.stuck_s.toFixed(0) + 's', 6)}${pad(x.player_laps, 5)}${pad(x.errors, 4)}` + (o ? `   vs base: draws${delta('draws')} tris${delta('tris_k')}` : ''))
  if (o) for (const [m, frac] of WATCH) if (x[m] > o[m] * (1 + frac) + 0.5) problems.push(`${r.key}: ${m} ${o[m]} → ${x[m]}`)
  if (x.errors) problems.push(`${r.key}: ${x.errors} console errors — ${x.error_lines[0]}`)
  if (x.resets > (o ? o.resets + 2 : 6)) problems.push(`${r.key}: ${x.resets} resets (${Object.entries(x.reset_reasons).map(([k, v]) => `${k} ${v}`).join('; ')})`)
  if (x.stuck_s > 6) problems.push(`${r.key}: a kart was stuck ${x.stuck_s} s`)
  if (o && x.player_laps < o.player_laps) problems.push(`${r.key}: your kart did ${x.player_laps} laps (was ${o.player_laps})`)
}
if (flag('--sources')) {
  for (const r of runs) {
    const x = results[r.key]
    if (!x.sources) continue
    console.log(`\n${r.key} draw calls by source (estimate, opaque pass ≈ ${x.sources.reduce((s, v) => s + v[1], 0)}):`)
    for (const [k, d, n] of x.sources.slice(0, 12)) console.log(`  ${pad(d, 4)}  ${pad(n, 4)} nodes  ${k}`)
  }
}
if (flag('--update')) {
  const merged = { ...base }
  for (const r of runs) if (!results[r.key].failed) { const { sources, error_lines, reset_reasons, ...keep } = results[r.key]; merged[r.key] = keep }
  await writeFile(BASELINE, JSON.stringify(merged, null, 1) + '\n')
  console.log('baseline updated')
}
console.log(problems.length ? `\n${problems.length} to look at:\n  ` + problems.join('\n  ') : `\nall clear${Object.keys(base).length ? ' against the baseline' : ' (no baseline yet: run with --update)'}`)
console.log(`(full results: ${LATEST})`)
process.exit(problems.length ? 1 : 0)
