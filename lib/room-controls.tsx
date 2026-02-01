"use client"

import { Button } from "@/components/ui/button"
import { useConnections } from "./connections-provider";
import { useState } from 'react';
import { TextInput } from '@mantine/core';

export default function RoomControls() {
  const { handleCreateRoom, handleFetchRooms } = useConnections()
  const [roomToJoin, setRoomToJoin] = useState('');
  const [showJoinRoomInput, setShowJoinRoomInput] = useState(false)

  const createRoom = () => {
    handleCreateRoom()
  }

  const joinRoom = () => {
    handleFetchRooms(roomToJoin)
    console.log("Joining room", roomToJoin)
  }

  const joinOrCreate = <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 items-center">
    <Button className="w-full" onClick={createRoom}>
      Create a room
    </Button>
    <Button className="w-full" variant="outline" onClick={() => setShowJoinRoomInput(true)}>
      Join a room
    </Button>
  </div>

  const joinRoomInput = <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 items-center">
    <TextInput
      value={roomToJoin}
      onChange={(event) => setRoomToJoin(event.currentTarget.value)}
    />
    <Button className="w-full" variant="outline" onClick={joinRoom}>
      Join
    </Button>
  </div>

  return (
    <div className="min-h-screen flex items-center justify-center px-4">
      <div className="w-full max-w-lg">
        {showJoinRoomInput ? joinRoomInput : joinOrCreate}
      </div>
    </div>
  )
}
