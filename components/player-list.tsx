'use client'

import { Crown } from 'lucide-react'
import type { Player, RoomSnapshot } from '@/lib/engine/types'

export default function PlayerList({
  snapshot,
  onKick,
}: {
  snapshot: RoomSnapshot
  /** Shown to the host only. */
  onKick?: (player: Player) => void
}) {
  const players = [...snapshot.players].sort((a, b) => a.joinedAt - b.joinedAt)
  return (
    <ul className="divide-y rounded-lg border bg-card">
      {players.map((p) => {
        const isHost = p.id === snapshot.hostId
        const isMe = p.id === snapshot.you
        return (
          <li key={p.id} className="flex items-center gap-3 px-4 py-3">
            <span
              className={`size-2.5 shrink-0 rounded-full ${p.connected ? 'bg-ok' : 'bg-muted-foreground/40'}`}
              aria-hidden="true"
            />
            <span className={`flex-1 truncate ${p.connected ? '' : 'text-muted-foreground'}`}>
              {p.name}
              {isMe && <span className="text-muted-foreground"> (you)</span>}
              {!p.connected && <span className="text-sm">, reconnecting</span>}
            </span>
            {isHost && (
              <span className="inline-flex items-center gap-1 text-sm text-muted-foreground">
                <Crown className="size-4" aria-hidden="true" /> Host
              </span>
            )}
            {onKick && !isHost && (
              <button
                type="button"
                onClick={() => onKick(p)}
                className="rounded-md px-2 py-1 text-sm text-muted-foreground hover:bg-secondary hover:text-destructive"
              >
                Remove
              </button>
            )}
          </li>
        )
      })}
    </ul>
  )
}
