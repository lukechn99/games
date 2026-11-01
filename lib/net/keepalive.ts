/**
 * Background tabs get their timers throttled hard (Chrome: about once a
 * minute after 5 minutes hidden; phones may freeze them entirely). That
 * makes a host tab miss its check-ins with the PeerJS broker, the broker
 * forgets the room, and new players get "No room with that code".
 *
 * Timers inside a dedicated Web Worker aren't throttled the same way, so we
 * run a tiny worker that pings the page every few seconds, and the page uses
 * those pings to drive heartbeats. We also fire immediately whenever the tab
 * becomes visible again or the network comes back.
 */

const WORKER_SOURCE = `
let id = null
onmessage = (e) => {
  clearInterval(id)
  if (e.data > 0) id = setInterval(() => postMessage(0), e.data)
}
`

export interface Keepalive {
  stop(): void
}

/**
 * Call `onTick` about every `intervalMs`, even in a background tab, plus once
 * right away whenever the page becomes visible or goes back online.
 * Falls back to a normal interval where workers aren't available.
 */
export function startKeepalive(onTick: (reason: 'timer' | 'wake') => void, intervalMs: number): Keepalive {
  let worker: Worker | null = null
  let url: string | null = null
  let fallback: ReturnType<typeof setInterval> | null = null

  try {
    url = URL.createObjectURL(new Blob([WORKER_SOURCE], { type: 'text/javascript' }))
    worker = new Worker(url)
    worker.onmessage = () => onTick('timer')
    worker.postMessage(intervalMs)
  } catch {
    worker = null
    fallback = setInterval(() => onTick('timer'), intervalMs)
  }

  const wake = () => {
    if (document.visibilityState === 'visible') onTick('wake')
  }
  const online = () => onTick('wake')
  document.addEventListener('visibilitychange', wake)
  window.addEventListener('focus', wake)
  window.addEventListener('pageshow', wake)
  window.addEventListener('online', online)

  return {
    stop() {
      document.removeEventListener('visibilitychange', wake)
      window.removeEventListener('focus', wake)
      window.removeEventListener('pageshow', wake)
      window.removeEventListener('online', online)
      if (worker) worker.terminate()
      if (url) URL.revokeObjectURL(url)
      if (fallback) clearInterval(fallback)
    },
  }
}

/**
 * Send PeerJS's own broker heartbeat now. PeerJS sends these on a plain
 * timer, which is exactly what gets throttled. `socket` is not part of the
 * public types, so this is defensive.
 */
export function sendBrokerHeartbeat(peer: unknown) {
  try {
    const socket = (peer as { socket?: { send?: (m: unknown) => void } }).socket
    socket?.send?.({ type: 'HEARTBEAT' })
  } catch {
    /* not connected */
  }
}
