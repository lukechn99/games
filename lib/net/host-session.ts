/**
 * The host side. The host's browser registers with the broker under an id
 * derived from the room code, accepts a data connection from each player,
 * runs the room engine, and sends every player their own snapshot.
 *
 * Players only ever talk to the host (a star, not a mesh).
 */
import type { DataConnection, Peer } from 'peerjs'
import {
  applyAction,
  botStep,
  createRoom,
  joinRoom,
  removePlayer,
  setConnected,
  snapshotFor,
  tickRoom,
} from '@/lib/engine/room'
import type { PlayerId, RoomAction, RoomState, RuleContext } from '@/lib/engine/types'
import { getGameModule } from '@/lib/games/modules'
import { generateRoomCode, hostPeerId, HEARTBEAT_MS, peerOptions, TIMEOUT_MS } from './config'
import { isObject, PROTOCOL_VERSION, type ClientMessage, type HostMessage } from './protocol'
import type { Session, SessionEvents } from './session-types'
import { startKeepalive, sendBrokerHeartbeat, type Keepalive } from './keepalive'
import { clearHostedRoom, saveHostedRoom } from './storage'

interface Link {
  conn: DataConnection
  playerId: PlayerId | null
  lastSeen: number
}

const HELLO_TIMEOUT_MS = 10_000
/** After a refresh the broker may still hold our old id for a few seconds. */
const RECLAIM_RETRY_MS = 2500
const RECLAIM_MAX_TRIES = 24
const NEW_CODE_MAX_TRIES = 5
/** Pause before each computer-player action, so people can follow along. */
const BOT_DELAY_MS = 650

function ruleContext(): RuleContext {
  return { now: Date.now(), random: Math.random }
}

export class HostSession implements Session {
  readonly role = 'host' as const
  code: string
  private room: RoomState
  private peer: Peer | null = null
  private links = new Map<string, Link>() // keyed by conn.connectionId
  private keepalive: Keepalive | null = null
  private botTimer: ReturnType<typeof setTimeout> | null = null
  private lastTick = 0
  private lastHeartbeat = 0
  private retryTimer: ReturnType<typeof setTimeout> | null = null
  private tries = 0
  private destroyed = false
  private everOnline = false
  private isRestored: boolean

  constructor(
    private me: { id: PlayerId; name: string },
    private events: SessionEvents,
    restore: RoomState | null,
    code?: string,
  ) {
    this.code = restore?.code ?? code ?? generateRoomCode()
    this.room = restore
      ? setConnected({ ...restore, players: restore.players.map((p) => ({ ...p, call: undefined })) }, restore.hostId, true)
      : createRoom(this.code, me, Date.now())
    // Players who were connected before the host left will have to reconnect.
    for (const p of this.room.players) {
      if (p.id !== this.room.hostId && !p.bot) this.room = setConnected(this.room, p.id, false)
    }
    this.isRestored = !!restore
  }

  get hostId() {
    return this.room.hostId
  }

  hostNow() {
    return Date.now()
  }

  start() {
    this.events.onStatus('connecting')
    // Save right away so a refresh before anyone joins can still resume the room.
    saveHostedRoom(this.room)
    this.publish()
    this.scheduleBots()
    // Driven by a worker so a background host tab keeps ticking and keeps
    // checking in with the broker (see keepalive.ts).
    this.keepalive = startKeepalive((reason) => this.onKeepalive(reason), 1000)
    void this.register()
  }

  private onKeepalive(reason: 'timer' | 'wake') {
    const now = Date.now()
    if (now - this.lastTick >= 1000) {
      this.lastTick = now
      this.tick()
    }
    if (reason === 'wake' || now - this.lastHeartbeat >= HEARTBEAT_MS) {
      this.lastHeartbeat = now
      this.heartbeat()
      this.checkBroker()
    }
  }

  /** Keep our registration with the broker alive, and repair it if it dropped. */
  private checkBroker() {
    const peer = this.peer
    if (!peer) {
      // Between registrations; a retry is scheduled or one is about to be.
      if (!this.retryTimer && this.everOnline) void this.register()
      return
    }
    if (peer.destroyed) {
      this.peer = null
      if (!this.retryTimer) void this.register()
    } else if (peer.disconnected) {
      if (this.retryTimer) clearTimeout(this.retryTimer)
      this.retryTimer = null
      peer.reconnect()
    } else if (peer.open) {
      sendBrokerHeartbeat(peer)
    }
  }

