/**
 * The player side. Connects to the host through the broker, says hello with
 * a stable player id, then just renders whatever snapshots the host sends.
 *
 * Reconnection is automatic: if the connection drops or goes silent we keep
 * retrying until the host is back or the player gives up.
 */
import type { DataConnection, Peer } from 'peerjs'
import type { PlayerId, RoomAction } from '@/lib/engine/types'
import { HEARTBEAT_MS, hostPeerId, peerOptions, TIMEOUT_MS } from './config'
import { isObject, PROTOCOL_VERSION, type ClientMessage, type HostMessage } from './protocol'
import { startKeepalive, sendBrokerHeartbeat, type Keepalive } from './keepalive'
import type { Session, SessionEvents } from './session-types'

/**
 * Before the first successful join, give up after this long. The broker takes
 * about 5 s to report that a host isn't there, so this allows ~2-3 attempts.
 * When resuming after a refresh the host may be refreshing too, so wait longer.
 */
const FIRST_JOIN_BUDGET_MS = 14_000
/** Once we know the host exists, allow longer: slow networks and relays need time. */
const FOUND_HOST_BUDGET_MS = 40_000
/** How long one attempt may take to open a direct connection before we retry. */
const OPEN_TIMEOUT_MS = 15_000
const RESUME_JOIN_BUDGET_MS = 60_000
const RETRY_DELAYS_MS = [1000, 2000, 3000, 5000]

export class ClientSession implements Session {
  readonly role = 'player' as const
  private peer: Peer | null = null
  private conn: DataConnection | null = null
  private destroyed = false
  private joinedOnce = false
  private failures = 0
  private retryTimer: ReturnType<typeof setTimeout> | null = null
  private keepalive: Keepalive | null = null
  private lastHeard = 0
  private seq = 0
  private clockOffset = 0
  private startedAt = 0
  /**
   * Did the broker ever tell us the host isn't there? If not, and we still
   * failed, we reached the host but couldn't open a direct connection
   * (a network problem, not a wrong code).
   */
  private sawHostMissing = false
  private sawConnectFailure = false

  constructor(
    readonly code: string,
    private me: { id: PlayerId; name: string },
    private events: SessionEvents,
    /** Called when the host maps us onto an existing seat with a different id. */
    private onIdChange: (id: PlayerId) => void,
    /** True when resuming after a refresh: the host may be refreshing too, so keep trying longer. */
    private patient = false,
  ) {}

  hostNow() {
    return Date.now() + this.clockOffset
  }

  start() {
    this.events.onStatus('connecting')
    this.startedAt = Date.now()
    this.keepalive = startKeepalive((reason) => this.heartbeat(reason === 'wake'), HEARTBEAT_MS)
    void this.ensurePeer()
  }

  /** Make sure we're registered with the broker, then dial the host. */
  private async ensurePeer() {
    if (this.destroyed) return
    if (this.peer && !this.peer.destroyed) {
      if (this.peer.disconnected) this.peer.reconnect()
      else this.dial()
      return
    }
    const { Peer } = await import('peerjs')
    if (this.destroyed) return
    const peer = new Peer(peerOptions())
    this.peer = peer
    peer.on('open', () => this.dial())
    peer.on('disconnected', () => {
      // Lost the broker. If we're still connected to the host that's fine;
      // we only need the broker to (re)dial.
      if (!this.destroyed && !peer.destroyed && !this.conn?.open) this.retry()
    })
    peer.on('error', (err) => {
      if (this.destroyed) return
      if (err.type === 'peer-unavailable') {
        // Host isn't registered with the broker: room doesn't exist, or the host is away.
        this.sawHostMissing = true
        this.retry()
      } else if (err.type === 'browser-incompatible') {
        this.end({ kind: 'error', message: "This browser doesn't support peer-to-peer connections." })
      } else {
        console.warn('[client] peer error', err.type, err.message)
        if (peer.destroyed) this.peer = null
        this.retry()
      }
    })
  }

