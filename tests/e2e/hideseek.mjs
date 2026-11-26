/**
 * End-to-end test of Hide and Seek in a real room: two people in separate
 * Chrome instances plus a computer player, peer to peer through a local
 * PeerJS broker (set up as for run.mjs, with the game exported to
 * public/hideseek and net.js and landscape.js copied beside it).
 *
 *   APP_URL=http://127.0.0.1:3100/ node tests/e2e/hideseek.mjs
 *
 * Each game publishes what it sees as window.hsDebug (main.gd), which this
 * reads from inside each player's game frame.
 */
import { chromium } from 'playwright-core'
import assert from 'node:assert/strict'
import { mkdirSync } from 'node:fs'

const URL = process.env.APP_URL ?? 'http://127.0.0.1:3100/'
const SHOTS = process.env.SHOTS_DIR
const CHROME = process.env.CHROME ?? '/usr/bin/google-chrome'
if (SHOTS) mkdirSync(SHOTS, { recursive: true })

const browser = await chromium.launch({
  executablePath: CHROME,
  args: ['--disable-features=WebRtcHideLocalIpsWithMdns', '--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
})
const T = 30_000
const log = (msg) => console.log(`  ✓ ${msg}`)
let step = 0
const shot = async (p, name) => SHOTS && p.page.screenshot({ path: `${SHOTS}/${String(++step).padStart(2, '0')}-${name}.png` })

async function open(name) {
  const context = await browser.newContext({ viewport: { width: 1000, height: 600 } })
  const page = await context.newPage()
  page.on('pageerror', (e) => console.log(`  [${name} pageerror]`, e.message))
  page.on('dialog', (d) => d.accept())
  return { name, context, page }
}

async function waitPlayers(p, n) {
  await p.page.getByRole('heading', { name: new RegExp(`^Players ${n}$`) }).waitFor({ timeout: T })
}

function gameFrame(p) {
  return p.page.frames().find((f) => f.url().includes('/hideseek/'))
}

/** The game's own summary (window.hsDebug), once it has one matching `ok`. */
async function debug(p, ok = (d) => d.round >= 1, timeout = 120_000) {
  const end = Date.now() + timeout
  while (Date.now() < end) {
    const f = gameFrame(p)
    const d = f && (await f.evaluate(() => window.hsDebug ?? null).catch(() => null))
    if (d && ok(d)) return d
    await p.page.waitForTimeout(500)
  }
  throw new Error(`${p.name}: game never reported the expected state`)
}

const dist = (a, b) => Math.hypot(a[0] - b[0], a[2] - b[2])

try {
  console.log('Room')
  const host = await open('Hana')
  await host.page.goto(URL)
  await host.page.fill('#name', host.name)
  await host.page.getByRole('button', { name: 'Create a room' }).click()
  await host.page.getByText('Room open').waitFor({ timeout: T })
  const code = (await host.page.locator('.ticket p').nth(1).textContent()).trim()
  const guest = await open('Ari')
  await guest.page.goto(`${URL}?room=${code}`)
  await guest.page.fill('#name', guest.name)
  await guest.page.getByRole('button', { name: 'Join', exact: true }).click()
  await waitPlayers(host, 2)
  await host.page.getByRole('radio', { name: /Hide and Seek/ }).click()
  await host.page.getByRole('button', { name: 'Add a computer player' }).click()
  await host.page.getByRole('button', { name: 'Add a computer player' }).click()
  await waitPlayers(host, 4)
  await waitPlayers(guest, 4)
  log('two people and two computer players in a room, Hide and Seek picked')
  await host.page.getByRole('button', { name: 'Start Hide and Seek' }).click()

  console.log('Round')
  const [h, g] = await Promise.all([debug(host), debug(guest)])
  assert.equal(h.round, g.round)
  assert.deepEqual(h.roles, g.roles, 'both games agree who seeks and who hides')
  assert.deepEqual(h.kinds, g.kinds, 'and what everyone is')
  assert.equal(Object.keys(h.roles).length, 4)
  assert.equal(Object.values(h.roles).filter((r) => r === 'seeker').length, 1, 'four players: one seeker')
  assert.ok(h.host && !g.host && h.bots === 2 && g.bots === 0, 'the host runs both bots')
  log(`round ${h.round} dealt the same on both: ${JSON.stringify(h.roles)}`)
  await shot(host, 'host-round')
  await shot(guest, 'guest-round')

  // The guest walks forward; the host should see them move there.
  const before = (await debug(guest)).seen[g.me]
  await guest.page.locator('iframe[title="Hide and Seek"]').click({ position: { x: 500, y: 300 } })
  const role = g.roles[g.me]
  if (role === 'seeker') {
    await debug(guest, (d) => d.phase === 'seek', 70_000)       // seekers wait out the hide phase
  }
  // (Software rendering runs these games at a few frames a second, so
  // hold the key a while and give the host's view time to catch up.)
  await guest.page.keyboard.down('KeyW')
  await guest.page.waitForTimeout(4000)
  await guest.page.keyboard.up('KeyW')
  await guest.page.waitForTimeout(1000)
  const gNow = (await debug(guest)).seen[g.me]
  const hd = await debug(host, (d) => dist(d.seen[g.me], gNow) < 0.6, 20_000).catch(() => null)
  const hView = hd ? hd.seen[g.me] : (await debug(host)).seen[g.me]
  assert.ok(dist(before, gNow) > 1.0, `the guest moved (${JSON.stringify(before)} -> ${JSON.stringify(gNow)})`)
  assert.ok(dist(gNow, hView) < 0.6, `the host sees the guest where they are (${JSON.stringify(gNow)} vs ${JSON.stringify(hView)})`)
  log(`the guest walked ${dist(before, gNow).toFixed(1)} m; the host sees them within ${dist(gNow, hView).toFixed(2)} m`)

  // A human hider rerolls; the other game sees the new prop.
  const people = [host, guest]
  const ids = [h.me, g.me]
  const hi = ids.findIndex((id) => h.roles[id] === 'hider')
  if (hi >= 0) {
    const p = people[hi]
    const other = people[1 - hi]
    const id = ids[hi]
    const was = h.kinds[id]
    await p.page.locator('iframe[title="Hide and Seek"]').click({ position: { x: 500, y: 300 } })
    await p.page.keyboard.press('KeyF')
    const seen = await debug(other, (d) => d.kinds[id] !== was, 15_000)
    log(`${p.name} rerolled from ${was} to ${seen.kinds[id]}; ${other.name}'s game shows it`)
  }

  // The bots, run by the host, move on the guest's screen too.
  const botIds = Object.keys(h.roles).filter((id) => !ids.includes(id))
  const startSeen = g.seen          // where everyone was when the round began
  await debug(host, (d) => d.phase === 'seek', 70_000)
  await host.page.waitForTimeout(8000)
  const hb = await debug(host)
  const gb = await debug(guest)
  for (const id of botIds) {
    assert.ok(dist(hb.seen[id], gb.seen[id]) < 0.8, `bot ${id} is in the same place on both (${JSON.stringify(hb.seen[id])} vs ${JSON.stringify(gb.seen[id])})`)
  }
  const moved = botIds.filter((id) => dist(startSeen[id], gb.seen[id]) > 1.0)
  assert.ok(moved.length >= 1, 'the bots have gone somewhere (hid or started hunting)')
  log(`bots run on the host and show up in the same places for the guest (${moved.length} moved)`)
  await shot(host, 'host-seek')
  await shot(guest, 'guest-seek')

  // Paintballs: whoever seeks fires; the other game sees the shots.
  const seekerId = Object.keys(hb.roles).find((id) => hb.roles[id] === 'seeker')
  if (botIds.includes(seekerId)) {
    const s = await debug(guest, (d) => d.shotsSeen > 0, 90_000)
    log(`the seeker bot's paintballs show on the guest's screen (${s.shotsSeen} so far)`)
  } else {
    const shooter = seekerId === h.me ? host : guest
    const watcher = shooter === host ? guest : host
    const frame = shooter.page.locator('iframe[title="Hide and Seek"]')
    for (let i = 0; i < 4; i++) {
      await frame.click({ position: { x: 500, y: 300 } })
      await shooter.page.waitForTimeout(400)
    }
    const s = await debug(watcher, (d) => d.shotsSeen > 0, 20_000)
    log(`${shooter.name}'s paintballs show on ${watcher.name}'s screen (${s.shotsSeen})`)
  }
  console.log('\nHide and Seek multiplayer: all checks passed')
} catch (e) {
  console.error('\nFAILED:', e.message)
  process.exitCode = 1
} finally {
  await browser.close()
}