  private async register() {
    if (this.destroyed) return
    const { Peer } = await import('peerjs')
    if (this.destroyed) return

    const peer = new Peer(hostPeerId(this.code), peerOptions())
    this.peer = peer

    peer.on('open', () => {
      this.events.onPeer?.(peer)
      this.tries = 0
      this.everOnline = true
      this.events.onStatus('online')
    })
    peer.on('connection', (conn) => this.accept(conn))
    peer.on('disconnected', () => {
      // Lost the broker. Existing data connections keep working; we just
      // can't accept new players until we're back.
      if (this.destroyed || peer.destroyed) return
      this.events.onStatus('broker-down')
      this.scheduleRetry(() => {
        if (!peer.destroyed && peer.disconnected) peer.reconnect()
      }, 3000)
    })
    peer.on('error', (err) => this.onPeerError(peer, err.type, err.message))
  }

  private onPeerError(peer: Peer, type: string, message: string) {
    if (this.destroyed) return
    if (type === 'unavailable-id') {
      peer.destroy()
      this.peer = null
      if (this.isRestored || this.everOnline) {
        // Our own previous tab is probably still registered. Wait it out.
        if (++this.tries > RECLAIM_MAX_TRIES) {
          this.events.onEnded({ kind: 'error', message: 'Could not reclaim this room code. Try creating a new room.' })
          return
        }
        this.events.onStatus('reconnecting')
        this.scheduleRetry(() => void this.register(), RECLAIM_RETRY_MS)
      } else {
        // Brand new room and somebody else has this code: pick another.
        if (++this.tries > NEW_CODE_MAX_TRIES) {
          this.events.onEnded({ kind: 'error', message: 'Could not create a room. Please try again.' })
          return
        }
        this.code = generateRoomCode()
        this.room = { ...this.room, code: this.code, version: this.room.version + 1 }
        this.publish()
        void this.register()
      }
      return
    }
    if (type === 'network' || type === 'server-error' || type === 'socket-error' || type === 'socket-closed') {
      this.events.onStatus('broker-down')
      if (peer.destroyed) {
        this.peer = null
        this.scheduleRetry(() => void this.register(), 3000)
      }
      return
    }
    if (type === 'browser-incompatible') {
      this.events.onEnded({ kind: 'error', message: "This browser doesn't support peer-to-peer connections." })
      return
    }
    // Errors about a single connection (e.g. 'peer-unavailable') are not fatal for the host.
    console.warn('[host] peer error', type, message)
  }

  private scheduleRetry(fn: () => void, ms: number) {
    if (this.retryTimer) clearTimeout(this.retryTimer)
    this.retryTimer = setTimeout(() => {
      this.retryTimer = null
      if (!this.destroyed) fn()
    }, ms)
  }

  private accept(conn: DataConnection) {
    const link: Link = { conn, playerId: null, lastSeen: Date.now() }
    this.links.set(conn.connectionId, link)

    const helloTimer = setTimeout(() => {
      if (!link.playerId) conn.close()
    }, HELLO_TIMEOUT_MS)

    conn.on('data', (data) => {
      link.lastSeen = Date.now()
      if (isObject(data)) this.onMessage(link, data as ClientMessage)
    })
    const gone = () => {
      clearTimeout(helloTimer)
      this.dropLink(link)
    }
    conn.on('close', gone)
    conn.on('error', gone)
    conn.on('iceStateChanged', (state) => {
      if (state === 'failed' || state === 'closed') gone()
    })
  }

  private dropLink(link: Link) {
    if (!this.links.has(link.conn.connectionId)) return
    this.links.delete(link.conn.connectionId)
    try {
      link.conn.close()
    } catch {
      /* already closed */
    }
    const id = link.playerId
    // Only mark offline if this was their current connection (not replaced by a newer one).
    if (id && ![...this.links.values()].some((l) => l.playerId === id)) {
      this.update(setConnected(this.room, id, false))
    }
  }

  private send(link: Link, msg: HostMessage) {
    if (!link.conn.open) return
    try {
      link.conn.send(msg)
    } catch (err) {
      console.warn('[host] send failed', err)
    }
  }

