"use client"

import { useConnections } from "./connections-provider"

interface PlayerInfo {
  playerName: string
  isHost?: boolean
}

export default function Lobby() {
  const { room, myPeerId } = useConnections()

  if (!room) {
    return null
  }

  const peerConnections = room.peer_connections || {}
  const players: { peerId: string; info: PlayerInfo }[] = Object.entries(peerConnections).map(
    ([peerId, info]) => ({
      peerId,
      info: info as PlayerInfo,
    })
  )

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
                  {/* Player Avatar Placeholder */}
                  <div className="w-10 h-10 rounded-full bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center text-white font-semibold">
                    {info.playerName?.charAt(0)?.toUpperCase() || "?"}
                  </div>
                  <span className="font-medium text-gray-900 dark:text-white">
                    {info.playerName || "Unknown Player"}
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

        {/* Waiting Message */}
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
