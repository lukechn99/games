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
/** Public Turnstile site key. When set, each request carries a bot-check pass. */
export const TURNSTILE_SITE_KEY = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY || ''

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
const PASS_TIMEOUT_MS = 8000

interface TurnstileApi {
  render(el: HTMLElement, opts: Record<string, unknown>): string
  reset(id: string): void
}

let turnstile: Promise<TurnstileApi> | null = null
let widget: { id: string; el: HTMLElement; waiting: ((t: string | null) => void) | null } | null = null

function loadTurnstile(): Promise<TurnstileApi> {
  turnstile ??= new Promise((resolve, reject) => {
    const w = window as unknown as { turnstile?: TurnstileApi }
    if (w.turnstile) return resolve(w.turnstile)
    const tag = document.createElement('script')
    tag.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit'
    tag.async = true
    tag.onload = () => (w.turnstile ? resolve(w.turnstile) : reject(new Error('turnstile missing')))
    tag.onerror = () => {
      turnstile = null
      reject(new Error('turnstile failed to load'))
    }
    document.head.appendChild(tag)
  })
  return turnstile
}

/**
 * A fresh bot-check pass from Cloudflare Turnstile. Invisible for nearly
 * everyone; if Cloudflare wants a click, its checkbox appears bottom-left.
 */
async function botPass(): Promise<string | null> {
  if (!TURNSTILE_SITE_KEY || typeof document === 'undefined') return null
  const api = await loadTurnstile()
  const token = new Promise<string | null>((resolve) => {
    const finish = (t: string | null) => {
      clearTimeout(timer)
      if (widget) widget.waiting = null
      resolve(t)
    }
    const timer = setTimeout(() => finish(null), PASS_TIMEOUT_MS)
    if (!widget) {
      const el = document.createElement('div')
      el.style.cssText = 'position:fixed;left:8px;bottom:8px;z-index:60'
      document.body.appendChild(el)
      widget = { id: '', el, waiting: finish }
      widget.id = api.render(el, {
        sitekey: TURNSTILE_SITE_KEY,
        appearance: 'interaction-only',
        callback: (t: string) => widget?.waiting?.(t),
        'error-callback': () => widget?.waiting?.(null),
        'expired-callback': () => undefined,
      })
    } else {
      widget.waiting = finish
      api.reset(widget.id) // asks for a new pass; the callback fires with it
    }
  })
  return token
}
let started = false
let inflight: Promise<void> | null = null

function setServers(extra: RTCIceServer[]) {
  iceServers.splice(0, iceServers.length, ...STUN, ...extra)
}

export function refreshTurn(): Promise<void> {
  if (!TURN_WORKER_URL || typeof fetch === 'undefined') return Promise.resolve()
  inflight ??= (async () => {
    const ctrl = new AbortController()
    let timer: ReturnType<typeof setTimeout> | undefined
    try {
      const pass = await botPass().catch(() => null)
      if (TURNSTILE_SITE_KEY && !pass) throw new Error('no bot-check pass')
      const url = new URL(TURN_WORKER_URL)
      if (pass) url.searchParams.set('pass', pass)
      timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS)
      const r = await fetch(url, { signal: ctrl.signal, cache: 'no-store' })
      const data = (await r.json()) as { iceServers?: RTCIceServer[]; reason?: string }
      const extra = (data.iceServers ?? []).filter((s) => s && s.urls)
      setServers(extra)
      if (!extra.length && data.reason) console.info('[turn] no relay:', data.reason)
    } catch (err) {
      // Keep whatever we had; credentials last 3 hours and we refresh hourly, so an older set still works.
      console.info('[turn] relay credentials unavailable', err)
    } finally {
      clearTimeout(timer)
      inflight = null
    }
  })()
  return inflight
}

/**
 * Fetch now and every hour. Resolves when the first fetch finishes, or after
 * 4 seconds at most, so a slow check never holds up joining a room.
 */
export function startTurn(): Promise<void> {
  if (!started && TURN_WORKER_URL && typeof window !== 'undefined') {
    started = true
    setInterval(() => void refreshTurn(), REFRESH_MS)
  }
  return Promise.race([refreshTurn(), new Promise<void>((r) => setTimeout(r, 4000))])
}
