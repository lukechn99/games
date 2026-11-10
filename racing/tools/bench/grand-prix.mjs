#!/usr/bin/env node
// Exercise the actual room-state bridge with completed three-track snapshots.
import { mkdir } from 'node:fs/promises'
import { join } from 'node:path'
import { serve, browser, ensureExport, isError, REPO } from './lib.mjs'
await ensureExport()
const server = await serve()
const b = await browser()
const out = join(REPO, 'racing/tools/bench/out/grand-prix')
await mkdir(out, { recursive: true })
try {
  const page = await b.newPage({ viewport: { width: 1280, height: 720 } })
  const errors = []
  let ready
  const warm = new Promise(resolve => { ready = resolve })
  page.on('console', m => { if (isError(m.text())) { errors.push(m.text()); console.error(m.text()) } if (m.text().includes('shader warm-up:')) ready() })
  page.on('pageerror', e => errors.push(String(e)))
  await page.goto(`${server.url}/racing/index.html?room=1&track=frost&quality=low`)
  const histories = [
    { track: 'meadow', finish: { a: 61, b: 63 }, places: { a: 1, b: 2 }, points: { a: 15, b: 12 }, laps: { a: [21, 20, 20], b: [22, 21, 20] } },
    { track: 'mine', finish: { a: 181, b: 184 }, places: { a: 1, b: 2 }, points: { a: 15, b: 12 }, laps: { a: [62, 60, 59], b: [63, 61, 60] } },
    { track: 'frost', finish: { a: 172, b: 170 }, places: { a: 2, b: 1 }, points: { a: 12, b: 15 }, laps: { a: [58, 57, 57], b: [58, 56, 56] } },
  ]
  const picks = Object.fromEntries(['a', 'b'].map((id, i) => [id, { chassis: 'frame', tires: 'slicks', driver: i ? 'deer' : 'fox', ready: false, bot: !!i }]))
  const state = { phase: 'pick', track: 'frost', laps: 3, seats: ['a', 'b'], picks, startAt: null, finish: {}, lapTimes: {}, firstFinishAt: null,
    cup: { tracks: ['meadow', 'mine', 'frost'], race: 2, points: { a: 30, b: 24 }, last: {}, results: histories.slice(0, 2) } }
  const envelope = { source: 'game-night', kind: 'state', me: 'a', isHost: true, round: 1, clock: 0, players: [{ id: 'a', name: 'Fox', bot: false }, { id: 'b', name: 'Deer', bot: true }] }
  const post = async state => page.evaluate(message => window.postMessage(message, '*'), { ...envelope, state })
  await post(state)
  let timer
  try {
    await Promise.race([warm, new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('room warm-up timeout')), 180000) })])
  } finally { clearTimeout(timer) }
  await post({ ...state, phase: 'race', startAt: Date.now() + 500 })
  await page.evaluate(async () => { for (let i = 0; i < 10; i++) await new Promise(requestAnimationFrame) })
  await post({ ...state, phase: 'done', finish: histories[2].finish, lapTimes: histories[2].laps,
    cup: { ...state.cup, points: { a: 42, b: 39 }, last: histories[2].points, results: histories } })
  await page.evaluate(async () => { for (let i = 0; i < 8; i++) await new Promise(requestAnimationFrame) })
  if (errors.length) throw new Error(errors.join('\n'))
  await page.screenshot({ path: join(out, 'final-all-tracks.png') })
  console.log('PASS real Web room bridge: completed GP snapshots render without script/browser errors')
  await page.close()
} finally { await b.close(); server.close() }
