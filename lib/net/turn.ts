/**
 * TURN relay credentials from our Cloudflare Worker (worker/turn-worker.js).
 *
 * The ICE server list is one shared array. PeerJS reads it each time it opens
 * a connection, so refreshing it in place means new connections always get
 * fresh credentials while existing ones keep theirs. If the Worker is
 * missing, slow or over its cap, the list is just the free STUN servers and
 * everything works as it would without a relay.
 */
export const TURN_WORKER_URL = process.env.NEXT_PUBLIC_TURN_WORKER || ''

const STUN: RTCIceServer[] = [
  { urls: ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'] },
  { urls: 'stun:stun.cloudflare.com:3478' },
]
// A fixed TURN server from build settings (NEXT_PUBLIC_TURN_URL), if any.
if (process.env.NEXT_PUBLIC_TURN_URL) {
  STUN.push({
    urls: process.env.NEXT_PUBLIC_TURN_URL.split(',').map((u) => u.trim()),
    username: process.env.NEXT_PUBLIC_TURN_USERNAME,
    credential: process.env.NEXT_PUBLIC_TURN_CREDENTIAL,
  })
}

/** Shared with every Peer's config. Mutated in place, never replaced. */
export const iceServers: RTCIceServer[] = [...STUN]

const REFRESH_MS = 60 * 60 * 1000
const TIMEOUT_MS = 3000
let started = false
let inflight: Promise<void> | null = null

function setServers(extra: RTCIceServer[]) {
  iceServers.splice(0, iceServers.length, ...STUN, ...extra)
}

export function refreshTurn(): Promise<void> {
  if (!TURN_WORKER_URL || typeof fetch === 'undefined') return Promise.resolve()
  inflight ??= (async () => {
    const ctrl = new AbortController()
    const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS)
    try {
      const r = await fetch(TURN_WORKER_URL, { signal: ctrl.signal, cache: 'no-store' })
      const data = (await r.json()) as { iceServers?: RTCIceServer[]; reason?: string }
      const extra = (data.iceServers ?? []).filter((s) => s && s.urls)
      setServers(extra)
      if (!extra.length && data.reason) console.info('[turn] no relay:', data.reason)
    } catch (err) {
      // Keep whatever we had; credentials last 8 hours, so an older set still works.
      console.info('[turn] relay credentials unavailable', err)
    } finally {
      clearTimeout(timer)
      inflight = null
    }
  })()
  return inflight
}

/** Fetch now and every hour. Resolves when the first fetch finishes (or times out). */
export function startTurn(): Promise<void> {
  if (!started && TURN_WORKER_URL && typeof window !== 'undefined') {
    started = true
    setInterval(() => void refreshTurn(), REFRESH_MS)
  }
  return refreshTurn()
}
