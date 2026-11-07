/**
 * End-to-end test: real Chrome instances connecting peer-to-peer through a
 * local PeerJS broker. Each player is a separate browser context, so they
 * share nothing but the network.
 *
 *   node tests/e2e/peer-server.mjs &           # broker on 127.0.0.1:9000
 *   NEXT_PUBLIC_PEER_HOST=127.0.0.1 NEXT_PUBLIC_PEER_PORT=9000 \
 *   NEXT_PUBLIC_PEER_SECURE=false npm run build && npx serve out -l 3100 &
 *   APP_URL=http://127.0.0.1:3100/ node tests/e2e/run.mjs
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
  args: ['--disable-features=WebRtcHideLocalIpsWithMdns', '--no-sandbox'],
})

const T = 20_000
let step = 0
function log(msg) {
  console.log(`  ✓ ${msg}`)
}
async function shot(page, name) {
  if (SHOTS) await page.screenshot({ path: `${SHOTS}/${String(++step).padStart(2, '0')}-${name}.png` })
}

async function open(name) {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } })
  const page = await context.newPage()
  page.on('pageerror', (e) => console.log(`  [${name} pageerror]`, e.message))
  page.on('dialog', (d) => d.accept())
  return { name, context, page }
}

async function create(p) {
  await p.page.goto(URL)
  await p.page.fill('#name', p.name)
  await p.page.getByRole('button', { name: 'Create a room' }).click()
  await p.page.getByText('Room open').waitFor({ timeout: T })
  return (await p.page.locator('.ticket p').nth(1).textContent()).trim()
}

async function join(p, code, viaLink = true) {
  await p.page.goto(viaLink ? `${URL}?room=${code}` : URL)
  await p.page.fill('#name', p.name)
  if (!viaLink) await p.page.fill('#code', code)
  await p.page.getByRole('button', { name: 'Join', exact: true }).click()
}

async function waitPlayers(p, n) {
  await p.page.getByRole('heading', { name: new RegExp(`^Players ${n}$`) }).waitFor({ timeout: T })
}

/** Reveal the role card and return 'spy' or the location name. */
async function role(p) {
  const card = p.page.getByRole('button', { name: /Tap to see your role|Tap to hide/ })
  await card.waitFor({ timeout: T })
  if ((await card.getAttribute('aria-pressed')) !== 'true') await card.click()
  const text = await card.textContent()
  if (text.includes("You're the spy")) return 'spy'
  return text.match(/The location is(.+?)One of you/)[1].trim()
}

try {
  console.log('Lobby')
  const host = await open('Hana')
  const code = await create(host)
  assert.match(code, /^[A-Z2-9]{5}$/)
  log(`host created room ${code}`)

  const a = await open('Ari')
  const b = await open('Bo')
  const c = await open('Cy')
  await join(a, code)
  await join(b, code, false)
  await join(c, code)
  for (const p of [host, a, b, c]) await waitPlayers(p, 4)
  log('three players joined (link and typed code); everyone sees 4 players')
  await shot(host.page, 'host-lobby')
  await shot(a.page, 'player-lobby')

  const stranger = await open('Zed')
  await join(stranger, 'QQQQQ')
  await stranger.page.getByText('No room with that code').waitFor({ timeout: 30_000 })
  log('joining a non-existent room fails with a clear message')
  await stranger.context.close()

  console.log('Game start')
  await host.page.getByRole('radio', { name: /Spyfall/ }).click()
  await a.page.getByText('Everyone but the spy knows').waitFor({ timeout: T })
  log('players see the host’s game choice')
  await host.page.getByRole('button', { name: 'Start Spyfall' }).click()
  const roles = {}
  for (const p of [host, a, b, c]) roles[p.name] = await role(p)
  const spies = Object.entries(roles).filter(([, r]) => r === 'spy')
  const locations = new Set(Object.values(roles).filter((r) => r !== 'spy'))
  assert.equal(spies.length, 1, `exactly one spy: ${JSON.stringify(roles)}`)
  assert.equal(locations.size, 1, 'all agents share one location')
  log(`roles dealt: spy is ${spies[0][0]}, location ${[...locations][0]}`)
  await shot(a.page, 'player-role')

  console.log('Refresh and rejoin')
  await b.page.reload()
  assert.equal(await role(b), roles.Bo)
  log('a player who refreshes gets the same seat and role back')

  const cRole = roles.Cy
  await c.context.close()
  await host.page.getByText('Waiting for Cy to reconnect').waitFor({ timeout: T })
  const c2 = await open('Cy')
  await join(c2, code)
  assert.equal(await role(c2), cRole)
  log('a player who closed the tab can reclaim their seat by name from a fresh browser')

  const late = await open('Lu')
  await join(late, code)
  await late.page.getByText('watching this round').waitFor({ timeout: T })
  log('a late joiner spectates instead of breaking the round')

  console.log('Host refresh')
  await host.page.reload()
  await a.page.getByText('Lost the host').waitFor({ timeout: T }).catch(() => {})
  await host.page.getByRole('button', { name: /Tap to see your role/ }).waitFor({ timeout: 45_000 })
  assert.equal(await role(host), roles.Hana)
  // Players reconnect on their own.
  await a.page.getByText('Lost the host').waitFor({ state: 'detached', timeout: 45_000 })
  assert.equal(await role(a), roles.Ari)
  log('host refreshes mid-game; game state survives and players reconnect automatically')

  console.log('Voting')
  const players = { Hana: host, Ari: a, Bo: b, Cy: c2 }
  for (const p of [host, a, b]) await p.page.getByRole('button', { name: 'Call a vote' }).click()
  await host.page.getByRole('heading', { name: 'Who is the spy?' }).waitFor({ timeout: T })
  log('majority calling a vote starts voting for everyone')
  const spyName = spies[0][0]
  const scapegoat = Object.keys(players).find((n) => n !== spyName)
  for (const [name, p] of Object.entries(players)) {
    const target = name === spyName ? scapegoat : spyName
    await p.page.getByRole('radio', { name: new RegExp(`^${target}`) }).click()
  }
  for (const p of Object.values(players)) await p.page.getByText('The agents win').waitFor({ timeout: T })
  log('everyone votes for the spy; all screens show the agents won')
  await shot(a.page, 'results')

  console.log('Next round, kick, close')
  await host.page.getByRole('button', { name: 'Play another round' }).click()
  await late.page.getByRole('button', { name: /Tap to see your role/ }).waitFor({ timeout: T })
  log('play again deals in the late joiner')

  await host.page.getByRole('button', { name: 'Show room controls' }).click()
  await host.page.getByRole('button', { name: 'End game' }).click()
  await waitPlayers(host, 5)
  await host.page.getByRole('listitem').filter({ hasText: 'Lu' }).getByRole('button', { name: 'Remove' }).click()
  await late.page.getByText('The host removed you').waitFor({ timeout: T })
  await waitPlayers(a, 4)
  log('host can end the game and remove a player; the removed player is told')

  await a.page.getByRole('button', { name: 'Leave room' }).click()
  await waitPlayers(host, 3)
  log('a player can leave; host sees them gone')

  await host.page.getByRole('button', { name: 'Close room' }).click()
  await b.page.getByText('The host closed the room').waitFor({ timeout: T })
  log('host closes the room; players are sent home with a message')
  await shot(b.page, 'closed')

  console.log('\nAll end-to-end checks passed.')
} catch (err) {
  console.error('\nFAILED:', err.message)
  process.exitCode = 1
} finally {
  await browser.close()
}