  private onMessage(link: Link, msg: ClientMessage) {
    switch (msg.t) {
      case 'hello': {
        if (msg.v !== PROTOCOL_VERSION) {
          this.send(link, { t: 'denied', reason: 'Your page is out of date. Please refresh.' })
          return
        }
        if (typeof msg.id !== 'string' || typeof msg.name !== 'string') return
        if (msg.id === this.room.hostId) {
          this.send(link, { t: 'denied', reason: 'This tab is already the host.' })
          return
        }
        const result = joinRoom(this.room, { id: msg.id, name: msg.name }, Date.now())
        if ('error' in result) {
          this.send(link, { t: 'denied', reason: result.error })
          return
        }
        // If the same player had an older connection (other tab, stale socket), retire it.
        for (const other of this.links.values()) {
          if (other !== link && other.playerId === result.playerId) {
            other.playerId = null
            this.send(other, { t: 'denied', reason: 'You joined from somewhere else.' })
            setTimeout(() => this.dropLink(other), 200)
          }
        }
        link.playerId = result.playerId
        this.send(link, { t: 'welcome', id: result.playerId })
        this.update(result.room, true)
        return
      }
      case 'action': {
        if (!link.playerId) return
        const reason = this.apply(link.playerId, msg.action)
        if (reason) this.send(link, { t: 'rejected', seq: msg.seq, reason })
        return
      }
      case 'leave': {
        const id = link.playerId
        link.playerId = null
        if (id) this.update(removePlayer(this.room, id, ruleContext(), getGameModule))
        setTimeout(() => this.dropLink(link), 200)
        return
      }
      case 'ping':
        this.send(link, { t: 'pong' })
        return
      case 'relay': {
        const from = link.playerId
        if (!from) return
        for (const other of this.links.values()) {
          if (other !== link && other.playerId) this.send(other, { t: 'relay', from, d: msg.d })
        }
        this.events.onRelay?.(from, msg.d)
        return
      }
    }
  }

  relay(data: unknown) {
    for (const link of this.links.values()) {
      if (link.playerId) this.send(link, { t: 'relay', from: this.room.hostId, d: data })
    }
  }

  /** Apply an action. Returns an error message if rejected. */
  private apply(playerId: PlayerId, action: RoomAction): string | null {
    if (!isObject(action) || typeof action.type !== 'string') return 'Invalid action.'
    const result = applyAction(this.room, playerId, action, ruleContext(), getGameModule)
    if ('error' in result) return result.error

    if (action.type === 'kick') {
      for (const link of this.links.values()) {
        if (link.playerId === action.playerId) {
          link.playerId = null
          this.send(link, { t: 'kicked' })
          setTimeout(() => this.dropLink(link), 200)
        }
      }
    }
    this.update(result.state)
    return null
  }

  /** The host's own actions. */
  act(action: RoomAction) {
    const reason = this.apply(this.room.hostId, action)
    if (reason) this.events.onNotice(reason)
  }

  private update(room: RoomState, force = false) {
    if (room === this.room && !force) return
    this.room = room
    saveHostedRoom(room)
    this.publish()
    this.scheduleBots()
  }

  /** Give computer players a turn, one action at a time with a short pause. */
  private scheduleBots() {
    if (this.botTimer || this.destroyed) return
    if (!this.room.game || !this.room.players.some((p) => p.bot)) return
    const delay = getGameModule(this.room.game.gameId)?.botDelayMs ?? BOT_DELAY_MS
    this.botTimer = setTimeout(() => {
      this.botTimer = null
      if (this.destroyed) return
      const next = botStep(this.room, ruleContext(), getGameModule)
      if (next) this.update(next)
    }, delay)
  }

  /** Send every connected player their personal snapshot, and update our own UI. */
  private publish() {
    const now = Date.now()
    for (const link of this.links.values()) {
      if (link.playerId) {
        this.send(link, { t: 'snapshot', snap: snapshotFor(this.room, link.playerId, getGameModule, now) })
      }
    }
    this.events.onSnapshot(snapshotFor(this.room, this.room.hostId, getGameModule, now))
  }

  private tick() {
    this.update(tickRoom(this.room, ruleContext(), getGameModule))
  }

  private heartbeat() {
    const now = Date.now()
    for (const link of [...this.links.values()]) {
      if (now - link.lastSeen > TIMEOUT_MS) this.dropLink(link)
      else this.send(link, { t: 'pong' })
    }
  }

  leave() {
    for (const link of this.links.values()) this.send(link, { t: 'closed' })
    clearHostedRoom(this.code)
    // Give the 'closed' messages a moment to flush before tearing down.
    setTimeout(() => this.destroy(), 300)
    this.events.onEnded({ kind: 'left' })
  }

  destroy() {
    if (this.destroyed) return
    this.destroyed = true
    this.keepalive?.stop()
    if (this.botTimer) clearTimeout(this.botTimer)
    if (this.retryTimer) clearTimeout(this.retryTimer)
    for (const link of this.links.values()) {
      try {
        link.conn.close()
      } catch {
        /* ignore */
      }
    }
    this.links.clear()
    this.peer?.destroy()
    this.peer = null
  }
}
