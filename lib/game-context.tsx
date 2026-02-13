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

/* ------------------------------------------------------------------ */
/*  Message types that flow over WebRTC data channels                 */
/* ------------------------------------------------------------------ */

/** Host → all: room-level config (game choice, ready flag) */
export interface RoomConfigMessage {
  type: 'room_config'
  gameId: GameId | null
  roomReady: boolean
}

/** Host → all: authoritative game state blob */
export interface GameStateMessage {
  type: 'game_state'
  gameId: GameId
  state: Record<string, unknown>
}

/** Player → host: a player action (vote, move, etc.) */
export interface PlayerActionMessage {
  type: 'player_action'
  action: Record<string, unknown>
}

/* ------------------------------------------------------------------ */

type PlayerActionHandler = (fromPeerId: string, action: Record<string, unknown>) => void

type GameContextValue = {
  /* Room-level */
  chosenGame: GameId | null
  isRoomReady: boolean
  chooseGame: (gameId: GameId | null) => void
  startGame: () => void
  exitGame: () => void
  isHost: boolean

  /* Centralised game state – the host is authoritative */
  gameState: Record<string, unknown> | null
  dispatchGameState: (state: Record<string, unknown>) => void
  sendPlayerAction: (action: Record<string, unknown>) => void
  setPlayerActionHandler: (handler: PlayerActionHandler | null) => void
}

const GameContext = createContext<GameContextValue | null>(null)

