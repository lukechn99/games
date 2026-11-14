#!/usr/bin/env node
// One command to check a change (design doc 14.3). Prints about ten lines
// and, only if a picture changed, writes one image to look at.
//
//   node racing/tools/verify/verify.mjs            the tracks your change touches
//   node racing/tools/verify/verify.mjs frost      just these tracks
//   node racing/tools/verify/verify.mjs all        every track
//     --approve     save the pictures taken now as the approved ones
//     --no-tests    skip the test suites (when you have just run them)
//
// What it runs: the test suites; a fast race per track with nothing drawn
// (lap times, resets, stuck karts, routes and items used, freezes); a tour
// of each track's fixed viewpoints in the browser build (draw calls and
// triangles against budgets.json, and a picture of each compared with the
// approved one in golden/); and the download size.
// Exit status: 1 if anything is over budget or broken; 0 otherwise
// (changed pictures alone are "look", not a failure).
import { readFile, writeFile, mkdir, copyFile, stat, readdir } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { execFile, execFileSync } from 'node:child_process'
import { promisify } from 'node:util'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { homedir } from 'node:os'
import { serve, browser, ensureExport, isError, REPO, GAME } from '../bench/lib.mjs'

const run = promisify(execFile)
const HERE = dirname(fileURLToPath(import.meta.url))
const OUT = join(HERE, 'out')
const GOLDEN = join(HERE, 'golden')
const GODOT = process.env.GODOT || join(homedir(), 'godot/godot')
const budgets = JSON.parse(await readFile(join(HERE, 'budgets.json'), 'utf8'))
const ALL = Object.keys(budgets.tracks)

const argv = process.argv.slice(2)
const flag = (f) => argv.includes(f)
const named = argv.filter((a) => !a.startsWith('--'))
const t0 = Date.now()

// Which tracks does this change touch? A track's own file means that track;
// anything else in the game means all of them; nothing in the game, none.
function changedFiles() {
  const git = (...a) => execFileSync('git', a, { cwd: REPO, encoding: 'utf8' }).split('\n').filter(Boolean)
  const files = new Set([...git('status', '--porcelain').map((l) => l.slice(3)), ...git('diff', '--name-only', 'HEAD~1', 'HEAD')])
  return [...files]
}
const changed = changedFiles()
let tracks
let why
if (named.includes('all')) { tracks = ALL; why = 'all tracks' }
else if (named.length) { tracks = named; why = 'as asked' }
else {
  const game = changed.filter((f) => f.startsWith('racing/') && !f.startsWith('racing/tools/verify/golden') && !f.startsWith('racing/tools/verify/out'))
  const own = game.map((f) => (f.match(/scripts\/track\/([a-z]+)_track\.gd$/) || [])[1])
  if (!game.length) { tracks = []; why = 'no game files changed' }
  else if (own.every((t) => t && ALL.includes(t))) { tracks = [...new Set(own)]; why = 'changed: ' + game.map((f) => f.split('/').pop()).join(', ') }
  else { tracks = ALL; why = 'changed: shared game files' }
}
const siteChanged = changed.some((f) => !f.startsWith('racing/') && !f.startsWith('docs/'))

const lines = []
let failed = false
const add = (status, name, text) => { lines.push(`${status.padEnd(5)} ${name.padEnd(11)} ${text}`); if (status === 'FAIL' || status === 'OVER') failed = true }

// 1. The fast race (first, alone: it times each step).
const races = {}
if (tracks.length) {
  try {
    const { stdout } = await run(GODOT, ['--headless', '--path', GAME, '--import'], { maxBuffer: 1 << 26 }).then(() =>
      run(GODOT, ['--headless', '--path', GAME, '--fixed-fps', '60', '-s', 'tests/race_report.gd'], { env: { ...process.env, KW_TRACKS: tracks.join(',') }, maxBuffer: 1 << 26, timeout: 900000 }))
    for (const l of stdout.split('\n')) if (l.startsWith('[race] ')) { const r = JSON.parse(l.slice(7)); races[r.track] = r }
    if (/SCRIPT ERROR/.test(stdout)) add('FAIL', 'race', 'script error: ' + stdout.split('\n').find((l) => l.includes('SCRIPT ERROR')).slice(0, 140))
  } catch (e) { add('FAIL', 'race', String(e.message).split('\n')[0].slice(0, 160)) }
}

// 2. Tests (in the background) while the browser tours the viewpoints.
const tests = flag('--no-tests') ? null : run(join(GAME, 'tools/check.sh'), [siteChanged || !tracks.length ? 'all' : 'game'], { cwd: REPO, maxBuffer: 1 << 26 }).then((r) => ({ ok: true, out: r.stdout }), (e) => ({ ok: false, out: (e.stdout || '') + (e.stderr || '') }))