  private dial() {
    if (this.destroyed || !this.peer || this.peer.disconnected) return
    this.closeConn()
    const conn = this.peer.connect(hostPeerId(this.code), { reliable: true, serialization: 'json' })
    if (!conn) {
      this.retry()
      return
    }
    this.conn = conn
    conn.on('open', () => {
      if (conn !== this.conn) return
      this.lastHeard = Date.now()
      this.send({ t: 'hello', v: PROTOCOL_VERSION, id: this.me.id, name: this.me.name })
    })
    conn.on('data', (data) => {
      if (conn !== this.conn) return
      this.lastHeard = Date.now()
      if (isObject(data)) this.onMessage(data as HostMessage)
    })
    const lost = () => {
      if (conn !== this.conn) return
      if (!conn.open) this.sawConnectFailure = true
      this.conn = null
      this.retry()
    }
    conn.on('close', lost)
    conn.on('error', lost)
    conn.on('iceStateChanged', (state) => {
      if (state === 'failed' || state === 'closed') lost()
    })
    // If the connection never opens (e.g. NAT traversal fails), don't hang forever.
    setTimeout(() => {
      if (conn === this.conn && !conn.open) lost()
    }, OPEN_TIMEOUT_MS)
  }

  private onMessage(msg: HostMessage) {
    switch (msg.t) {
      case 'welcome':
        this.joinedOnce = true
        this.failures = 0
        if (msg.id !== this.me.id) {
          this.me = { ...this.me, id: msg.id }
          this.onIdChange(msg.id)
        }
        this.events.onStatus('online')
        return
      case 'snapshot':
        this.clockOffset = msg.snap.hostNow - Date.now()
        this.events.onSnapshot(msg.snap)
        return
      case 'rejected':
        this.events.onNotice(msg.reason)
        return
      case 'denied':
        this.end({ kind: 'denied', message: msg.reason })
        return
      case 'kicked':
        this.end({ kind: 'kicked' })
        return
      case 'closed':
        this.end({ kind: 'closed' })
        return
      case 'pong':
        return
    }
  }

  private send(msg: ClientMessage): boolean {
    if (!this.conn?.open) return false
    try {
      this.conn.send(msg)
      return true
    } catch {
      return false
    }
  }

  private heartbeat(woke = false) {
    if (this.peer?.open) sendBrokerHeartbeat(this.peer)
    if (!this.conn?.open) {
      // Coming back to a tab that was stuck mid-retry: try again right away.
      if (woke && this.retryTimer && !this.destroyed) {
        clearTimeout(this.retryTimer)
        this.retryTimer = null
        void this.ensurePeer()
      }
      return
    }
    if (Date.now() - this.lastHeard > TIMEOUT_MS) {
      // The host went silent (closed laptop, lost Wi-Fi). Start over.
      this.conn = null
      this.retry()
      return
    }
    this.send({ t: 'ping' })
  }

  private retry() {
    if (this.destroyed || this.retryTimer) return
    this.closeConn()
    this.failures++
    const budget = this.patient
      ? RESUME_JOIN_BUDGET_MS
      : this.sawConnectFailure && !this.sawHostMissing
        ? FOUND_HOST_BUDGET_MS
        : FIRST_JOIN_BUDGET_MS
    if (!this.joinedOnce && Date.now() - this.startedAt >= budget) {
      this.end({ kind: this.sawConnectFailure && !this.sawHostMissing ? 'unreachable' : 'not-found' })
      return
    }
    this.events.onStatus(this.joinedOnce ? 'host-away' : 'connecting')
    const delay = RETRY_DELAYS_MS[Math.min(this.failures - 1, RETRY_DELAYS_MS.length - 1)]!
    this.retryTimer = setTimeout(() => {
      this.retryTimer = null
      void this.ensurePeer()
    }, delay)
  }

  private closeConn() {
    const conn = this.conn
    this.conn = null
    try {
      conn?.close()
    } catch {
      /* ignore */
    }
  }

  act(action: RoomAction) {
    if (!this.send({ t: 'action', seq: ++this.seq, action })) {
      this.events.onNotice('Not connected to the host right now.')
    }
  }

  leave() {
    this.send({ t: 'leave' })
    setTimeout(() => this.destroy(), 300)
    this.events.onEnded({ kind: 'left' })
  }

  private end(reason: Parameters<SessionEvents['onEnded']>[0]) {
    this.destroy()
    this.events.onEnded(reason)
  }

  destroy() {
    if (this.destroyed) return
    this.destroyed = true
    if (this.retryTimer) clearTimeout(this.retryTimer)
    this.keepalive?.stop()
    this.closeConn()
    this.peer?.destroy()
    this.peer = null
  }
}
