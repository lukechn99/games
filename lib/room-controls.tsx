"use client"

import { Button } from "@/components/ui/button"
import { useConnections } from "./connections-provider";
import { useState } from 'react';
import { Input } from '@/components/ui/input';
import Lobby from "./lobby";

export default function RoomControls() {
  const { handleCreateRoom, handleJoinRoom, room } = useConnections()
  const [roomToJoin, setRoomToJoin] = useState('');
  const [playerName, setPlayerName] = useState('');
  const [showRoomInput, setShowRoomInput] = useState<"createOrJoin" | "create" | "join">("createOrJoin")

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
      <div className="w-full max-w-lg">
        {showRoomInput === "join" ? joinRoomInput : (showRoomInput === "create" ? createRoomInput : createOrJoin)}
      </div>
    </div>
  )
}
