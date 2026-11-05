import { afterEach, describe, expect, it, vi } from 'vitest'

const workerPath = '../worker/turn-worker.js'
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Mod = any

const env = { TURN_KEY_ID: 'key1', TURN_KEY_API_TOKEN: 'tok', ACCOUNT_ID: 'acct', ANALYTICS_TOKEN: 'ana', CAP_GB: '900' }
const ORIGIN = 'https://lukechn99.github.io'

function mockCloudflare(usedBytes: number | 'error') {
  const calls: string[] = []
  vi.stubGlobal('fetch', async (url: string, init: RequestInit) => {
    calls.push(url)
    if (url.includes('graphql')) {
      expect(String(init.body)).toContain('callsTurnUsageAdaptiveGroups')
      expect(String(init.body)).toContain('keyId: \\"key1\\"')
      if (usedBytes === 'error') return new Response(JSON.stringify({ errors: [{ message: 'no' }] }), { status: 200 })
      return new Response(JSON.stringify({ data: { viewer: { accounts: [{ callsTurnUsageAdaptiveGroups: [{ sum: { egressBytes: usedBytes } }] }] } } }))
    }
    expect(JSON.parse(String(init.body))).toEqual({ ttl: 8 * 3600 })
    return new Response(
      JSON.stringify({
        iceServers: [
          { urls: ['stun:stun.cloudflare.com:3478', 'stun:stun.cloudflare.com:53'] },
          { urls: ['turn:turn.cloudflare.com:3478?transport=udp', 'turn:turn.cloudflare.com:53?transport=udp', 'turns:turn.cloudflare.com:443?transport=tcp'], username: 'u', credential: 'c' },
        ],
      }),
      { status: 201 },
    )
  })
  return calls
}

async function call(mod: Mod, path = '/', origin: string | null = ORIGIN) {
  const headers = origin ? { Origin: origin } : undefined
  const r: Response = await mod.default.fetch(new Request(`https://w.example${path}`, { headers }), env)
  return { status: r.status, body: await r.json(), cors: r.headers.get('Access-Control-Allow-Origin') }
}

afterEach(() => vi.unstubAllGlobals())

describe('TURN worker', () => {
  it('hands out credentials under the cap, without port 53', async () => {
    const mod: Mod = await import(workerPath)
    mod._resetUsageCache()
    mockCloudflare(5e9)
    const r = await call(mod)
    expect(r.status).toBe(200)
    expect(r.cors).toBe(ORIGIN)
    const urls = r.body.iceServers.flatMap((s: { urls: string[] }) => s.urls)
    expect(urls).toContain('turns:turn.cloudflare.com:443?transport=tcp')
    expect(urls.some((u: string) => u.includes(':53'))).toBe(false)
  })

  it('stops at the cap and caches the usage check', async () => {
    const mod: Mod = await import(workerPath)
    mod._resetUsageCache()
    const calls = mockCloudflare(900e9)
    expect((await call(mod)).body).toEqual({ iceServers: [], reason: 'cap-reached' })
    await call(mod)
    expect(calls.filter((u) => u.includes('graphql'))).toHaveLength(1)
    expect(calls.some((u) => u.includes('rtc.live'))).toBe(false)
  })

  it('refuses when usage is unknown, and blocks other sites', async () => {
    const mod: Mod = await import(workerPath)
    mod._resetUsageCache()
    mockCloudflare('error')
    expect((await call(mod)).body).toEqual({ iceServers: [], reason: 'usage-unknown' })
    expect((await call(mod, '/', 'https://evil.example')).status).toBe(403)
    expect((await call(mod, '/', null)).status).toBe(403)
  })

  it('reports setup on /status', async () => {
    const mod: Mod = await import(workerPath)
    mod._resetUsageCache()
    mockCloudflare(1.5e9)
    const r = await call(mod, '/status', null)
    expect(r.body).toMatchObject({ ok: true, usedGBLast30Days: 1.5, capGB: 900, handingOutCredentials: true, missingSettings: [] })
  })
})

describe('game-side relay list', () => {
  it('adds fetched relay servers to the shared list in place', async () => {
    vi.resetModules()
    vi.stubEnv('NEXT_PUBLIC_TURN_WORKER', 'https://w.example/')
    const relay = { urls: ['turns:turn.cloudflare.com:443?transport=tcp'], username: 'u', credential: 'c' }
    vi.stubGlobal('fetch', async () => new Response(JSON.stringify({ iceServers: [relay] })))
    const turn = await import('@/lib/net/turn')
    const { peerOptions } = await import('@/lib/net/config')
    const list = peerOptions().config!.iceServers!
    expect(list).toHaveLength(2)
    await turn.refreshTurn()
    expect(list).toBe(turn.iceServers)
    expect(list).toContainEqual(relay)
    // A failed refresh keeps the last good credentials.
    vi.stubGlobal('fetch', async () => { throw new Error('offline') })
    await turn.refreshTurn()
    expect(list).toContainEqual(relay)
    vi.unstubAllEnvs()
  })
})