const spots = {}
const pictures = []       // {track, name, changed (percent) | null (new), now, approved}
if (tracks.length) {
  await ensureExport({ log: () => {} })
  const { url, close } = await serve()
  const b = await browser()
  const tour = async (track) => {
    const page = await (await b.newContext({ viewport: { width: 480, height: 270 } })).newPage()
    const errors = []
    page.on('console', (m) => { if (isError(m.text())) errors.push(m.text().slice(0, 160)) })
    await page.goto(`${url}/racing/index.html?spots&quality=low` + (track === 'meadow' ? '' : `&track=${track}`))
    await mkdir(join(OUT, track), { recursive: true })
    try {
      for (let i = 0; ; i++) {
        const next = await page.waitForFunction((n) => (window.__spot && window.__spot.i === n ? window.__spot.name : window.__spots ? '#done' : null), i, { timeout: 240000, polling: 200 })
        const name = await next.jsonValue()
        if (name === '#done') break
        const now = join(OUT, track, name + '.jpg')
        await page.screenshot({ path: now, type: 'jpeg', quality: 78 })
        pictures.push({ track, name, now, approved: join(GOLDEN, track, name + '.jpg') })
        await page.evaluate((n) => { window.__spot_ack = n }, i)
      }
      spots[track] = { ...(await page.evaluate(() => window.__spots)), errors }
    } catch { spots[track] = { failed: errors[0] || 'the viewpoint tour did not finish', errors } }
    await page.context().close()
  }
  for (let i = 0; i < tracks.length; i += 2) await Promise.all(tracks.slice(i, i + 2).map(tour))

  // Compare each picture with its approved one (in a blank page's canvas).
  const page = await (await b.newContext()).newPage()
  const b64 = async (f) => 'data:image/jpeg;base64,' + (await readFile(f)).toString('base64')
  for (const p of pictures) {
    if (!existsSync(p.approved)) { p.changed = null; continue }
    p.changed = await page.evaluate(async ([a, c]) => {
      const load = (src) => new Promise((res) => { const im = new Image(); im.onload = () => res(im); im.src = src })
      const [ia, ib] = await Promise.all([load(a), load(c)])
      if (ia.width !== ib.width || ia.height !== ib.height) return 100
      const px = (im) => { const cv = document.createElement('canvas'); cv.width = im.width; cv.height = im.height; const x = cv.getContext('2d'); x.drawImage(im, 0, 0); return x.getImageData(0, 0, im.width, im.height).data }
      const da = px(ia), db = px(ib); let n = 0
      for (let i = 0; i < da.length; i += 4) if (Math.max(Math.abs(da[i] - db[i]), Math.abs(da[i + 1] - db[i + 1]), Math.abs(da[i + 2] - db[i + 2])) > 36) n++
      return (100 * n) / (da.length / 4)
    }, [await b64(p.approved), await b64(p.now)])
  }
  // One sheet of the pictures that changed: approved on the left, now on the right.
  const look = pictures.filter((p) => p.changed === null || p.changed > budgets.picture_changed_percent)
  if (look.length && !flag('--approve')) {
    const cells = []
    for (const p of look.slice(0, 12)) cells.push(`<div><div class="t">${p.track} ${p.name}: ${p.changed === null ? 'new' : p.changed.toFixed(1) + '% changed'}</div><div class="r">${p.changed === null ? '<div class="none">no approved picture</div>' : `<img src="${await b64(p.approved)}">`}<img src="${await b64(p.now)}"></div></div>`)
    // New pictures only: a plain grid of them. Changed ones: before and after, side by side.
    const fresh = look.every((p) => p.changed === null)
    const cols = fresh ? 4 : look.length > 3 ? 2 : 1
    const w = fresh ? 330 : 660
    await page.setViewportSize({ width: cols * w, height: 100 })
    await page.setContent(`<style>body{margin:0;background:#111;color:#fff;font:13px sans-serif;display:grid;grid-template-columns:repeat(${cols},${w}px)}.t{padding:4px 6px}.r{display:flex}img,.none{width:330px;height:186px;display:block}.none{display:${fresh ? 'none' : 'grid'};place-items:center;color:#888}</style>` + cells.join(''))
    await page.screenshot({ path: join(OUT, 'sheet.png'), fullPage: true })
  }
  if (flag('--approve')) for (const p of pictures) { await mkdir(dirname(p.approved), { recursive: true }); await copyFile(p.now, p.approved) }
  await b.close()
  close()
}

