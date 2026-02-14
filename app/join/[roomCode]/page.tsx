'use client'

import { use, useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { useConnections } from '@/lib/connections-provider'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'

export default function JoinRoomPage({
  params,
}: {
  params: Promise<{ roomCode: string }>
}) {
  const { roomCode } = use(params)
  const router = useRouter()
  const { handleJoinRoom, room } = useConnections()
  const [playerName, setPlayerName] = useState('')
  const [joining, setJoining] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // If already in the room, redirect to home
  useEffect(() => {
    if (room) {
      router.replace('/')
    }
  }, [room, router])

  if (room) {
    return null
  }

  const onJoin = async () => {
    if (!playerName.trim()) {
      setError('Please enter your name')
      return
    }
    setError(null)
    setJoining(true)
    try {
      await handleJoinRoom(roomCode.toUpperCase(), playerName.trim())
      // The connections-provider saves to localStorage automatically.
      // The useEffect above will redirect once room state is set.
    } catch {
      setError('Failed to join room. Please check the room code and try again.')
      setJoining(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center px-4">
      <div className="w-full max-w-sm">
        <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6 space-y-6">
          {/* Header */}
          <div className="text-center space-y-2">
            <h1 className="text-2xl font-bold text-gray-900 dark:text-white">
              Join Room
            </h1>
            <div className="inline-block px-4 py-2 bg-gray-100 dark:bg-gray-700 rounded-lg">
              <span className="text-sm text-gray-500 dark:text-gray-400 uppercase tracking-wide">
                Room Code
              </span>
              <p className="text-2xl font-bold tracking-widest text-gray-900 dark:text-white">
                {roomCode.toUpperCase()}
              </p>
            </div>
          </div>

          {/* Name input */}
          <div className="space-y-3">
            <Input
              placeholder="Enter your name..."
              value={playerName}
              onChange={(e) => setPlayerName(e.currentTarget.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') onJoin()
              }}
              autoFocus
            />
            {error && (
              <p className="text-sm text-red-600 dark:text-red-400">{error}</p>
            )}
            <Button
              className="w-full"
              onClick={onJoin}
              disabled={joining}
            >
              {joining ? 'Joining...' : 'Join Game'}
            </Button>
          </div>
        </div>
      </div>
    </div>
  )
}
