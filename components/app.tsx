'use client'

import { useSession } from '@/lib/session'
import GameShell from './game-shell'
import Home from './home'
import Lobby from './lobby'
import Notices from './notices'
import { ConnectingScreen } from './status'

export default function App() {
  const { ready, room } = useSession()

  let screen
  if (!ready) screen = null
  else if (!room) screen = <Home />
  else if (!room.snapshot) screen = <ConnectingScreen />
  else if (room.snapshot.game) screen = <GameShell />
  else screen = <Lobby />

  return (
    <>
      {screen}
      <Notices />
    </>
  )
}
