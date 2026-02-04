'use client'

import { createContext, useContext, useState, useEffect, useRef, useCallback } from 'react'
import { createClient } from '@/utils/supabase/client'
import { Room } from './room'

export type GameMessageHandler = (fromPeerId: string, msg: unknown) => void

const ConnectionsContext = createContext<{
    supabase: ReturnType<typeof createClient>
    handleCreateRoom: (playerName: string) => Promise<string | undefined>
    handleJoinRoom: (roomCode: string, playerName: string) => Promise<void>
    room: Room | null
    peerConnections: Map<string, RTCPeerConnection>
    myPeerId: string | null
    dataChannels: Map<string, RTCDataChannel>
    sendGameMessage: (peerId: string, msg: object) => void
    broadcastGameMessage: (msg: object) => void
    setGameMessageHandler: (handler: GameMessageHandler | null) => void
} | null>(null)

export function ConnectionsProvider({
    children,
}: {
    children: React.ReactNode
}) {
    const supabase = createClient()

    const [room, setRoom] = useState<Room | null>(null)
    const [peerConnections, setPeerConnections] = useState<Map<string, RTCPeerConnection>>(new Map())
    const [dataChannels, setDataChannels] = useState<Map<string, RTCDataChannel>>(new Map())
    const [myPeerId, setMyPeerId] = useState<string | null>(null)
    const [channel, setChannel] = useState<any>(null)
    const [iceCandidates, setIceCandidates] = useState<Map<string, RTCIceCandidate[]>>(new Map())
    const gameMessageHandlerRef = useRef<GameMessageHandler | null>(null)
    const setGameMessageHandler = useCallback((handler: GameMessageHandler | null) => {
        gameMessageHandlerRef.current = handler
    }, [])

    const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

    function generateRoomCode(): string {
        const bytes = new Uint8Array(4)
        crypto.getRandomValues(bytes)
        let decimalValue = (bytes[0]! << 24) | (bytes[1]! << 16) | (bytes[2]! << 8) | bytes[3]!
        decimalValue = Math.abs(decimalValue)
        let code = ''
        const base = ALPHABET.length
        while (decimalValue > 0 && code.length < 6) {
            code = ALPHABET[decimalValue % base] + code
            decimalValue = Math.floor(decimalValue / base)
        }
        return code.padStart(6, ALPHABET[0]).toUpperCase().slice(-6)
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
            const dc = event.channel
            dc.onmessage = (e) => {
                try {
                    const msg = JSON.parse(e.data as string)
                    gameMessageHandlerRef.current?.(remotePeerId, msg)
                } catch {
                    gameMessageHandlerRef.current?.(remotePeerId, e.data)
                }
            }
            dc.onopen = () => {
                setDataChannels((prev) => new Map(prev).set(remotePeerId, dc))
            }
            if (dc.readyState === 'open') {
                setDataChannels((prev) => new Map(prev).set(remotePeerId, dc))
            }
        }

        return pc
    }

    const setupDataChannel = (pc: RTCPeerConnection, remotePeerId: string) => {
        const dc = pc.createDataChannel('game', { ordered: true })
        dc.onmessage = (e) => {
            try {
                const msg = JSON.parse(e.data as string)
                gameMessageHandlerRef.current?.(remotePeerId, msg)
            } catch {
                gameMessageHandlerRef.current?.(remotePeerId, e.data)
            }
        }
        dc.onopen = () => {
            setDataChannels((prev) => new Map(prev).set(remotePeerId, dc))
        }
        if (dc.readyState === 'open') {
            setDataChannels((prev) => new Map(prev).set(remotePeerId, dc))
        }
        return dc
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
                    alert(`Peer has joined ${peerId}`)
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
                setRoom((prev) => (prev ? { ...prev, ...payload.new } as Room : payload.new as Room))
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
            setRoom(data as Room)

            // Create offers to all existing peers
            const existingPeers = Object.keys(data.peer_connections || {})
            const offers: any = {}

            for (const existingPeerId of existingPeers) {
                const pc = createPeerConnection(existingPeerId)
                setupDataChannel(pc, existingPeerId)
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
                    setRoom((prev) => (prev ? { ...prev, ...payload.new } as Room : payload.new as Room))
                    handleSignalingUpdate(payload.new)
                })
                .subscribe()

            setChannel(roomChannel)
        }
    }

    const sendGameMessage = useCallback((peerId: string, msg: object) => {
        const dc = dataChannels.get(peerId)
        if (dc?.readyState === 'open') {
            dc.send(JSON.stringify(msg))
        }
    }, [dataChannels])

    const broadcastGameMessage = useCallback((msg: object) => {
        const payload = JSON.stringify(msg)
        dataChannels.forEach((dc) => {
            if (dc.readyState === 'open') dc.send(payload)
        })
    }, [dataChannels])

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
            myPeerId,
            dataChannels,
            sendGameMessage,
            broadcastGameMessage,
            setGameMessageHandler,
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