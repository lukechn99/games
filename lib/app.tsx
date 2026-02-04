'use client'

import { useConnections } from './connections-provider'
import { useGame } from './game-context'
import { GameCanvas } from './game-context'
import Lobby from './lobby'
import RoomControls from './room-controls'

// Register games (side effect)
import './games/spyfall'
import './games/secret-hitler'
import './games/codenames'
import './games/betrayal'

export default function App() {
  const { room } = useConnections()
  const { isRoomReady, chosenGame } = useGame()

  if (!room) {
    return (
      <div className="min-h-screen">
        <RoomControls />
      </div>
    )
  }

  if (isRoomReady && chosenGame) {
    return <GameCanvas />
  }

  return (
    <div className="min-h-screen">
      <Lobby />
    </div>
  )
}