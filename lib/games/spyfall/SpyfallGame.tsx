'use client'

import { useEffect, useState, useCallback, useRef, useMemo } from 'react'
import { useConnections } from '@/lib/connections-provider'
import { useGame } from '@/lib/game-context'
import type { SpyfallGameState } from './types'
import { SPYFALL_DURATION_MS } from './types'
import { SPYFALL_LOCATIONS } from './locations'
import { Button } from '@/components/ui/button'

function pickRandom<T>(arr: readonly T[]): T {
  return arr[Math.floor(Math.random() * arr.length)]!
}

/**
 * Spyfall — fully driven by the centralised game-state sync in GameProvider.
 *
 * Flow:
 *  1. Host clicks "Start game" in the lobby  →  GameProvider sets isRoomReady
 *     and mounts this component for everyone.
 *  2. On mount the host auto-initialises the Spyfall state (picks spy &
 *     location) and pushes it to all peers via `dispatchGameState`.
 *  3. Non-host players read `gameState` from context and render accordingly.
 *  4. Player actions (votes) are sent to the host via `sendPlayerAction`;
 *     the host tallies them and pushes updated state.
 */
export default function SpyfallGame() {
  const { room, myPeerId } = useConnections()
  const {
    isHost,
    gameState: rawGameState,
    dispatchGameState,
    sendPlayerAction,
    setPlayerActionHandler,
  } = useGame()

  // Cast the generic game state to Spyfall-specific shape
  const gameState = useMemo(
    () => (rawGameState ?? {}) as Partial<SpyfallGameState>,
    [rawGameState]
  )
  const phase = gameState.phase ?? 'waiting'
  const peerIds = useMemo(
    () => (room ? Object.keys(room.peer_connections) : []),
    [room]
  )
  const isSpy = myPeerId === gameState.spyPeerId
  const startedAt = gameState.startedAt ?? 0
  const [timeLeftMs, setTimeLeftMs] = useState(0)
  const [myVote, setMyVote] = useState<string | null>(null)

  // Track votes on the host side
  const hostVotesRef = useRef<Map<string, string>>(new Map())
  const votingEndTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const playerNames: Record<string, string> = room?.peer_connections
    ? Object.fromEntries(
        Object.entries(room.peer_connections).map(([id, data]) => [
          id,
          (data as { playerName: string }).playerName,
        ])
      )
    : {}

  /* ------------------------------------------------------------------ */
  /* Host: auto-initialise on mount                                     */
  /* ------------------------------------------------------------------ */
  const hasInitialised = useRef(false)
  useEffect(() => {
    if (!isHost || hasInitialised.current || peerIds.length < 2) return
    hasInitialised.current = true

    const spyPeerId = pickRandom(peerIds)
    const location = pickRandom(SPYFALL_LOCATIONS)
    const initialState: SpyfallGameState = {
      phase: 'playing',
      spyPeerId,
      location,
      startedAt: Date.now(),
    }
    console.log('[spyfall] Host auto-initialising game state')
    dispatchGameState(initialState as unknown as Record<string, unknown>)
  }, [isHost, peerIds, dispatchGameState])

  /* ------------------------------------------------------------------ */
  /* Timer                                                               */
  /* ------------------------------------------------------------------ */
  useEffect(() => {
    if (phase !== 'playing' || !startedAt) {
      setTimeLeftMs(0)
      return
    }
    const endAt = startedAt + SPYFALL_DURATION_MS
    const tick = () => {
      const now = Date.now()
      const left = Math.max(0, endAt - now)
      setTimeLeftMs(left)
      if (left === 0 && isHost) {
        dispatchGameState({
          ...gameState,
          phase: 'voting',
        } as unknown as Record<string, unknown>)
      }
    }
    tick()
    const interval = setInterval(tick, 1000)
    return () => clearInterval(interval)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [phase, startedAt, isHost])

  /* ------------------------------------------------------------------ */
  /* Host: handle player actions (votes)                                */
  /* ------------------------------------------------------------------ */
  useEffect(() => {
    if (!isHost) {
      setPlayerActionHandler(null)
      return
    }

    const handler = (fromPeerId: string, action: Record<string, unknown>) => {
      if (action.action === 'vote' && typeof action.targetPeerId === 'string') {
        console.log('[spyfall] Host received vote from', fromPeerId, '→', action.targetPeerId)
        hostVotesRef.current.set(fromPeerId, action.targetPeerId)
        checkVoteCompletion()
      }
    }

    setPlayerActionHandler(handler)
    return () => setPlayerActionHandler(null)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isHost, setPlayerActionHandler])

  const checkVoteCompletion = useCallback(() => {
    // All players (including host) should vote; host's vote also goes through sendPlayerAction
    const totalVotersNeeded = peerIds.length
    if (hostVotesRef.current.size < totalVotersNeeded) return

    const votes = Array.from(hostVotesRef.current.values())
    const count: Record<string, number> = {}
    votes.forEach((id) => {
      count[id] = (count[id] ?? 0) + 1
    })
    let max = 0
    let votedOut: string | null = null
    Object.entries(count).forEach(([id, n]) => {
      if (n > max) {
        max = n
        votedOut = id
      }
    })
    const spyPeerId = gameState.spyPeerId!
    const win = votedOut === spyPeerId ? 'innocents' : 'spy'

    dispatchGameState({
      ...gameState,
      phase: 'ended',
      result: { spyPeerId, votedOutPeerId: votedOut ?? null, win },
    } as unknown as Record<string, unknown>)

    if (votingEndTimeoutRef.current) {
      clearTimeout(votingEndTimeoutRef.current)
      votingEndTimeoutRef.current = null
    }
  }, [peerIds, gameState, dispatchGameState])

  /* Host: voting timeout — auto-resolve after 60 s */
  useEffect(() => {
    if (!isHost || phase !== 'voting') return
    hostVotesRef.current = new Map()
    votingEndTimeoutRef.current = setTimeout(() => {
      checkVoteCompletion()
      // If still not enough votes, force end
      const spyPeerId = gameState.spyPeerId!
      const votes = Array.from(hostVotesRef.current.values())
      const count: Record<string, number> = {}
      votes.forEach((id) => {
        count[id] = (count[id] ?? 0) + 1
      })
      let max = 0
      let votedOut: string | null = null
      Object.entries(count).forEach(([id, n]) => {
        if (n > max) {
          max = n
          votedOut = id
        }
      })
      const win = votedOut === spyPeerId ? 'innocents' : 'spy'
      dispatchGameState({
        ...gameState,
        phase: 'ended',
        result: { spyPeerId, votedOutPeerId: votedOut ?? null, win },
      } as unknown as Record<string, unknown>)
    }, 60_000)
    return () => {
      if (votingEndTimeoutRef.current) {
        clearTimeout(votingEndTimeoutRef.current)
        votingEndTimeoutRef.current = null
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isHost, phase])

  /* ------------------------------------------------------------------ */
  /* Player action: cast vote                                           */
  /* ------------------------------------------------------------------ */
  const sendVote = useCallback(
    (targetPeerId: string) => {
      if (phase !== 'voting' || !myPeerId) return
      sendPlayerAction({ action: 'vote', targetPeerId })
      setMyVote(targetPeerId)
    },
    [phase, myPeerId, sendPlayerAction]
  )

  /* ------------------------------------------------------------------ */
  /* Render                                                              */
  /* ------------------------------------------------------------------ */

  // Waiting for host to initialise (should be very brief)
  if (!gameState.phase || phase === 'waiting') {
    return (
      <div className="p-6 max-w-md mx-auto text-center">
        <p className="text-muted-foreground">Setting up the game...</p>
        <div className="mt-3 flex justify-center">
          <div className="animate-pulse flex space-x-1">
            <div className="w-2 h-2 bg-gray-400 rounded-full"></div>
            <div className="w-2 h-2 bg-gray-400 rounded-full"></div>
            <div className="w-2 h-2 bg-gray-400 rounded-full"></div>
          </div>
        </div>
      </div>
    )
  }

  if (phase === 'playing') {
    const minutes = Math.floor(timeLeftMs / 60000)
    const seconds = Math.floor((timeLeftMs % 60000) / 1000)
    return (
      <div className="p-6 max-w-lg mx-auto space-y-6">
        <div className="text-center text-2xl font-mono tabular-nums">
          {minutes}:{seconds.toString().padStart(2, '0')}
        </div>
        {isSpy ? (
          <p className="text-center text-lg font-medium">
            You are the <span className="text-red-500 font-bold">spy</span>. Figure out the location without getting caught!
          </p>
        ) : (
          <p className="text-center text-lg font-medium">
            Location: <span className="text-primary font-bold">{gameState.location}</span>
          </p>
        )}
        <div className="text-center text-sm text-muted-foreground">
          {peerIds.length} players in the game
        </div>

        {/* All possible locations — helps everyone ask/answer questions */}
        <div className="border border-border rounded-lg p-4">
          <h4 className="text-sm font-semibold text-muted-foreground mb-3 text-center">
            Possible Locations
          </h4>
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-1.5">
            {SPYFALL_LOCATIONS.map((loc) => (
              <span
                key={loc}
                className={`text-xs px-2 py-1 rounded text-center ${
                  !isSpy && loc === gameState.location
                    ? 'bg-primary/15 text-primary font-semibold'
                    : 'bg-muted text-muted-foreground'
                }`}
              >
                {loc}
              </span>
            ))}
          </div>
        </div>
      </div>
    )
  }

  if (phase === 'voting') {
    const others = peerIds.filter((p) => p !== myPeerId)
    return (
      <div className="p-6 max-w-md mx-auto space-y-4">
        <h3 className="font-semibold">Vote for who you think is the spy</h3>
        <ul className="space-y-2">
          {others.map((peerId) => (
            <li key={peerId}>
              <Button
                variant={myVote === peerId ? 'default' : 'outline'}
                className="w-full justify-start"
                onClick={() => sendVote(peerId)}
                disabled={!!myVote}
              >
                {playerNames[peerId] ?? peerId.slice(0, 8)}
              </Button>
            </li>
          ))}
        </ul>
        {myVote && (
          <p className="text-sm text-muted-foreground">
            Vote sent. Waiting for other players...
          </p>
        )}
      </div>
    )
  }

  const result = gameState.result
  if (phase === 'ended' && result) {
    const votedOutName = result.votedOutPeerId
      ? playerNames[result.votedOutPeerId]
      : 'No one'
    const spyName = playerNames[result.spyPeerId]
    return (
      <div className="p-6 max-w-md mx-auto space-y-4">
        <h3 className="font-semibold text-xl">Game Over</h3>
        <p>
          The spy was: <strong>{spyName ?? result.spyPeerId}</strong>
        </p>
        <p>
          Voted out: <strong>{votedOutName}</strong>
        </p>
        <p className="font-medium text-lg">
          {result.win === 'innocents' ? 'Innocents win!' : 'The spy wins!'}
        </p>
      </div>
    )
  }

  return null
}
