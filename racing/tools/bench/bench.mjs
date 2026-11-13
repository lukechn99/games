#!/usr/bin/env node
// Races each track at each quality with a computer driving, and reports, in
// a few lines, how heavy it is to draw and whether anything went wrong,
// compared with the saved baseline (design doc 14.2).
//
//   node racing/tools/bench/bench.mjs                 every track, low + high
//   node racing/tools/bench/bench.mjs mine:low frost  just these (track[:quality])
//     --secs N      seconds of racing per run (default 30)
//     --profile phone  844×390 CSS px, DPR 3 (desktop default: 960×540 DPR 1)
//     --repeat N    retain N independent samples (default 1)
//     --sources     also list the biggest sources of draw calls
//     --wall N      real seconds a run may take before it stops as partial (300)
//     --update      save these results as the new baseline
//     --export      re-export the game even if it looks current
//
// Draw calls, triangles, objects, resets and stalls describe this workload.
// Physics/process timings also depend on this host and its load. This machine
// renders in software; measure phone FPS by opening ?bench on the phone.
import { writeFile, readFile, mkdir } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { cpus, platform, arch } from 'node:os'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { serve, browser, ensureExport, isError, REPO } from './lib.mjs'

import { baselineEligible, incompatibilities } from './compare.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))
const BASELINE = join(HERE, 'baseline.json')
const LATEST = join(HERE, 'out/latest.json')

