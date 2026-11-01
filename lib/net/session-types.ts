import type { RoomAction, RoomSnapshot } from '@/lib/engine/types'

/**
 * Connection status shown in the UI.
 * - connecting:  opening the first connection
 * - online:      everything is working
 * - reconnecting: we lost the connection and are trying again
 * - host-away:   (players) the host's browser can't be reached right now
 * - broker-down: (host) can't reach the matchmaking server; existing players still work
 */
export type SessionStatus = 'connecting' | 'online' | 'reconnecting' | 'host-away' | 'broker-down'

export type EndReason =
  | { kind: 'left' }
  | { kind: 'kicked' }
  | { kind: 'closed' }
  | { kind: 'not-found' }
  /** The room exists but a direct connection to the host couldn't be opened. */
  | { kind: 'unreachable' }
  | { kind: 'denied'; message: string }
  | { kind: 'error'; message: string }

export interface SessionEvents {
  onSnapshot(snap: RoomSnapshot): void
  onStatus(status: SessionStatus): void
  /** A short message to show the user, e.g. an action that was rejected. */
  onNotice(message: string): void
  onEnded(reason: EndReason): void
}

export interface Session {
  readonly role: 'host' | 'player'
  readonly code: string
  start(): void
  act(action: RoomAction): void
  /** Leave the room for good. For a host this closes the room for everyone. */
  leave(): void
  /** Tear down without telling anyone (page unload, React unmount). */
  destroy(): void
  /** Host clock estimate, for countdowns. */
  hostNow(): number
}
