"use client"

import { Button } from "@/components/ui/button"
import { useConnections } from "../lib/connections-provider";
import { useState } from 'react';
import { TextInput } from '@mantine/core';

export default function RoomControls() {
  const { handleCreateRoom, handleJoinRoom } = useConnections()
  const [roomToJoin, setRoomToJoin] = useState('');
  const [playerName, setPlayerName] = useState('');
  const [showJoinRoomInput, setShowJoinRoomInput] = useState(false)

  const createRoom = async () => {
    if (!playerName.trim()) {
      alert('Please enter your name')
      return
    }
    await handleCreateRoom(playerName.trim())
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
    console.log("Joining room", roomToJoin)
  }

  return (
    <div className="min-h-screen flex items-center justify-center px-4">
      <div className="w-full max-w-lg">
        <div className="mb-4">
          <TextInput
            placeholder="Enter your name"
            value={playerName}
            onChange={(event) => setPlayerName(event.currentTarget.value)}
          />
        </div>

        {!showJoinRoomInput ? (
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 items-center">
            <Button className="w-full" onClick={createRoom}>
              Create a room
            </Button>
            <Button className="w-full" variant="outline" onClick={() => setShowJoinRoomInput(true)}>
              Join a room
            </Button>
          </div>
        ) : (
          <div className="space-y-3">
            <TextInput
              placeholder="Enter room code"
              value={roomToJoin}
              onChange={(event) => setRoomToJoin(event.currentTarget.value.toUpperCase())}
              maxLength={6}
            />
            <div className="flex gap-2">
              <Button className="flex-1" onClick={joinRoom}>
                Join Room
              </Button>
              <Button className="flex-1" variant="outline" onClick={() => setShowJoinRoomInput(false)}>
                Back
              </Button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