const argv = process.argv.slice(2)
const flag = (f) => argv.includes(f)
const opt = (f, d) => (argv.includes(f) ? argv[argv.indexOf(f) + 1] : d)
const secs = Number(opt('--secs', 30))
// Software rendering here is slow: allow time for complete runs, which
// the baseline requires (a phone keeps the game's own 120 s cap).
const wall = Number(opt('--wall', 300))
const profile = opt('--profile', 'desktop')
const repeats = Number(opt('--repeat', 1))
const profiles = {
  desktop: { viewport: { width: 960, height: 540 }, deviceScaleFactor: 1 },
  phone: { viewport: { width: 844, height: 390 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true },
}
if (!profiles[profile] || !Number.isFinite(secs) || secs < 1 || secs > 300 || !Number.isInteger(repeats) || repeats < 1 || repeats > 20) {
  throw new Error('Use --profile desktop|phone, --secs 1..300 and --repeat 1..20')
}
const named = argv.filter((a, i) => !a.startsWith('--') && !['--secs', '--profile', '--repeat', '--wall'].includes(argv[i - 1]))
const runs = (named.length ? named : ['meadow', 'mine', 'frost']).flatMap((n) => {
  const [track, q] = n.split(':')
  return (q ? [q] : ['low', 'high']).map((quality) => ({ track, quality, key: `${track}:${quality}` }))
})

// What counts as worse: [metric, allowed rise as a fraction, or absolute].
const WATCH = [['draws', 0.08], ['tris_k', 0.1], ['objects', 0.1], ['physics_ms', 0.25]]

for (const r of runs) if (!['meadow', 'mine', 'frost'].includes(r.track) || !['low', 'medium', 'high'].includes(r.quality)) throw new Error(`Unknown scenario ${r.key}`)
const exported = await ensureExport({ force: flag('--export') })
const git = (...args) => execFileSync('git', args, { cwd: REPO, encoding: 'utf8' }).trim()
const artifacts = {}
for (const file of ['index.pck', 'index.wasm', 'index.js', 'mobile.js', 'landscape.js', 'tilt.js', 'net.js']) {
  artifacts[file] = createHash('sha256').update(await readFile(join(REPO, 'public/racing', file))).digest('hex')
}
const build = { checkout_commit: git('rev-parse', 'HEAD'), checkout_dirty: !!git('status', '--porcelain'), exported_this_run: exported, artifacts }
const runner = { profile, ...profiles[profile], renderer: 'SwiftShader', platform: platform(), arch: arch(), cpu: cpus()[0]?.model, cpu_count: cpus().length }
const executions = runs.flatMap((r) => Array.from({ length: repeats }, (_, i) => ({ ...r, baselineKey: `${r.key}:${profile}`, key: `${r.key}:${profile}:${i + 1}` })))
const { url, close } = await serve()
const b = await browser()
const results = {}
for (const r of executions) {
  const t0 = Date.now()
  const page = await (await b.newContext(profiles[profile])).newPage()
  const errors = []
  page.on('console', (m) => { if (isError(m.text())) errors.push(m.text().slice(0, 200)) })
  page.on('pageerror', (e) => errors.push(String(e).slice(0, 200)))
  const q = `autodrive&bench=${secs}&benchwall=${wall}&quality=${r.quality}` + (r.track === 'meadow' ? '' : `&track=${r.track}`)
  await page.goto(`${url}/racing/index.html?${q}`)
  try {
    await page.waitForFunction(() => window.__bench, null, { timeout: (wall + 300) * 1000, polling: 1000 })
    results[r.key] = { ...(await page.evaluate(() => window.__bench)), build, runner, browser_version: b.version(), errors: errors.length, error_lines: errors.slice(0, 5), wall_s: Math.round((Date.now() - t0) / 1000) }
  } catch {
    results[r.key] = { failed: 'no result (timed out)', errors: errors.length, error_lines: errors.slice(0, 5) }
  }
  await page.context().close()
}
await b.close()
close()

await mkdir(dirname(LATEST), { recursive: true })
const serialized = JSON.stringify(results, null, 1) + '\n'
await writeFile(LATEST, serialized)
await writeFile(join(dirname(LATEST), new Date().toISOString().replace(/[:.]/g, '-') + '.json'), serialized)
const base = existsSync(BASELINE) ? JSON.parse(await readFile(BASELINE, 'utf8')) : {}

// The report: one line per run, then only what needs attention.
const pad = (s, n) => String(s).padStart(n)
console.log(`${'run'.padEnd(24)}${pad('draws', 7)}${pad('tris', 7)}${pad('obj', 6)}${pad('phys', 6)}${pad('reset', 6)}${pad('stuck', 6)}${pad('done', 5)}${pad('err', 4)}`)
const problems = []
for (const r of executions) {
  const x = results[r.key]
  if (x.failed) {
    console.log(`${r.key.padEnd(24)}  FAILED: ${x.failed}`)
    problems.push(`${r.key}: ${x.failed}${x.error_lines.length ? ' — ' + x.error_lines[0] : ''}`)
    continue
  }
  const previous = base[r.baselineKey]
  const reasons = incompatibilities(x, previous)
  const o = reasons.length ? null : previous
  if (reasons.length) console.log(`${r.key}: baseline comparison skipped (${reasons.join('; ')})`)
  const delta = (m) => (o && o[m] != null && o[m] !== 0 ? ` ${x[m] >= o[m] ? '+' : ''}${Math.round(((x[m] - o[m]) / o[m]) * 100)}%` : '')
  console.log(`${r.key.padEnd(24)}${pad(x.draws, 7)}${pad(x.tris_k + 'k', 7)}${pad(x.objects, 6)}${pad(x.physics_ms.toFixed(1), 6)}${pad(x.resets, 6)}${pad(x.stuck_s.toFixed(0) + 's', 6)}${pad(x.player_completed_laps, 5)}${pad(x.errors, 4)}` + (o ? `   vs base: draws${delta('draws')} tris${delta('tris_k')}` : ''))
  if (o) for (const [m, frac] of WATCH) if (x[m] > o[m] * (1 + frac) + 0.5) problems.push(`${r.key}: ${m} ${o[m]} → ${x[m]}`)
  if (x.errors) problems.push(`${r.key}: ${x.errors} console errors — ${x.error_lines[0]}`)
  if (x.resets > (o ? o.resets + 2 : 6)) problems.push(`${r.key}: ${x.resets} resets (${Object.entries(x.reset_reasons).map(([k, v]) => `${k} ${v}`).join('; ')})`)
  if (x.stuck_s > 6) problems.push(`${r.key}: a kart was stuck ${x.stuck_s} s`)
  if (x.partial) problems.push(`${r.key}: partial (${x.seconds}/${x.requested_seconds} simulation seconds); no comparison`)
  if (!x.valid) problems.push(`${r.key}: interrupted, resized or quality changed; no comparison`)
  if (o && !x.partial && !o.partial && x.player_completed_laps < o.player_completed_laps) problems.push(`${r.key}: your kart did ${x.player_completed_laps} laps (was ${o.player_completed_laps})`)
}
if (flag('--sources')) {
  for (const r of executions) {
    const x = results[r.key]
    if (!x.sources) continue
    console.log(`\n${r.key} draw calls by source (estimate, opaque pass ≈ ${x.sources.reduce((s, v) => s + v[1], 0)}):`)
    for (const [k, d, n] of x.sources.slice(0, 12)) console.log(`  ${pad(d, 4)}  ${pad(n, 4)} nodes  ${k}`)
  }
}
if (flag('--update')) {
  if (repeats !== 1 || executions.some((r) => !baselineEligible(results[r.key]))) {
    problems.push('baseline NOT updated: use one complete, valid, error-free run per scenario')
  } else {
    const merged = { ...base }
    for (const r of executions) {
      const omit = new Set(['sources', 'error_lines', 'reset_reasons', 'wall_frames_ms'])
      merged[r.baselineKey] = Object.fromEntries(Object.entries(results[r.key]).filter(([key]) => !omit.has(key)))
    }
    await writeFile(BASELINE, JSON.stringify(merged, null, 1) + '\n')
    console.log('baseline updated')
  }
}
console.log(problems.length ? `\n${problems.length} to look at:\n  ` + problems.join('\n  ') : '\nrun checks passed; see per-run baseline comparison status above')
console.log(`(full results: ${LATEST})`)
process.exit(problems.length ? 1 : 0)
