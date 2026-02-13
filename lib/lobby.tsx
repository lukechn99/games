'use client'

import { useConnections } from './connections-provider'
import { useGame } from './game-context'
import { getAllGames, getGame } from './game-types'
import type { GameId } from './game-types'
import { Button } from '@/components/ui/button'

interface PlayerInfo {
  playerName: string
  isHost?: boolean
}

export default function Lobby() {
  const { room, myPeerId, dataChannels } = useConnections()
  const { chooseGame, chosenGame, startGame, isRoomReady, isHost } = useGame()
  const games = getAllGames()

  if (!room) {
    return (
      <div className="p-6">
        <h2 className="text-lg font-semibold">No room joined</h2>
      </div>
    )
  }

  const peerConnections = room.peer_connections || {}
  const players: { peerId: string; info: PlayerInfo }[] = Object.entries(peerConnections).map(
    ([peerId, info]) => ({
      peerId,
      info: info as PlayerInfo,
    })
  )

  const openChannels = Array.from(dataChannels.values()).filter(
    (dc) => dc.readyState === 'open'
  ).length

  const chosenGameDef = chosenGame ? getGame(chosenGame) : null

  return (
    <div className="w-full max-w-md mx-auto p-6">
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
        {/* Room Code Header */}
        <div className="text-center mb-6">
          <p className="text-sm text-gray-500 dark:text-gray-400 uppercase tracking-wide">
            Room Code
          </p>
          <h2 className="text-3xl font-bold tracking-widest text-gray-900 dark:text-white">
            {room.room_code}
          </h2>
        </div>

        {/* Players List */}
        <div>
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-4">
            Players ({players.length})
          </h3>
          <ul className="space-y-2">
            {players.map(({ peerId, info }) => (
              <li
                key={peerId}
                className="flex items-center justify-between p-3 bg-gray-50 dark:bg-gray-700 rounded-lg"
              >
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-full bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center text-white font-semibold">
                    {info.playerName?.charAt(0)?.toUpperCase() || '?'}
                  </div>
                  <span className="font-medium text-gray-900 dark:text-white">
                    {info.playerName || 'Unknown Player'}
                  </span>
                </div>
                <div className="flex items-center gap-2">
                  {info.isHost && (
                    <span className="px-2 py-1 text-xs font-medium bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200 rounded-full">
                      Host
                    </span>
                  )}
                  {peerId === myPeerId && (
                    <span className="px-2 py-1 text-xs font-medium bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200 rounded-full">
                      You
                    </span>
                  )}
                </div>
              </li>
            ))}
          </ul>
        </div>

        {/* WebRTC connection status */}
        {players.length > 1 && (
          <div className="mt-4 flex items-center gap-2">
            <div
              className={`w-2 h-2 rounded-full ${
                openChannels >= players.length - 1
                  ? 'bg-green-500'
                  : openChannels > 0
                  ? 'bg-yellow-500'
                  : 'bg-red-500'
              }`}
            />
            <span className="text-xs text-gray-500 dark:text-gray-400">
              {openChannels}/{players.length - 1} peer connections active
            </span>
          </div>
        )}

        {/* Host: Choose game and Start */}
        {isHost && !isRoomReady && (
          <div className="mt-6 space-y-3">
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

        {/* Non-host: show what game is selected */}
        {!isHost && chosenGame && !isRoomReady && (
          <div className="mt-6 p-4 bg-blue-50 dark:bg-blue-900/20 rounded-lg text-center space-y-2">
            <p className="text-sm font-medium text-blue-800 dark:text-blue-200">
              Host selected: <strong>{chosenGameDef?.name ?? chosenGame}</strong>
            </p>
            <p className="text-xs text-blue-600 dark:text-blue-300">
              Waiting for host to start the game...
            </p>
            <div className="flex justify-center">
              <div className="animate-pulse flex space-x-1">
                <div className="w-2 h-2 bg-blue-400 rounded-full"></div>
                <div className="w-2 h-2 bg-blue-400 rounded-full animation-delay-200"></div>
                <div className="w-2 h-2 bg-blue-400 rounded-full animation-delay-400"></div>
              </div>
            </div>
          </div>
        )}

        {/* Non-host: no game selected yet */}
        {!isHost && !chosenGame && !isRoomReady && players.length >= 2 && (
          <div className="mt-6 text-center">
            <p className="text-sm text-gray-500 dark:text-gray-400">
              Waiting for the host to choose a game...
            </p>
          </div>
        )}

        {/* Waiting for players */}
        {players.length < 2 && (
          <div className="mt-6 text-center">
            <p className="text-sm text-gray-500 dark:text-gray-400">
              Waiting for more players to join...
            </p>
            <div className="mt-2 flex justify-center">
              <div className="animate-pulse flex space-x-1">
                <div className="w-2 h-2 bg-gray-400 rounded-full"></div>
                <div className="w-2 h-2 bg-gray-400 rounded-full animation-delay-200"></div>
                <div className="w-2 h-2 bg-gray-400 rounded-full animation-delay-400"></div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
