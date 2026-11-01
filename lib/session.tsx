'use client'

/**
 * React glue: owns the current HostSession / ClientSession and exposes the
 * latest snapshot plus a few actions to the UI.
 */
import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from 'react'
import type { RoomAction, RoomSnapshot, RoomState } from '@/lib/engine/types'
import { ClientSession } from '@/lib/net/client-session'
import { isValidCode, normalizeCode } from '@/lib/net/config'
import { HostSession } from '@/lib/net/host-session'
import type { EndReason, Session, SessionEvents, SessionStatus } from '@/lib/net/session-types'
import {
  getActiveSession,
  getPlayerId,
  getSavedName,
  loadHostedRoom,
  saveName,
  setActiveSession,
  setPlayerId,
} from '@/lib/net/storage'

interface RoomView {
  role: 'host' | 'player'
  code: string
  status: SessionStatus
  snapshot: RoomSnapshot | null
}

interface Notice {
  id: number
  text: string
}

interface SessionContextValue {
  /** Set once we've checked the URL / storage on first load. */
  ready: boolean
  room: RoomView | null
  /** Room code from a ?room= link, to prefill the join form. */
  linkCode: string | null
  notices: Notice[]
  dismissNotice(id: number): void
  createRoom(name: string): void
  resumeHosting(room: RoomState): void
  joinRoom(code: string, name: string): void
  act(action: RoomAction): void
  leave(): void
  hostNow(): number
}

const SessionContext = createContext<SessionContextValue | null>(null)

const END_MESSAGES: Record<EndReason['kind'], string> = {
  left: '',
  kicked: 'The host removed you from the room.',
  closed: 'The host closed the room.',
  'not-found': "No room with that code is open. Check the code, and make sure the host's page is open and on screen.",
  unreachable:
    "Found the room, but your device couldn't connect to the host's. This happens on some cellular and Wi-Fi networks. Try switching networks (for example, Wi-Fi to cellular).",
  denied: '',
  error: '',
}

function setRoomParam(code: string | null) {
  const url = new URL(window.location.href)
  if (code) url.searchParams.set('room', code)
  else url.searchParams.delete('room')
  window.history.replaceState(null, '', url)
}

export function SessionProvider({ children }: { children: ReactNode }) {
  const [ready, setReady] = useState(false)
  const [room, setRoom] = useState<RoomView | null>(null)
  const [linkCode, setLinkCode] = useState<string | null>(null)
  const [notices, setNotices] = useState<Notice[]>([])
  const sessionRef = useRef<Session | null>(null)
  const noticeId = useRef(0)

  const notify = useCallback((text: string) => {
    if (!text) return
    const id = ++noticeId.current
    setNotices((n) => [...n.slice(-2), { id, text }])
    setTimeout(() => setNotices((n) => n.filter((x) => x.id !== id)), 5000)
  }, [])

  const dismissNotice = useCallback((id: number) => {
    setNotices((n) => n.filter((x) => x.id !== id))
  }, [])

  /** Wire a session's events to React state and start it. */
  const run = useCallback(
    (make: (events: SessionEvents) => Session) => {
      sessionRef.current?.destroy()
      let current: Session | null = null
      const events: SessionEvents = {
        onSnapshot: (snap) => {
          if (sessionRef.current !== current) return
          // A brand-new host may switch codes if theirs was taken.
          if (snap.code !== current?.code) setRoomParam(snap.code)
          setRoom((r) => (r ? { ...r, code: snap.code, snapshot: snap } : r))
          setActiveSession({ code: snap.code, role: current!.role })
        },
        onStatus: (status) => {
          if (sessionRef.current !== current) return
          setRoom((r) => (r ? { ...r, status } : r))
        },
        onNotice: notify,
        onEnded: (reason) => {
          if (sessionRef.current !== current) return
          sessionRef.current = null
          setActiveSession(null)
          setRoomParam(null)
          setRoom(null)
          setLinkCode(null)
          notify('message' in reason ? reason.message : END_MESSAGES[reason.kind])
        },
      }
      current = make(events)
      sessionRef.current = current
      setRoom({ role: current.role, code: current.code, status: 'connecting', snapshot: null })
      setRoomParam(current.code)
      setActiveSession({ code: current.code, role: current.role })
      current.start()
    },
    [notify],
  )

  const startHost = useCallback(
    (name: string, restore: RoomState | null) => {
      if (restore) setPlayerId(restore.hostId)
      const me = { id: restore?.hostId ?? getPlayerId(), name }
      run((events) => new HostSession(me, events, restore))
    },
    [run],
  )

  const startClient = useCallback(
    (code: string, name: string, patient: boolean) => {
      const me = { id: getPlayerId(), name }
      run((events) => new ClientSession(code, me, events, setPlayerId, patient))
    },
    [run],
  )

  // First load: resume an active session (refresh) or read a ?room= link.
  // URL and storage only exist in the browser, so this has to run after mount.
  /* eslint-disable react-hooks/set-state-in-effect */
  useEffect(() => {
    const params = new URLSearchParams(window.location.search)
    const fromLink = normalizeCode(params.get('room') ?? '')
    const active = getActiveSession()
    const name = getSavedName()

    if (active && (!fromLink || fromLink === active.code)) {
      if (active.role === 'host') {
        const saved = loadHostedRoom(active.code)
        if (saved) startHost(name || 'Host', saved)
        else setActiveSession(null)
      } else if (name) {
        startClient(active.code, name, true)
      }
    } else if (isValidCode(fromLink)) {
      setLinkCode(fromLink)
    }
    setReady(true)

    // Let the broker know right away when the tab goes, so ids free up quickly.
    const onHide = () => sessionRef.current?.destroy()
    window.addEventListener('pagehide', onHide)
    return () => {
      window.removeEventListener('pagehide', onHide)
      sessionRef.current?.destroy()
      sessionRef.current = null
    }
  }, [startHost, startClient])
  /* eslint-enable react-hooks/set-state-in-effect */

  const hostNow = useCallback(() => sessionRef.current?.hostNow() ?? Date.now(), [])

  const value: SessionContextValue = {
    ready,
    room,
    linkCode,
    notices,
    dismissNotice,
    createRoom: (name) => {
      saveName(name)
      startHost(name, null)
    },
    resumeHosting: (saved) => startHost(getSavedName() || 'Host', saved),
    joinRoom: (code, name) => {
      saveName(name)
      startClient(normalizeCode(code), name, false)
    },
    act: (action) => sessionRef.current?.act(action),
    leave: () => sessionRef.current?.leave(),
    hostNow,
  }

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>
}

export function useSession() {
  const ctx = useContext(SessionContext)
  if (!ctx) throw new Error('useSession must be used inside SessionProvider')
  return ctx
}
