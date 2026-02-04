'use client'

import { useConnections } from './connections-provider'
import { useGame } from './game-context'
import { getAllGames } from './game-types'
import type { GameId } from './game-types'
import { Button } from '@/components/ui/button'

export default function Lobby() {
  const { room, myPeerId } = useConnections()
  const { chooseGame, chosenGame, startGame, isRoomReady } = useGame()
  const games = getAllGames()
  const hostPeerId = room ? Object.entries(room.peer_connections).find(([, info]) => (info as { isHost?: boolean }).isHost)?.[0] : null
  const amHost = myPeerId === hostPeerId

  if (!room) {
    return (
      <div className="p-6">
        <h2 className="text-lg font-semibold">No room joined</h2>
      </div>
    )
  }

  return (
    <div className="p-6 max-w-lg mx-auto space-y-6">
      <div>
        <h2 className="text-lg font-semibold">Room code</h2>
        <p className="font-mono text-2xl tracking-wider text-primary">{room.room_code}</p>
      </div>
      <div>
        <h3 className="text-sm font-medium text-muted-foreground mb-2">Players</h3>
        <ul className="space-y-1">
          {Object.entries(room.peer_connections).map(([peerId, info]) => (
            <li key={peerId} className="flex items-center gap-2">
              <span>{(info as { playerName: string }).playerName}</span>
              {(info as { isHost?: boolean }).isHost && (
                <span className="text-xs text-muted-foreground">(Host)</span>
              )}
            </li>
          ))}
        </ul>
      </div>
      {amHost && !isRoomReady && (
        <div className="space-y-3">
          <h3 className="text-sm font-medium text-muted-foreground">Choose a game</h3>
          <div className="flex flex-wrap gap-2">
            {games.map((g) => (
              <Button
                key={g.id}
                variant={chosenGame === g.id ? 'default' : 'outline'}
                size="sm"
                onClick={() => chooseGame(chosenGame === g.id ? null : (g.id as GameId))}
              >
                {g.name}
              </Button>
            ))}
          </div>
          {chosenGame && (
            <Button className="w-full" onClick={startGame}>
              Start game
            </Button>
          )}
        </div>
      )}
    </div>
  )
}