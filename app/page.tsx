import Image from "next/image";
import { Button } from "@/components/ui/button"

export default function Home() {

  const createRoom = () => {
    // TODO: implement
    console.log("Creating room")
  }

  const joinRoom = () => {
    // TODO: implement
    console.log("Joining room")
  }

  return <div>
    <Button onClick={createRoom}>Create a room</Button>
    <Button onClick={joinRoom}>Join a room</Button>
  </div>
}
