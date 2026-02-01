'use client'

import { createContext, useContext, useState, useEffect } from 'react'
import { createClient } from '@/utils/supabase/client'
import { createHash } from 'crypto'

const ConnectionsContext = createContext<{
    supabase: ReturnType<typeof createClient>
    handleCreateRoom: (playerName: string) => Promise<string | undefined>
    handleJoinRoom: (roomCode: string, playerName: string) => Promise<void>
    room: any
    peerConnections: Map<string, RTCPeerConnection>
    myPeerId: string | null
} | null>(null)

export function ConnectionsProvider({
    children,
}: {
    children: React.ReactNode
}) {
    const supabase = createClient()

    const [room, setRoom] = useState<any>(null)
    const [peerConnections, setPeerConnections] = useState<Map<string, RTCPeerConnection>>(new Map())
    const [myPeerId, setMyPeerId] = useState<string | null>(null)
    const [channel, setChannel] = useState<any>(null)
    const [iceCandidates, setIceCandidates] = useState<Map<string, RTCIceCandidate[]>>(new Map())

    const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

    function generateRoomCode(): string {
        const uuid = crypto.randomUUID()
        const hash = createHash('sha256').update(uuid).digest('hex');

        // 32 bits (8 hex chars) covers ~4.29 billion values, more than enough for 31^6 (~887m)
        let decimalValue = parseInt(hash.substring(0, 8), 16);

        let code = "";
        const base = ALPHABET.length;

        while (decimalValue > 0 && code.length < 6) {
            code = ALPHABET[decimalValue % base] + code;
            decimalValue = Math.floor(decimalValue / base);
        }

        return code.padStart(6, ALPHABET[0]).toUpperCase().slice(-6);
    }

    const createPeerConnection = (remotePeerId: string): RTCPeerConnection => {
        const pc = new RTCPeerConnection({
            iceServers: [
                { urls: 'stun:stun.l.google.com:19302' },
            ]
        })

        pc.onicecandidate = (event) => {
            if (event.candidate) {
                // Store ICE candidate locally and send to remote peer
                setIceCandidates(prev => {
                    const current = prev.get(remotePeerId) || []
                    const updated = new Map(prev)
                    updated.set(remotePeerId, [...current, event.candidate!])
                    return updated
                })

                // Send ICE candidate to remote peer via database
                updatePeerConnections({
                    [myPeerId!]: {
                        iceCandidates: {
                            [remotePeerId]: [event.candidate]
                        }
                    }
                })
            }
        }

        pc.onconnectionstatechange = () => {
            console.log(`Connection to ${remotePeerId}:`, pc.connectionState)
        }

        pc.ondatachannel = (event) => {
            console.log(`Data channel from ${remotePeerId}:`, event.channel)
            // Handle incoming data channels for game communication
        }

        return pc
    }

    const updatePeerConnections = async (updates: any) => {
        if (!room?.room_code) return

        const currentConnections = room.peer_connections || {}
        const newConnections = { ...currentConnections, ...updates }

        const { error } = await supabase
            .from('rooms')
            .update({ peer_connections: newConnections })
            .eq('room_code', room.room_code)

        if (error) console.error('Error updating peer connections:', error)
    }

    const handleSignalingUpdate = async (updatedRoom: any) => {
        if (!updatedRoom.peer_connections || !myPeerId) return

        const connections = updatedRoom.peer_connections
        const myData = connections[myPeerId]

        // Handle offers directed at me
        for (const [peerId, peerData] of Object.entries(connections)) {
            if (peerId === myPeerId) continue

            const data = peerData as any

            // Check if there's an offer for me
            if (data.offers?.[myPeerId]) {
                let pc = peerConnections.get(peerId)
                if (!pc) {
                    console.log("Creating peer connection for", peerId)
                    pc = createPeerConnection(peerId)
                    setPeerConnections(prev => new Map(prev.set(peerId, pc!)))
                }

                const offer = JSON.parse(data.offers[myPeerId])
                await pc.setRemoteDescription(new RTCSessionDescription(offer))
                const answer = await pc.createAnswer()
                await pc.setLocalDescription(answer)

                // Send answer back
                await updatePeerConnections({
                    [myPeerId]: {
                        answers: {
                            [peerId]: JSON.stringify(answer)
                        }
                    }
                })
            }

            // Check if there's an answer from someone I offered to
            if (data.answers?.[myPeerId]) {
                const pc = peerConnections.get(peerId)
                if (pc) {
                    const answer = JSON.parse(data.answers[myPeerId])
                    await pc.setRemoteDescription(new RTCSessionDescription(answer))
                }
            }

            // Handle ICE candidates
            if (data.iceCandidates?.[myPeerId]) {
                const pc = peerConnections.get(peerId)
                if (pc) {
                    for (const candidate of data.iceCandidates[myPeerId]) {
                        await pc.addIceCandidate(new RTCIceCandidate(candidate))
                    }
                }
            }
        }
    }

    const handleCreateRoom = async (playerName: string) => {
        const roomCode = generateRoomCode()
        const peerId = crypto.randomUUID()

        setMyPeerId(peerId)

        const { error } = await supabase
            .from('rooms')
            .insert({ 
                room_code: roomCode, 
                status: 'open',
                peer_connections: { [peerId]: { isHost: true, playerName: playerName } }
            })

        // TODO: we should actually check the database with each generated code before trying to insert
        if (error) {
            console.error('Error creating room:', error)
            if (error.code === '23505') {
                return handleCreateRoom(playerName) // Retry with new code
            }
            return
        }

        setRoom({ room_code: roomCode, peer_connections: { [peerId]: { isHost: true, playerName: playerName } } })

        // Set up real-time subscription
        const roomChannel = supabase
            .channel(`room-${roomCode}`)
            .on('postgres_changes', { 
                event: 'UPDATE', 
                schema: 'public', 
                table: 'rooms',
                filter: `room_code=eq.${roomCode}`
            }, (payload) => {
                handleSignalingUpdate(payload.new)
            })
            .subscribe()

        setChannel(roomChannel)

        return roomCode
    }

    const handleJoinRoom = async (roomCode: string, playerName: string) => {
        const { data, error } = await supabase
            .from('rooms')
            .select('room_code, peer_connections')
            .eq('room_code', roomCode)
            .maybeSingle()

        if (error) {
            console.error(error)
            return
        }

        if (data) {
            const peerId = crypto.randomUUID()
            setMyPeerId(peerId)

            setRoom(data)

            // Create offers to all existing peers
            const existingPeers = Object.keys(data.peer_connections || {})
            const offers: any = {}

            for (const existingPeerId of existingPeers) {
                const pc = createPeerConnection(existingPeerId)
                setPeerConnections(prev => new Map(prev.set(existingPeerId, pc)))

                const offer = await pc.createOffer()
                await pc.setLocalDescription(offer)
                offers[existingPeerId] = JSON.stringify(offer)
            }

            // Store my offers
            await updatePeerConnections({
                [peerId]: { offers, playerName }
            })

            // Set up real-time subscription
            const roomChannel = supabase
                .channel(`room-${roomCode}`)
                .on('postgres_changes', { 
                    event: 'UPDATE', 
                    schema: 'public', 
                    table: 'rooms',
                    filter: `room_code=eq.${roomCode}`
                }, (payload) => {
                    handleSignalingUpdate(payload.new)
                })
                .subscribe()

            setChannel(roomChannel)
        }
    }

    // Cleanup on unmount
    useEffect(() => {
        return () => {
            if (channel) {
                supabase.removeChannel(channel)
            }
            peerConnections.forEach(pc => pc.close())
        }
    }, [channel, peerConnections])

    return (
        <ConnectionsContext.Provider value={{ 
            supabase, 
            handleCreateRoom, 
            handleJoinRoom, 
            room, 
            peerConnections,
            myPeerId 
        }}>
            {children}
        </ConnectionsContext.Provider>
    )
}

export function useConnections() {
    const context = useContext(ConnectionsContext)
    if (!context) {
        throw new Error('useConnections must be used within ConnectionsProvider')
    }
    return context
}