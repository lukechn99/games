import type { PlayerId, RoomAction, RoomSnapshot } from '@/lib/engine/types'

export const PROTOCOL_VERSION = 1

/** Player → host */
export type ClientMessage =
  | { t: 'hello'; v: number; id: PlayerId; name: string }
  | { t: 'action'; seq: number; action: RoomAction }
  | { t: 'leave' }
  | { t: 'ping' }
  /** Fast, throwaway game data (kart positions): the host passes it on to everyone else. */
  | { t: 'relay'; d: unknown }

/** Host → player */
export type HostMessage =
  | { t: 'welcome'; id: PlayerId }
  | { t: 'snapshot'; snap: RoomSnapshot }
  | { t: 'rejected'; seq: number; reason: string }
  | { t: 'denied'; reason: string }
  | { t: 'kicked' }
  | { t: 'closed' }
  | { t: 'pong' }
  /** Another player's fast game data, passed on by the host. */
  | { t: 'relay'; from: PlayerId; d: unknown }

export function isObject(x: unknown): x is Record<string, unknown> {
  return typeof x === 'object' && x !== null
}
