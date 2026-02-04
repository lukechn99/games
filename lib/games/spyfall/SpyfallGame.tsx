'use client'

import { useEffect, useState, useCallback, useRef } from 'react'
import { useConnections } from '@/lib/connections-provider'
import { useGame } from '@/lib/game-context'
import type { SpyfallGameState, SpyfallVoteMessage, SpyfallStateMessage } from './types'
import { SPYFALL_DURATION_MS } from './types'
import { SPYFALL_LOCATIONS } from './locations'
import { Button } from '@/components/ui/button'

function pickRandom<T>(arr: readonly T[]): T {
  return arr[Math.floor(Math.random() * arr.length)]!
}

export default function SpyfallGame() {
  const { room, myPeerId, broadcastGameMessage, sendGameMessage, setGameMessageHandler } = useConnections()
  const { setGameMessageCallback } = useGame()
  const [gameState, setGameState] = useState<Partial<SpyfallGameState>>({})
  const phase = gameState.phase ?? 'playing'
  const peerIds = room ? Object.keys(room.peer_connections) : []
  const isHost = !!myPeerId && !!(room?.peer_connections?.[myPeerId] as { isHost?: boolean })?.isHost
  const isSpy = myPeerId === gameState.spyPeerId
  const startedAt = gameState.startedAt ?? 0
  const [timeLeftMs, setTimeLeftMs] = useState(0)
  const [myVote, setMyVote] = useState<string | null>(null)
  const hostVotesRef = useRef<Map<string, string>>(new Map())
  const votingEndTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const playerNames = room?.peer_connections
    ? Object.fromEntries(
        Object.entries(room.peer_connections).map(([id, data]) => [
          id,
          (data as { playerName: string }).playerName,
        ])
      )
    : {}

  const broadcastState = useCallback(
    (update: Partial<SpyfallGameState>) => {
      const next = { ...gameState, ...update }
      setGameState(next)
      if (isHost) broadcastGameMessage({ type: 'spyfall_state', state: next })
    },
    [isHost, broadcastGameMessage, gameState]
  )

  // Timer
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
        broadcastState({ phase: 'voting' })
      }
    }
    tick()
    const interval = setInterval(tick, 1000)
    return () => clearInterval(interval)
  }, [phase, startedAt, isHost, broadcastState])

  const spyPeerIdRef = useRef(gameState.spyPeerId)
  spyPeerIdRef.current = gameState.spyPeerId

  // Receive state from host and handle votes (host only)
  useEffect(() => {
    const handler = (fromPeerId: string, msg: unknown) => {
      const stateMsg = msg as SpyfallStateMessage
      if (stateMsg?.type === 'spyfall_state' && stateMsg.state) {
        setGameState((prev) => ({ ...prev, ...stateMsg.state }))
        return
      }
      const voteMsg = msg as SpyfallVoteMessage
      if (voteMsg?.type === 'spyfall_vote' && voteMsg.targetPeerId && isHost) {
        hostVotesRef.current.set(fromPeerId, voteMsg.targetPeerId)
        const peersWithoutHost = peerIds.filter((p) => p !== myPeerId)
        if (hostVotesRef.current.size >= peersWithoutHost.length) {
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
          const spyPeerId = spyPeerIdRef.current!
          const win = votedOut === spyPeerId ? 'innocents' : 'spy'
          broadcastState({
            phase: 'ended',
            result: {
              spyPeerId,
              votedOutPeerId: votedOut ?? null,
              win,
            },
          })
          if (votingEndTimeoutRef.current) {
            clearTimeout(votingEndTimeoutRef.current)
            votingEndTimeoutRef.current = null
          }
        }
      }
    }
    setGameMessageCallback(handler)
    return () => setGameMessageCallback(null)
  }, [isHost, myPeerId, peerIds, setGameMessageCallback, broadcastState])

  // Host: voting timeout
  useEffect(() => {
    if (!isHost || phase !== 'voting') return
    hostVotesRef.current = new Map()
    votingEndTimeoutRef.current = setTimeout(() => {
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
      const spyPeerId = spyPeerIdRef.current!
      const win = votedOut === spyPeerId ? 'innocents' : 'spy'
      broadcastState({
        phase: 'ended',
        result: {
          spyPeerId,
          votedOutPeerId: votedOut ?? null,
          win,
        },
      })
      votingEndTimeoutRef.current = null
    }, 60_000)
    return () => {
      if (votingEndTimeoutRef.current) {
        clearTimeout(votingEndTimeoutRef.current)
        votingEndTimeoutRef.current = null
      }
    }
  }, [isHost, phase, broadcastState])

  const startGame = useCallback(() => {
    if (!isHost || peerIds.length < 2) return
    const spyPeerId = pickRandom(peerIds)
    const location = pickRandom(SPYFALL_LOCATIONS)
    broadcastState({
      phase: 'playing',
      spyPeerId,
      location,
      startedAt: Date.now(),
    })
  }, [isHost, peerIds, broadcastState])

  const sendVote = useCallback(
    (targetPeerId: string) => {
      if (phase !== 'voting' || !myPeerId) return
      const hostPeerId = peerIds.find((id) => (room?.peer_connections?.[id] as { isHost?: boolean })?.isHost)
      if (hostPeerId) {
        sendGameMessage(hostPeerId, { type: 'spyfall_vote', targetPeerId })
        setMyVote(targetPeerId)
      }
    },
    [phase, myPeerId, peerIds, room?.peer_connections, sendGameMessage]
  )

  if (!gameState.phase && isHost) {
    return (
      <div className="p-6 max-w-md mx-auto">
        <p className="text-muted-foreground mb-4">You’re the host. Start the game when everyone is ready.</p>
        <Button onClick={startGame} disabled={peerIds.length < 2}>
          Start Spyfall
        </Button>
      </div>
    )
  }

  if (!gameState.phase) {
    return (
      <div className="p-6 max-w-md mx-auto">
        <p className="text-muted-foreground">Waiting for the host to start the game…</p>
      </div>
    )
  }

  if (phase === 'playing') {
    const minutes = Math.floor(timeLeftMs / 60000)
    const seconds = Math.floor((timeLeftMs % 60000) / 1000)
    return (
      <div className="p-6 max-w-md mx-auto space-y-6">
        <div className="text-center text-2xl font-mono tabular-nums">
          {minutes}:{seconds.toString().padStart(2, '0')}
        </div>
        {isSpy ? (
          <p className="text-center text-lg font-medium">You are the spy. Don’t get caught.</p>
        ) : (
          <p className="text-center text-lg font-medium">
            Location: <span className="text-primary">{gameState.location}</span>
          </p>
        )}
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
        {myVote && <p className="text-sm text-muted-foreground">Vote sent. Waiting for others.</p>}
      </div>
    )
  }

  const result = gameState.result
  if (phase === 'ended' && result) {
    const votedOutName = result.votedOutPeerId ? playerNames[result.votedOutPeerId] : 'No one'
    const spyName = playerNames[result.spyPeerId]
    return (
      <div className="p-6 max-w-md mx-auto space-y-4">
        <h3 className="font-semibold">Game over</h3>
        <p>Spy was: {spyName ?? result.spyPeerId}</p>
        <p>Voted out: {votedOutName}</p>
        <p className="font-medium">{result.win === 'innocents' ? 'Innocents win!' : 'Spy wins!'}</p>
      </div>
    )
  }

  return null
}
