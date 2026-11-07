'use client'

import { getGameModule } from '@/lib/games/modules'
import { GAME_VIEWS } from '@/lib/games/ui'
import { useSession } from '@/lib/session'
import { TroubleBanner } from './status'
import { CallButton } from './call'
import { Menu, X } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'

export default function GameShell() {
  const { room, act, leave, hostNow, call } = useSession()
  // The room controls (call, end game, leave) fold away behind a menu
  // button, closed to start with, so the game gets the screen.
  const [menuOpen, setMenuOpen] = useState(false)
  const snapshot = room!.snapshot!
  const game = snapshot.game!
  const isHost = room!.role === 'host'
  const mod = getGameModule(game.gameId)
  const View = GAME_VIEWS[game.gameId]
  const names = new Map(snapshot.players.map((p) => [p.id, p.name]))
  const seated = game.seats.includes(snapshot.you)
  const away = snapshot.players.filter((p) => !p.connected && game.seats.includes(p.id)).map((p) => p.name)

  function onLeave() {
    const msg = isHost ? 'Close this room for everyone?' : 'Leave the room? Your seat in this game will be given up.'
    if (window.confirm(msg)) leave()
  }

  // Games that fill the screen size themselves with calc(100dvh - var(--shell-head)).
  const topRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const el = topRef.current
    if (!el) return
    const set = () => document.documentElement.style.setProperty('--shell-head', `${el.offsetHeight}px`)
    set()
    const ro = new ResizeObserver(set)
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  function backToLobby() {
    act({ type: 'endGame' })
  }

  return (
    <div className="flex min-h-dvh flex-col">
      <div ref={topRef}>
        <TroubleBanner />
        <header className="border-b px-3 py-1.5">
          <div className="flex items-center gap-2">
            <button
              type="button"
              className="relative -ml-1.5 rounded-md p-1.5 text-muted-foreground hover:bg-secondary"
              aria-expanded={menuOpen}
              aria-controls="room-controls"
              aria-label={menuOpen ? 'Hide room controls' : 'Show room controls'}
              onClick={() => setMenuOpen((o) => !o)}
            >
              {menuOpen ? <X className="size-5" aria-hidden="true" /> : <Menu className="size-5" aria-hidden="true" />}
              {call.inCall && !menuOpen && (
                <span className="absolute right-1 top-1 size-2 rounded-full bg-ok" aria-hidden="true" />
              )}
            </button>
            <h1 className="min-w-0 font-display text-lg font-bold leading-tight">{mod?.name ?? game.gameId}</h1>
            <span className="shrink-0 rounded bg-ticket px-1.5 py-0.5 font-display text-sm font-bold tracking-widest text-ticket-ink">
              {snapshot.code}
            </span>
          </div>
          <nav id="room-controls" aria-label="Room" className={`-mx-2 mt-1 items-center gap-1 whitespace-nowrap ${menuOpen ? "flex" : "hidden"}`}>
            <CallButton align="left" />
            <span className="flex-1" />
            {isHost && (
              <button
                type="button"
                className="rounded-md px-2 py-1 text-sm text-muted-foreground hover:bg-secondary"
                onClick={() => {
                  if (window.confirm('End this game and go back to the lobby?')) backToLobby()
                }}
              >
                End game
              </button>
            )}
            <button
              type="button"
              className="rounded-md px-2 py-1 text-sm text-muted-foreground hover:bg-secondary hover:text-destructive"
              onClick={onLeave}
            >
              {isHost ? 'Close room' : 'Leave'}
            </button>
          </nav>
        </header>
        {away.length > 0 && (
          <p className="bg-secondary px-4 py-2 text-center text-sm" role="status">
            Waiting for {away.join(', ')} to reconnect
          </p>
        )}
        {!seated && (
          <p className="bg-secondary px-4 py-2 text-center text-sm">
            You joined mid-game, so you&apos;re watching this round. You&apos;ll be dealt in next round.
          </p>
        )}
      </div>
      <main className="flex-1">
        {View ? (
          <View
            view={game.view}
            snapshot={snapshot}
            me={snapshot.you}
            isHost={isHost}
            act={(action) => act({ type: 'game', action })}
            playAgain={() => act({ type: 'playAgain' })}
            backToLobby={backToLobby}
            hostNow={hostNow}
            nameOf={(id) => names.get(id) ?? 'Someone who left'}
          />
        ) : (
          <p className="p-6 text-muted-foreground">This game isn&apos;t available in your version. Try refreshing.</p>
        )}
      </main>
    </div>
  )
}
