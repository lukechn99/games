'use client'

import {
  createContext,
  useContext,
  useState,
  useCallback,
  useEffect,
  useRef,
  type ReactNode,
} from 'react'
import type { GameId } from './game-types'
import { getGame } from './game-types'
import { useConnections } from './connections-provider'

export interface RoomConfigMessage {
  type: 'room_config'
  gameId: GameId | null
  roomReady: boolean
}

type GameMessageCallback = (fromPeerId: string, msg: unknown) => void

type GameContextValue = {
  chosenGame: GameId | null
  isRoomReady: boolean
  chooseGame: (gameId: GameId | null) => void
  startGame: () => void
  exitGame: () => void
  isHost: boolean
  setGameMessageCallback: (cb: GameMessageCallback | null) => void
}

const GameContext = createContext<GameContextValue | null>(null)

export function GameProvider({ children }: { children: ReactNode }) {
  const { room, myPeerId, broadcastGameMessage, setGameMessageHandler } = useConnections()
  const [chosenGame, setChosenGame] = useState<GameId | null>(null)
  const [isRoomReady, setIsRoomReady] = useState(false)
  const gameMessageCallbackRef = useRef<GameMessageCallback | null>(null)

  const isHost = !!myPeerId && !!(room?.peer_connections?.[myPeerId] as { isHost?: boolean })?.isHost

  const setGameMessageCallback = useCallback((cb: GameMessageCallback | null) => {
    gameMessageCallbackRef.current = cb
  }, [])

  useEffect(() => {
    const handler = (fromPeerId: string, msg: unknown) => {
      const m = msg as RoomConfigMessage
      if (m?.type === 'room_config') {
        setChosenGame(m.gameId)
        setIsRoomReady(m.roomReady)
      }
      gameMessageCallbackRef.current?.(fromPeerId, msg)
    }
    setGameMessageHandler(handler)
    return () => setGameMessageHandler(null)
  }, [setGameMessageHandler])

  const chooseGame = useCallback(
    (gameId: GameId | null) => {
      if (!isHost) return
      setChosenGame(gameId)
      setIsRoomReady(false)
      broadcastGameMessage({ type: 'room_config', gameId, roomReady: false })
    },
    [isHost, broadcastGameMessage]
  )

  const startGame = useCallback(() => {
    if (!isHost || !chosenGame) return
    setIsRoomReady(true)
    broadcastGameMessage({ type: 'room_config', gameId: chosenGame, roomReady: true })
  }, [isHost, chosenGame, broadcastGameMessage])

  const exitGame = useCallback(() => {
    if (!isHost) return
    setChosenGame(null)
    setIsRoomReady(false)
    broadcastGameMessage({ type: 'room_config', gameId: null, roomReady: false })
  }, [isHost, broadcastGameMessage])

  return (
    <GameContext.Provider
      value={{
        chosenGame,
        isRoomReady,
        chooseGame,
        startGame,
        exitGame,
        isHost,
        setGameMessageCallback,
      }}
    >
      {children}
    </GameContext.Provider>
  )
}

export function useGame() {
  const ctx = useContext(GameContext)
  if (!ctx) {
    throw new Error('useGame must be used within GameProvider')
  }
  return ctx
}

export function GameCanvas() {
  const { chosenGame, exitGame, isRoomReady } = useGame()
  const { room } = useConnections()

  if (!room || !isRoomReady || !chosenGame) return null

  const gameDef = getGame(chosenGame)
  if (!gameDef) return null

  const GameComponent = gameDef.component

  return (
    <div className="flex flex-col h-screen bg-background">
      <header className="flex-shrink-0 h-12 border-b border-border flex items-center justify-between px-4 bg-card">
        <span className="font-medium text-sm text-muted-foreground">
          {gameDef.name}
        </span>
        <button
          type="button"
          onClick={exitGame}
          className="text-sm text-muted-foreground hover:text-foreground underline"
        >
          Exit game
        </button>
      </header>
      <main className="flex-1 min-h-0 overflow-auto">
        <GameComponent />
      </main>
    </div>
  )
}