export function GameProvider({ children }: { children: ReactNode }) {
  const {
    room,
    myPeerId,
    broadcastGameMessage,
    sendGameMessage,
    setGameMessageHandler,
    dataChannels,
  } = useConnections()

  const [chosenGame, setChosenGame] = useState<GameId | null>(null)
  const [isRoomReady, setIsRoomReady] = useState(false)
  const [gameState, setGameState] = useState<Record<string, unknown> | null>(null)

  const playerActionHandlerRef = useRef<PlayerActionHandler | null>(null)
  const gameStateRef = useRef<Record<string, unknown> | null>(null)
  const chosenGameRef = useRef<GameId | null>(null)
  const isRoomReadyRef = useRef(false)
  const broadcastRef = useRef(broadcastGameMessage)
  const sendMsgRef = useRef(sendGameMessage)

  const isHost =
    !!myPeerId &&
    !!(room?.peer_connections?.[myPeerId] as { isHost?: boolean })?.isHost

  const isHostRef = useRef(isHost)
  useEffect(() => { isHostRef.current = isHost }, [isHost])

  // Keep refs in sync
  useEffect(() => { gameStateRef.current = gameState }, [gameState])
  useEffect(() => { chosenGameRef.current = chosenGame }, [chosenGame])
  useEffect(() => { isRoomReadyRef.current = isRoomReady }, [isRoomReady])
  useEffect(() => { broadcastRef.current = broadcastGameMessage }, [broadcastGameMessage])
  useEffect(() => { sendMsgRef.current = sendGameMessage }, [sendGameMessage])

  /* ---- handler registration ---- */
  const setPlayerActionHandler = useCallback((handler: PlayerActionHandler | null) => {
    playerActionHandlerRef.current = handler
  }, [])

  /* ---- Incoming message handler ---- */
  useEffect(() => {
    const handler = (fromPeerId: string, msg: unknown) => {
      const m = msg as Record<string, unknown>
      if (!m || typeof m !== 'object') return

      if (m.type === 'room_config') {
        const rc = m as unknown as RoomConfigMessage
        console.log('[game-ctx] Received room_config:', rc)
        setChosenGame(rc.gameId)
        setIsRoomReady(rc.roomReady)
        // If the game is being exited / reset, clear game state
        if (!rc.roomReady) {
          setGameState(null)
        }
      }

      if (m.type === 'game_state') {
        const gs = m as unknown as GameStateMessage
        console.log('[game-ctx] Received game_state from host:', gs.gameId)
        setGameState(gs.state)
      }

      if (m.type === 'player_action') {
        const pa = m as unknown as PlayerActionMessage
        console.log('[game-ctx] Received player_action from', fromPeerId)
        playerActionHandlerRef.current?.(fromPeerId, pa.action)
      }
    }
    setGameMessageHandler(handler)
    return () => setGameMessageHandler(null)
  }, [setGameMessageHandler])

  /* ---- Host: re-sync newly opened data channels ---- */
  const prevChannelCountRef = useRef(0)
  useEffect(() => {
    if (!isHostRef.current) return
    const currentCount = dataChannels.size
    // If a new channel appeared, push current state to it
    if (currentCount > prevChannelCountRef.current) {
      console.log(`[game-ctx] New data channel detected (${prevChannelCountRef.current} → ${currentCount}), re-syncing`)
      const currentGameId = chosenGameRef.current
      const currentReady = isRoomReadyRef.current
      const currentState = gameStateRef.current

      // Send room config to all (idempotent)
      if (currentGameId !== null || currentReady) {
        broadcastRef.current({
          type: 'room_config',
          gameId: currentGameId,
          roomReady: currentReady,
        } as RoomConfigMessage)
      }
      // Send current game state
      if (currentState && currentGameId) {
        broadcastRef.current({
          type: 'game_state',
          gameId: currentGameId,
          state: currentState,
        } as GameStateMessage)
      }
    }
    prevChannelCountRef.current = currentCount
  }, [dataChannels])

  /* ---- Host actions ---- */

  const chooseGame = useCallback(
    (gameId: GameId | null) => {
      if (!isHostRef.current) return
      setChosenGame(gameId)
      setIsRoomReady(false)
      setGameState(null)
      broadcastRef.current({ type: 'room_config', gameId, roomReady: false } as RoomConfigMessage)
    },
    []
  )

  const startGame = useCallback(() => {
    const game = chosenGameRef.current
    if (!isHostRef.current || !game) return
    console.log('[game-ctx] Host starting game:', game)
    setIsRoomReady(true)
    broadcastRef.current({
      type: 'room_config',
      gameId: game,
      roomReady: true,
    } as RoomConfigMessage)
  }, [])

  const exitGame = useCallback(() => {
    if (!isHostRef.current) return
    setChosenGame(null)
    setIsRoomReady(false)
    setGameState(null)
    broadcastRef.current({
      type: 'room_config',
      gameId: null,
      roomReady: false,
    } as RoomConfigMessage)
  }, [])

  /* ---- Game state management ---- */

  /** Host only: set the authoritative game state and broadcast to all peers */
  const dispatchGameState = useCallback(
    (state: Record<string, unknown>) => {
      if (!isHostRef.current) return
      const gameId = chosenGameRef.current
      if (!gameId) return
      console.log('[game-ctx] Host dispatching game state for', gameId)
      setGameState(state)
      broadcastRef.current({
        type: 'game_state',
        gameId,
        state,
      } as GameStateMessage)
    },
    []
  )

  /** Any player: send an action to the host */
  const roomRef = useRef(room)
  useEffect(() => { roomRef.current = room }, [room])
  const myPeerIdRef = useRef(myPeerId)
  useEffect(() => { myPeerIdRef.current = myPeerId }, [myPeerId])

  const sendPlayerAction = useCallback(
    (action: Record<string, unknown>) => {
      const currentRoom = roomRef.current
      if (!currentRoom?.peer_connections) return
      const hostPeerId = Object.entries(currentRoom.peer_connections).find(
        ([, info]) => (info as { isHost?: boolean }).isHost
      )?.[0]
      if (!hostPeerId) {
        console.warn('[game-ctx] Cannot send player action — no host found')
        return
      }
      const localPeerId = myPeerIdRef.current
      // If we ARE the host, just call the handler directly
      if (hostPeerId === localPeerId) {
        playerActionHandlerRef.current?.(localPeerId!, action)
        return
      }
      console.log('[game-ctx] Sending player_action to host', hostPeerId)
      sendMsgRef.current(hostPeerId, {
        type: 'player_action',
        action,
      } as PlayerActionMessage)
    },
    []
  )

  return (
    <GameContext.Provider
      value={{
        chosenGame,
        isRoomReady,
        chooseGame,
        startGame,
        exitGame,
        isHost,
        gameState,
        dispatchGameState,
        sendPlayerAction,
        setPlayerActionHandler,
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
  const { chosenGame, exitGame, isRoomReady, isHost } = useGame()
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
        {isHost && (
          <button
            type="button"
            onClick={exitGame}
            className="text-sm text-muted-foreground hover:text-foreground underline"
          >
            Exit game
          </button>
        )}
      </header>
      <main className="flex-1 min-h-0 overflow-auto">
        <GameComponent />
      </main>
    </div>
  )
}
