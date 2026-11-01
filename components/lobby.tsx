'use client'

import { COMING_SOON, GAME_MODULES, getGameModule } from '@/lib/games/modules'
import { useSession } from '@/lib/session'
import PlayerList from './player-list'
import { StatusPill, TroubleBanner } from './status'
import Ticket from './ticket'
import { Button } from './ui/button'

export default function Lobby() {
  const { room, act, leave } = useSession()
  const snapshot = room!.snapshot!
  const isHost = room!.role === 'host'
  const selected = snapshot.selectedGameId ? getGameModule(snapshot.selectedGameId) : undefined
  const connected = snapshot.players.filter((p) => p.connected).length

  let startBlocker: string | null = null
  if (!selected) startBlocker = 'Pick a game to start'
  else if (connected < selected.minPlayers) {
    const need = selected.minPlayers - connected
    startBlocker = `Waiting for ${need} more player${need === 1 ? '' : 's'}`
  } else if (connected > selected.maxPlayers) {
    startBlocker = `${selected.name} allows at most ${selected.maxPlayers} players`
  }

  function onLeave() {
    if (isHost && !window.confirm('Close this room for everyone?')) return
    leave()
  }

  return (
    <div className="min-h-dvh pb-28">
      <TroubleBanner />
      <main className="mx-auto flex max-w-md flex-col gap-8 px-6 pt-8">
        <div className="flex flex-col items-center gap-3">
          <Ticket code={snapshot.code} />
          <StatusPill />
        </div>

        <section aria-labelledby="players-heading">
          <h2 id="players-heading" className="mb-3 font-display text-xl font-bold">
            Players <span className="text-muted-foreground">{connected}</span>
          </h2>
          <PlayerList
            snapshot={snapshot}
            onKick={
              isHost
                ? (p) => {
                    if (window.confirm(`Remove ${p.name} from the room?`)) act({ type: 'kick', playerId: p.id })
                  }
                : undefined
            }
          />
        </section>

        <section aria-labelledby="game-heading">
          <h2 id="game-heading" className="mb-3 font-display text-xl font-bold">
            Game
          </h2>
          {isHost ? (
            <div className="flex flex-col gap-2" role="radiogroup" aria-label="Choose a game">
              {GAME_MODULES.map((g) => {
                const active = g.id === snapshot.selectedGameId
                return (
                  <button
                    key={g.id}
                    type="button"
                    role="radio"
                    aria-checked={active}
                    onClick={() => act({ type: 'selectGame', gameId: active ? null : g.id })}
                    className={`rounded-lg border-2 bg-card p-4 text-left transition-colors ${
                      active ? 'border-primary' : 'border-border hover:border-muted-foreground/40'
                    }`}
                  >
                    <span className="flex items-baseline justify-between gap-2">
                      <span className="font-display text-lg font-bold">{g.name}</span>
                      <span className="text-sm text-muted-foreground">
                        {g.minPlayers}–{g.maxPlayers} players
                      </span>
                    </span>
                    <span className="mt-1 block text-sm text-muted-foreground">{g.description}</span>
                  </button>
                )
              })}
              {COMING_SOON.map((g) => (
                <div key={g.name} className="flex justify-between rounded-lg border border-dashed p-4 text-muted-foreground">
                  <span>{g.name}</span>
                  <span className="text-sm">Coming soon</span>
                </div>
              ))}
            </div>
          ) : selected ? (
            <div className="rounded-lg border bg-card p-4">
              <p className="font-display text-lg font-bold">{selected.name}</p>
              <p className="mt-1 text-sm text-muted-foreground">{selected.description}</p>
            </div>
          ) : (
            <p className="text-muted-foreground">The host is choosing a game.</p>
          )}
        </section>

        <button type="button" onClick={onLeave} className="self-center text-sm text-muted-foreground underline-offset-4 hover:underline">
          {isHost ? 'Close room' : 'Leave room'}
        </button>
      </main>

      <div className="fixed inset-x-0 bottom-0 border-t bg-background/95 px-6 py-4 backdrop-blur">
        <div className="mx-auto max-w-md">
          {isHost ? (
            <Button
              size="lg"
              className="h-12 w-full text-base"
              disabled={!!startBlocker}
              onClick={() => act({ type: 'startGame' })}
            >
              {startBlocker ?? `Start ${selected!.name}`}
            </Button>
          ) : (
            <p className="py-3 text-center text-muted-foreground">Waiting for the host to start</p>
          )}
        </div>
      </div>
    </div>
  )
}
