'use client'

import { Bot, Crown } from 'lucide-react'
import type { BotLevel, Player, RoomSnapshot } from '@/lib/engine/types'

const LEVELS: BotLevel[] = ['easy', 'medium', 'hard']

export default function PlayerList({
  snapshot,
  onKick,
  onBotLevel,
}: {
  snapshot: RoomSnapshot
  /** Shown to the host only. */
  onKick?: (player: Player) => void
  onBotLevel?: (player: Player, level: BotLevel) => void
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
            <span className={`flex min-w-0 flex-1 items-center gap-1.5 truncate ${p.connected ? '' : 'text-muted-foreground'}`}>
              {p.bot && <Bot className="size-4 shrink-0 text-muted-foreground" aria-label="Computer player" />}
              {p.name}
              {isMe && <span className="text-muted-foreground"> (you)</span>}
              {!p.connected && <span className="text-sm">, reconnecting</span>}
            </span>
            {p.bot && onBotLevel && (
              <select
                value={p.bot.level}
                onChange={(e) => onBotLevel(p, e.target.value as BotLevel)}
                aria-label={`${p.name}'s difficulty`}
                className="h-8 rounded-md border bg-card px-1.5 text-sm capitalize"
              >
                {LEVELS.map((l) => (
                  <option key={l} value={l}>
                    {l[0]!.toUpperCase() + l.slice(1)}
                  </option>
                ))}
              </select>
            )}
            {p.bot && !onBotLevel && <span className="text-sm capitalize text-muted-foreground">{p.bot.level}</span>}
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
