'use client'

import { Loader2 } from 'lucide-react'
import type { SessionStatus } from '@/lib/net/session-types'
import { useSession } from '@/lib/session'
import { Button } from './ui/button'

const LABELS: Record<'host' | 'player', Record<SessionStatus, string>> = {
  host: {
    connecting: 'Opening room…',
    online: 'Room open',
    reconnecting: 'Reclaiming room code…',
    'host-away': '',
    'broker-down': "Can't reach matchmaking. Players already here can keep playing.",
  },
  player: {
    connecting: 'Connecting to host…',
    online: 'Connected',
    reconnecting: 'Reconnecting…',
    'host-away': 'Lost the host. Reconnecting…',
    'broker-down': '',
  },
}

export function statusLabel(role: 'host' | 'player', status: SessionStatus) {
  return LABELS[role][status]
}

/** Small inline dot + label. Hidden when everything is fine, except in the lobby. */
export function StatusPill({ quietWhenOnline = false }: { quietWhenOnline?: boolean }) {
  const { room } = useSession()
  if (!room) return null
  const online = room.status === 'online'
  if (online && quietWhenOnline) return null
  return (
    <span className="inline-flex items-center gap-2 text-sm text-muted-foreground" role="status">
      <span
        className={`size-2 rounded-full ${online ? 'bg-ok' : 'bg-ticket animate-pulse'}`}
        aria-hidden="true"
      />
      {statusLabel(room.role, room.status)}
    </span>
  )
}

/** Full-width banner for when the connection is in trouble. */
export function TroubleBanner() {
  const { room } = useSession()
  if (!room || room.status === 'online' || room.status === 'connecting') return null
  return (
    <div className="bg-ticket px-4 py-2 text-center text-sm font-medium text-ticket-ink" role="status">
      {statusLabel(room.role, room.status)}
    </div>
  )
}

export function ConnectingScreen() {
  const { room, leave } = useSession()
  if (!room) return null
  return (
    <main className="mx-auto flex min-h-dvh max-w-md flex-col items-center justify-center gap-6 px-6 text-center">
      <Loader2 className="size-8 animate-spin text-primary" aria-hidden="true" />
      <div>
        <p className="font-display text-2xl font-bold">Room {room.code}</p>
        <p className="mt-1 text-muted-foreground">{statusLabel(room.role, room.status)}</p>
      </div>
      <Button variant="ghost" onClick={leave}>
        Cancel
      </Button>
    </main>
  )
}
