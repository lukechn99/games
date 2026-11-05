/**
 * Game Night TURN credentials, as a Cloudflare Worker.
 *
 * The games ask this Worker for relay credentials. It checks how much TURN
 * traffic this key has used over the last 30 days and, while that's under
 * the cap, asks Cloudflare for short-lived credentials and passes them on.
 * Over the cap it hands out none, so the games carry on without a relay.
 *
 * Settings (Worker → Settings → Variables and Secrets):
 *   TURN_KEY_ID          (text)   the Turn Token ID from Realtime → TURN
 *   TURN_KEY_API_TOKEN   (secret) the API token shown with it
 *   ACCOUNT_ID           (text)   your Cloudflare account ID
 *   ANALYTICS_TOKEN      (secret) an API token with "Account Analytics: Read"
 *   CAP_GB               (text, optional) monthly cap in GB, default 900
 *
 * Visit <worker url>/status in a browser to see usage and check the setup.
 */

const ALLOWED_ORIGINS = ['https://lukechn99.github.io', 'http://localhost:3000', 'http://127.0.0.1:3100']
const TTL_SECONDS = 8 * 60 * 60 // long enough that a game night never drops mid-call
const USAGE_CACHE_MS = 5 * 60 * 1000
const GB = 1e9

let usageCache = { bytes: null, at: 0 }

function json(body, status, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...headers },
  })
}

function day(offsetDays) {
  return new Date(Date.now() + offsetDays * 86400000).toISOString().slice(0, 10)
}

/** TURN bytes sent to devices (what Cloudflare bills) over the last 30 days, or null if unknown. */
export async function usageBytes(env, now = Date.now()) {
  if (usageCache.bytes !== null && now - usageCache.at < USAGE_CACHE_MS) return usageCache.bytes
  const query = `query {
    viewer {
      accounts(filter: { accountTag: ${JSON.stringify(env.ACCOUNT_ID)} }) {
        callsTurnUsageAdaptiveGroups(
          filter: { date_geq: ${JSON.stringify(day(-29))}, date_leq: ${JSON.stringify(day(0))}, keyId: ${JSON.stringify(env.TURN_KEY_ID)} }
          limit: 1
        ) { sum { egressBytes } }
      }
    }
  }`
  try {
    const r = await fetch('https://api.cloudflare.com/client/v4/graphql', {
      method: 'POST',
      headers: { Authorization: `Bearer ${env.ANALYTICS_TOKEN}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query }),
    })
    const data = await r.json()
    if (!r.ok || data.errors?.length) throw new Error(JSON.stringify(data.errors ?? r.status))
    const rows = data.data?.viewer?.accounts?.[0]?.callsTurnUsageAdaptiveGroups ?? []
    const bytes = rows.reduce((n, row) => n + (row.sum?.egressBytes ?? 0), 0)
    usageCache = { bytes, at: now }
    return bytes
  } catch (err) {
    console.error('usage check failed', err)
    // A recent reading (within the hour) is good enough; otherwise refuse to guess.
    return usageCache.bytes !== null && now - usageCache.at < 60 * 60 * 1000 ? usageCache.bytes : null
  }
}

async function credentials(env) {
  const r = await fetch(
    `https://rtc.live.cloudflare.com/v1/turn/keys/${env.TURN_KEY_ID}/credentials/generate-ice-servers`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${env.TURN_KEY_API_TOKEN}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ ttl: TTL_SECONDS }),
    },
  )
  if (!r.ok) throw new Error(`TURN credentials: ${r.status} ${await r.text()}`)
  const data = await r.json()
  // Browsers block port 53, and trying it only slows connecting down.
  return (data.iceServers ?? []).map((s) => {
    const urls = (Array.isArray(s.urls) ? s.urls : [s.urls]).filter((u) => !/:53(\?|$)/.test(u))
    return { ...s, urls }
  }).filter((s) => s.urls.length)
}

const worker = {
  async fetch(req, env) {
    const url = new URL(req.url)
    const capGB = Number(env.CAP_GB || 900)
    const origin = req.headers.get('Origin') || ''
    const cors = {
      'Access-Control-Allow-Origin': ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0],
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      Vary: 'Origin',
    }
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors })

    if (url.pathname === '/status') {
      const missing = ['TURN_KEY_ID', 'TURN_KEY_API_TOKEN', 'ACCOUNT_ID', 'ANALYTICS_TOKEN'].filter((k) => !env[k])
      const bytes = missing.length ? null : await usageBytes(env)
      return json(
        {
          ok: !missing.length && bytes !== null,
          missingSettings: missing,
          usedGBLast30Days: bytes === null ? 'unknown (check ACCOUNT_ID and ANALYTICS_TOKEN)' : +(bytes / GB).toFixed(3),
          capGB,
          handingOutCredentials: bytes !== null && bytes < capGB * GB,
        },
        200,
      )
    }

    if (!ALLOWED_ORIGINS.includes(origin)) return json({ error: 'Not allowed from this site.' }, 403, cors)

    const bytes = await usageBytes(env)
    if (bytes === null) return json({ iceServers: [], reason: 'usage-unknown' }, 200, cors)
    if (bytes >= capGB * GB) return json({ iceServers: [], reason: 'cap-reached' }, 200, cors)
    try {
      return json({ iceServers: await credentials(env), ttl: TTL_SECONDS }, 200, cors)
    } catch (err) {
      console.error(err)
      return json({ iceServers: [], reason: 'turn-error' }, 200, cors)
    }
  },
}

export default worker

/** For tests. */
export function _resetUsageCache() {
  usageCache = { bytes: null, at: 0 }
}