// 3. The verdict.
if (tests) {
  const r = await tests
  const ok = r.out.split('\n').filter((l) => l.startsWith('ok '))
  const bad = r.out.split('\n').filter((l) => l.startsWith('FAIL'))
  const count = (name) => ((r.out.match(new RegExp(`ok +${name} +\\((\\d+) passed|ok +${name} +\\(Tests +(\\d+)`)) || []).slice(1).find(Boolean))
  if (r.ok && !bad.length) add('ok', 'tests', `${count('game') || '?'} game` + (count('vitest') ? `, ${count('vitest')} site` : '') + `, ${ok.length} suites`)
  else add('FAIL', 'tests', (bad[0] || r.out.split('\n').find(Boolean) || 'did not run').slice(0, 150))
}
for (const track of tracks) {
  const r = races[track]
  const lim = { ...budgets.default, ...budgets.tracks[track] }
  if (r) {
    const problems = []
    if (r.finished < r.karts) problems.push(`${r.karts - r.finished} karts never finished`)
    if (r.resets > lim.resets) problems.push(`${r.resets} resets (${Object.entries(r.reset_reasons).map(([k, v]) => `${k}: ${v}`).join('; ').slice(0, 90)})`)
    if (r.stuck_s > lim.stuck_s) problems.push(`a kart stuck ${r.stuck_s} s`)
    if (r.lap_max > r.lap_min * lim.lap_spread) problems.push(`slowest lap ${r.lap_max} s is over ${lim.lap_spread}× the fastest`)
    if (r.step_max_ms > lim.freeze_ms) problems.push(`a ${r.step_max_ms} ms freeze at ${r.step_max_at_s} s`)
    const unused = Object.entries(r.routes).filter(([, n]) => n === 0).map(([k]) => k)
    if (unused.length) problems.push(`route never used: ${unused.join(', ')}`)
    add(problems.length ? 'FAIL' : 'ok', `${track} race`, problems.length ? problems.join('; ') : `${r.karts} karts, ${r.laps} laps, ${r.resets} resets, laps ${r.lap_min} to ${r.lap_max} s, routes ${Object.entries(r.routes).map(([k, n]) => `${k} ${n}`).join(' ')}, items ${Object.values(r.items).reduce((a, c) => a + c, 0)}`)
  }
  const s = spots[track]
  if (!s) continue
  if (s.failed) { add('FAIL', `${track} views`, s.failed); continue }
  const judged = s.spots.filter((c) => !(budgets.unjudged_views || []).includes(c.name))
  const worst = (k) => judged.reduce((a, c) => (c[k] > a[k] ? c : a))
  const range = (k) => `${Math.min(...judged.map((c) => c[k]))} to ${Math.max(...judged.map((c) => c[k]))}`
  const over = judged.filter((c) => c.draws > lim.draws).map((c) => `${c.name} ${c.draws}`)
  add(over.length ? 'OVER' : 'ok', `${track} draws`, over.length ? `${over.join(', ')} (budget ${lim.draws}); all ${s.spots.length} viewpoints ${range('draws')}` : `${range('draws')} over ${judged.length} viewpoints, most at ${worst('draws').name} (budget ${lim.draws})`)
  const overT = judged.filter((c) => c.tris_k > lim.tris_k).map((c) => `${c.name} ${c.tris_k}k`)
  add(overT.length ? 'OVER' : 'ok', `${track} tris`, overT.length ? `${overT.join(', ')} (budget ${lim.tris_k}k)` : `most ${worst('tris_k').tris_k}k at ${worst('tris_k').name} (budget ${lim.tris_k}k)`)
  if (s.errors.length) add('FAIL', `${track} errors`, `${s.errors.length} in the console: ${s.errors[0]}`)
}
if (tracks.length) {
  let bytes = 0
  for (const f of await readdir(join(REPO, 'public/racing'))) if (/\.(pck|wasm|js)$/.test(f)) bytes += (await stat(join(REPO, 'public/racing', f))).size
  const mb = bytes / 1048576
  add(mb > budgets.download_mb ? 'OVER' : 'ok', 'download', `${mb.toFixed(1)} MB (budget ${budgets.download_mb})`)
  const look = pictures.filter((p) => p.changed === null || p.changed > budgets.picture_changed_percent)
  if (flag('--approve')) add('ok', 'pictures', `${pictures.length} approved`)
  else if (look.length) add('look', 'pictures', `${look.length} of ${pictures.length} ${look.some((p) => p.changed !== null) ? 'changed' : 'new'}: ${look.slice(0, 6).map((p) => `${p.track} ${p.name}${p.changed === null ? '' : ' ' + p.changed.toFixed(0) + '%'}`).join(', ')}${look.length > 6 ? '…' : ''}  → ${join(OUT, 'sheet.png')}`)
  else add('ok', 'pictures', `${pictures.length} viewpoints match the approved pictures`)
}
await mkdir(OUT, { recursive: true })
await writeFile(join(OUT, 'verify.json'), JSON.stringify({ tracks, races, spots, pictures: pictures.map(({ track, name, changed }) => ({ track, name, changed })) }, null, 1))
const secs = Math.round((Date.now() - t0) / 1000)
console.log(`verify  ${tracks.join(' ') || '(no tracks)'}  (${why})  ${Math.floor(secs / 60)} min ${secs % 60} s`)
console.log(lines.join('\n'))
process.exit(failed ? 1 : 0)
