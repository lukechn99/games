"use client"

import { Button } from "@/components/ui/button"

export default function RoomControls() {
  const createRoom = () => {
    // TODO: implement
    console.log("Creating room")
  }

  const joinRoom = () => {
    // TODO: implement
    console.log("Joining room")
  }

  return (
    <div className="min-h-screen flex items-center justify-center px-4">
      <div className="w-full max-w-lg">
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 items-center">
          <Button className="w-full" onClick={createRoom}>
            Create a room
          </Button>
          <Button className="w-full" variant="outline" onClick={joinRoom}>
            Join a room
          </Button>
        </div>
      </div>
    </div>
  )
}