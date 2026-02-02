'use client'

import { createContext, useContext, useState, useEffect, useRef } from 'react'
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
    const [supabase] = useState(() => createClient())

    const [room, setRoom] = useState<any>(null)
    const [peerConnections, setPeerConnections] = useState<Map<string, RTCPeerConnection>>(new Map())
    const [myPeerId, setMyPeerId] = useState<string | null>(null)
    const [channel, setChannel] = useState<any>(null)
    const [iceCandidates, setIceCandidates] = useState<Map<string, RTCIceCandidate[]>>(new Map())
    const peerConnectionsRef = useRef(peerConnections)

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

    const mergeNestedRecords = (current?: Record<string, any>, incoming?: Record<string, any>) => {
        if (!current) return incoming
        if (!incoming) return current
        return { ...current, ...incoming }
    }

    const mergeIceCandidates = (current?: Record<string, any>, incoming?: Record<string, any>) => {
        if (!current) return incoming
        if (!incoming) return current

        const merged = { ...current }
        for (const [peerId, candidates] of Object.entries(incoming)) {
            const existing = merged[peerId] || []
            merged[peerId] = [...existing, ...(candidates as any[])]
        }
        return merged
    }

    const mergePeerConnections = (current: Record<string, any>, updates: Record<string, any>) => {
        const merged = { ...current }
        for (const [peerId, update] of Object.entries(updates || {})) {
            const currentData = current[peerId] || {}
            const updateData = update as Record<string, any>
            const offers = mergeNestedRecords(currentData.offers, updateData.offers)
            const answers = mergeNestedRecords(currentData.answers, updateData.answers)
            const iceCandidates = mergeIceCandidates(currentData.iceCandidates, updateData.iceCandidates)

            merged[peerId] = {
                ...currentData,
                ...updateData,
                ...(offers ? { offers } : {}),
                ...(answers ? { answers } : {}),
                ...(iceCandidates ? { iceCandidates } : {}),
            }
        }
        return merged
    }

    const updatePeerConnections = async (
        updates: Record<string, any>,
        options?: { roomCode?: string; currentConnections?: Record<string, any> }
    ) => {
        const roomCode = options?.roomCode ?? room?.room_code
        if (!roomCode) return null

        const currentConnections = options?.currentConnections ?? room?.peer_connections ?? {}
        const newConnections = mergePeerConnections(currentConnections, updates)

        const { error } = await supabase
            .from('rooms')
            .update({ peer_connections: newConnections })
            .eq('room_code', roomCode)

        if (error) {
            console.error('Error updating peer connections:', error)
            return null
        }

        if (room?.room_code === roomCode) {
            setRoom((prev: any) => (prev ? { ...prev, peer_connections: newConnections } : prev))
        }

        return newConnections
    }

    const handleSignalingUpdate = async (updatedRoom: any) => {
        // Update room state to reflect latest peer_connections
        setRoom((prev: any) => ({
            ...prev,
            peer_connections: updatedRoom.peer_connections
        }))

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

    const subscribeToRoom = (roomCode: string) => {
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
            .subscribe(async (status) => {
                if (status === 'SUBSCRIBED') {
                    const { data, error } = await supabase
                        .from('rooms')
                        .select('room_code, peer_connections')
                        .eq('room_code', roomCode)
                        .maybeSingle()

                    if (error) {
                        console.error('Error fetching latest room state:', error)
                        return
                    }

                    if (data) {
                        setRoom((prev: any) => (prev ? { ...prev, peer_connections: data.peer_connections } : data))
                    }
                }
            })

        setChannel(roomChannel)
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
        subscribeToRoom(roomCode)

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

            // Create offers to all existing peers
            const existingConnections = data.peer_connections || {}
            const existingPeers = Object.keys(existingConnections)
            const offers: any = {}

            for (const existingPeerId of existingPeers) {
                const pc = createPeerConnection(existingPeerId)
                setPeerConnections(prev => new Map(prev.set(existingPeerId, pc)))

                const offer = await pc.createOffer()
                await pc.setLocalDescription(offer)
                offers[existingPeerId] = JSON.stringify(offer)
            }

            // Store my offers
            const updatedConnections = await updatePeerConnections(
                { [peerId]: { offers, playerName } },
                { roomCode: data.room_code, currentConnections: existingConnections }
            )

            if (updatedConnections) {
                setRoom({ ...data, peer_connections: updatedConnections })
            } else {
                setRoom(data)
            }

            // Set up real-time subscription
            subscribeToRoom(roomCode)
        }
    }

    // Cleanup on unmount
    useEffect(() => {
        peerConnectionsRef.current = peerConnections
    }, [peerConnections])

    useEffect(() => {
        return () => {
            if (channel) {
                supabase.removeChannel(channel)
            }
            peerConnectionsRef.current.forEach(pc => pc.close())
        }
    }, [channel, supabase])

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