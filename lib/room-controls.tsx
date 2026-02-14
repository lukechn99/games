"use client"

import { Button } from "@/components/ui/button"
import { useConnections } from "./connections-provider";
import { useState, useEffect } from 'react';
import { Input } from '@/components/ui/input';
import Lobby from "./lobby";
import { loadGameSession, clearGameSession, type GameSession } from './local-storage';

export default function RoomControls() {
  const { handleCreateRoom, handleJoinRoom, room } = useConnections()
  const [roomToJoin, setRoomToJoin] = useState('');
  const [playerName, setPlayerName] = useState('');
  const [showRoomInput, setShowRoomInput] = useState<"createOrJoin" | "create" | "join">("createOrJoin")
  const [savedSession, setSavedSession] = useState<GameSession | null>(null)
  const [rejoining, setRejoining] = useState(false)

  // Check localStorage for a previous session
  useEffect(() => {
    const session = loadGameSession()
    if (session) {
      setSavedSession(session)
    }
  }, [])

  const createRoom = async () => {
    if (!playerName.trim()) {
      alert('Please enter your name')
      return
    }
    const roomCode = await handleCreateRoom(playerName.trim())
    if (roomCode) alert(`You've created a room ${roomCode}`)
  }

  const joinRoom = async () => {
    if (!playerName.trim()) {
      alert('Please enter your name')
      return
    }
    if (!roomToJoin.trim()) {
      alert('Please enter a room code')
      return
    }
    await handleJoinRoom(roomToJoin.trim().toUpperCase(), playerName.trim())
  }

  const rejoinGame = async () => {
    if (!savedSession) return
    setRejoining(true)
    try {
      await handleJoinRoom(savedSession.roomCode, savedSession.playerName)
    } catch {
      // Room may no longer exist
      clearGameSession()
      setSavedSession(null)
    } finally {
      setRejoining(false)
    }
  }

  const dismissSavedSession = () => {
    clearGameSession()
    setSavedSession(null)
  }

  const createOrJoin = <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 items-center">
    <Button className="w-full" onClick={() => setShowRoomInput("create")}>
      Create a room
    </Button>
    <Button className="w-full" variant="outline" onClick={() => setShowRoomInput("join")}>
      Join a room
    </Button>
  </div>

  const joinRoomInput = <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 items-center">
    <Input
      placeholder="Enter player name..."
      value={playerName}
      onChange={(event) => setPlayerName(event.currentTarget.value)}
    />
    <Input
      placeholder="Enter room code..."
      value={roomToJoin}
      onChange={(event) => setRoomToJoin(event.currentTarget.value.toUpperCase())}
    />
    <Button className="w-full" variant="outline" onClick={joinRoom}>
      Join
    </Button>
  </div>

  const createRoomInput = <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 items-center">
    <Input
      placeholder="Enter player name..."
      value={playerName}
      onChange={(event) => setPlayerName(event.currentTarget.value)}
    />
    <Button className="w-full" variant="outline" onClick={createRoom}>
      Create Room
    </Button>
  </div>

  // Show lobby if user is in a room
  if (room) {
    return (
      <div className="min-h-screen flex items-center justify-center px-4">
        <Lobby />
      </div>
    )
  }

  return (
    <div className="min-h-screen flex items-center justify-center px-4">
      <div className="w-full max-w-lg space-y-6">
        {/* Rejoin prompt */}
        {savedSession && !room && (
          <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-5 space-y-4">
            <div className="text-center space-y-1">
              <h2 className="text-lg font-semibold text-gray-900 dark:text-white">
                Welcome back, {savedSession.playerName}!
              </h2>
              <p className="text-sm text-gray-500 dark:text-gray-400">
                You were in room <span className="font-mono font-bold tracking-wider">{savedSession.roomCode}</span>
              </p>
            </div>
            <div className="flex gap-3">
              <Button
                className="flex-1"
                onClick={rejoinGame}
                disabled={rejoining}
              >
                {rejoining ? 'Rejoining...' : 'Rejoin Game'}
              </Button>
              <Button
                variant="outline"
                className="flex-1"
                onClick={dismissSavedSession}
              >
                Start Fresh
              </Button>
            </div>
          </div>
        )}

        {/* Normal create/join UI */}
        {!savedSession && (
          showRoomInput === "join" ? joinRoomInput : (showRoomInput === "create" ? createRoomInput : createOrJoin)
        )}
        {savedSession && (
          <div className="text-center">
            <button
              type="button"
              className="text-sm text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 underline"
              onClick={dismissSavedSession}
            >
              Or create/join a different room
            </button>
          </div>
        )}
      </div>
    </div>
  )
}
