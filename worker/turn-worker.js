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
 *   CAP_GB               (text, optional) cap over the last 30 days in GB, default 900
 *   DAILY_CAP_GB         (text, optional) cap for today (UTC) in GB, default 50
 *   TURNSTILE_SECRET     (secret, optional) Turnstile widget secret. When set,
 *                        every request must carry a fresh bot-check pass from
 *                        the games page, so scripts can't get credentials.
 *   EXTRA_ORIGINS        (text, optional) comma-separated extra sites to allow,
 *                        e.g. http://localhost:3000 while testing. Remove after.
 *
 * Visit <worker url>/status in a browser to see usage and check the setup.
 *
 * What protects the allowance: the bot check (stops scripts), the site
 * check (stops other websites), the daily and 30-day caps (limit the damage
 * from anything that gets through) and 8-hour credential expiry.
 */

// Only the live games site. Note that this stops other *websites* from using
// the Worker through their visitors' browsers; a script can still fake the
// Origin header, which is why the usage cap below is the real protection.
const SITE_ORIGINS = ['https://lukechn99.github.io']
const SITE_HOSTNAME = 'lukechn99.github.io'
// Relayed connections are cut when credentials expire; the games reconnect
// on their own (they refresh credentials hourly), so a relayed player sees a
// short blip about every 3 hours.
const TTL_SECONDS = 3 * 60 * 60
const USAGE_CACHE_MS = 5 * 60 * 1000
const GB = 1e9

let usageCache = { value: null, at: 0 }

function json(body, status, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...headers },
  })
}

function day(offsetDays) {
  return new Date(Date.now() + offsetDays * 86400000).toISOString().slice(0, 10)
}

/**
 * TURN bytes sent to devices (what Cloudflare bills) over the last 30 days
 * and today (UTC), or null if unknown.
 */
export async function usage(env, now = Date.now()) {
  if (usageCache.value !== null && now - usageCache.at < USAGE_CACHE_MS) return usageCache.value
  const key = JSON.stringify(env.TURN_KEY_ID)
  const query = `query {
    viewer {
      accounts(filter: { accountTag: ${JSON.stringify(env.ACCOUNT_ID)} }) {
        month: callsTurnUsageAdaptiveGroups(
          filter: { date_geq: ${JSON.stringify(day(-29))}, date_leq: ${JSON.stringify(day(0))}, keyId: ${key} }
          limit: 1
        ) { sum { egressBytes } }
        today: callsTurnUsageAdaptiveGroups(
          filter: { date_geq: ${JSON.stringify(day(0))}, date_leq: ${JSON.stringify(day(0))}, keyId: ${key} }
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
    const acct = data.data?.viewer?.accounts?.[0] ?? {}
    const total = (rows) => (rows ?? []).reduce((n, row) => n + (row.sum?.egressBytes ?? 0), 0)
    const value = { month: total(acct.month), today: total(acct.today) }
    usageCache = { value, at: now }
    return value
  } catch (err) {
    console.error('usage check failed', err)
    // A recent reading (within the hour) is good enough; otherwise refuse to guess.
    return usageCache.value !== null && now - usageCache.at < 60 * 60 * 1000 ? usageCache.value : null
  }
}

/** Check a Turnstile pass from the games page. */
async function passedBotCheck(env, token, ip) {
  if (!token) return false
  try {
    const form = new FormData()
    form.append('secret', env.TURNSTILE_SECRET)
    form.append('response', token)
    if (ip) form.append('remoteip', ip)
    const r = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', { method: 'POST', body: form })
    const out = await r.json()
    return out.success === true && out.hostname === SITE_HOSTNAME
  } catch (err) {
    console.error('bot check failed', err)
    return false
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
    const origin = req.headers.get('Origin') || ''
    const ALLOWED_ORIGINS = [
      ...SITE_ORIGINS,
      ...String(env.EXTRA_ORIGINS || '').split(',').map((o) => o.trim()).filter(Boolean),
    ]
    const cors = {
      'Access-Control-Allow-Origin': ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0],
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      Vary: 'Origin',
    }
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors })

    const capGB = Number(env.CAP_GB || 900)
    const dailyGB = Number(env.DAILY_CAP_GB || 50)

    if (url.pathname === '/status') {
      const missing = ['TURN_KEY_ID', 'TURN_KEY_API_TOKEN', 'ACCOUNT_ID', 'ANALYTICS_TOKEN'].filter((k) => !env[k])
      const used = missing.length ? null : await usage(env)
      const gb = (b) => +(b / GB).toFixed(3)
      return json(
        {
          ok: !missing.length && used !== null,
          missingSettings: missing,
          usedGBLast30Days: used === null ? 'unknown (check ACCOUNT_ID and ANALYTICS_TOKEN)' : gb(used.month),
          usedGBToday: used === null ? 'unknown' : gb(used.today),
          capGB,
          dailyCapGB: dailyGB,
          botCheck: env.TURNSTILE_SECRET ? 'on' : 'off (add TURNSTILE_SECRET to turn it on)',
          handingOutCredentials: used !== null && used.month < capGB * GB && used.today < dailyGB * GB,
        },
        200,
      )
    }

    if (!ALLOWED_ORIGINS.includes(origin)) return json({ error: 'Not allowed from this site.' }, 403, cors)
    if (env.TURNSTILE_SECRET) {
      const ok = await passedBotCheck(env, url.searchParams.get('pass'), req.headers.get('CF-Connecting-IP'))
      if (!ok) return json({ iceServers: [], reason: 'bot-check-failed' }, 403, cors)
    }

    const used = await usage(env)
    if (used === null) return json({ iceServers: [], reason: 'usage-unknown' }, 200, cors)
    if (used.month >= capGB * GB) return json({ iceServers: [], reason: 'cap-reached' }, 200, cors)
    if (used.today >= dailyGB * GB) return json({ iceServers: [], reason: 'daily-cap-reached' }, 200, cors)
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
  usageCache = { value: null, at: 0 }
}
