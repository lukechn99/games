/**
 * Browser storage helpers. Every access is wrapped because storage can be
 * unavailable (private mode, blocked cookies) and the app must still work.
 *
 * - Player id: sessionStorage, so each tab is its own player (handy for
 *   testing) and a refresh keeps the same identity. A player who closes the
 *   tab can still reclaim their seat by rejoining with the same name.
 * - Name: localStorage, remembered across visits.
 * - Active session: sessionStorage, so a refresh drops you back into the room.
 * - Hosted room state: localStorage, so a host can refresh or reopen the tab
 *   and resume the game where it was.
 */
import type { PlayerId, RoomState } from '@/lib/engine/types'

const KEY = {
  playerId: 'p2pg.playerId',
  name: 'p2pg.name',
  session: 'p2pg.session',
  hostRoom: (code: string) => `p2pg.hostRoom.${code}`,
  lastHosted: 'p2pg.lastHosted',
}

const HOST_ROOM_TTL_MS = 12 * 60 * 60 * 1000

function get(store: 'local' | 'session', key: string): string | null {
  try {
    return (store === 'local' ? localStorage : sessionStorage).getItem(key)
  } catch {
    return null
  }
}

function set(store: 'local' | 'session', key: string, value: string | null) {
  try {
    const s = store === 'local' ? localStorage : sessionStorage
    if (value === null) s.removeItem(key)
    else s.setItem(key, value)
  } catch {
    /* storage unavailable */
  }
}

function randomId(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) return crypto.randomUUID()
  return Math.random().toString(36).slice(2) + Date.now().toString(36)
}

export function getPlayerId(): PlayerId {
  let id = get('session', KEY.playerId)
  if (!id) {
    id = randomId()
    set('session', KEY.playerId, id)
  }
  return id
}

export function setPlayerId(id: PlayerId) {
  set('session', KEY.playerId, id)
}

export function getSavedName(): string {
  return get('local', KEY.name) ?? ''
}

export function saveName(name: string) {
  set('local', KEY.name, name)
}

export interface ActiveSession {
  code: string
  role: 'host' | 'player'
}

export function getActiveSession(): ActiveSession | null {
  const raw = get('session', KEY.session)
  if (!raw) return null
  try {
    return JSON.parse(raw) as ActiveSession
  } catch {
    return null
  }
}

export function setActiveSession(session: ActiveSession | null) {
  set('session', KEY.session, session ? JSON.stringify(session) : null)
}

export function saveHostedRoom(room: RoomState) {
  set('local', KEY.hostRoom(room.code), JSON.stringify({ room, savedAt: Date.now() }))
  set('local', KEY.lastHosted, room.code)
}

export function loadHostedRoom(code: string): RoomState | null {
  const raw = get('local', KEY.hostRoom(code))
  if (!raw) return null
  try {
    const { room, savedAt } = JSON.parse(raw) as { room: RoomState; savedAt: number }
    if (Date.now() - savedAt > HOST_ROOM_TTL_MS) {
      clearHostedRoom(code)
      return null
    }
    return room
  } catch {
    return null
  }
}

export function clearHostedRoom(code: string) {
  set('local', KEY.hostRoom(code), null)
  if (get('local', KEY.lastHosted) === code) set('local', KEY.lastHosted, null)
}

/** The most recent room this browser hosted, if it can still be resumed. */
export function getResumableHostedRoom(): RoomState | null {
  const code = get('local', KEY.lastHosted)
  return code ? loadHostedRoom(code) : null
}
