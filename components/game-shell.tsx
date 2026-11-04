'use client'

import { getGameModule } from '@/lib/games/modules'
import { GAME_VIEWS } from '@/lib/games/ui'
import { useSession } from '@/lib/session'
import { TroubleBanner } from './status'
import { CallButton } from './call'

export default function GameShell() {
  const { room, act, leave, hostNow } = useSession()
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

  function backToLobby() {
    act({ type: 'endGame' })
  }

  return (
    <div className="flex min-h-dvh flex-col">
      <TroubleBanner />
      <header className="flex items-center gap-2 border-b px-3 py-2.5 whitespace-nowrap">
        <span className="min-w-0 truncate font-display text-lg font-bold">{mod?.name ?? game.gameId}</span>
        <span className="hidden shrink-0 rounded bg-ticket px-1.5 py-0.5 font-display text-sm font-bold tracking-widest text-ticket-ink min-[430px]:inline">
          {snapshot.code}
        </span>
        <span className="flex-1" />
        <CallButton />
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
