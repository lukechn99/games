'use client'

import { createContext, useContext, useState, useEffect, useRef, useCallback } from 'react'
import { createClient } from '@/utils/supabase/client'
import { notifications } from '@mantine/notifications'
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
    const [supabase] = useState(() => createClient())

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
    const peerConnectionsRef = useRef(peerConnections)
    const roomRef = useRef<Room | null>(room)
    const myPeerIdRef = useRef<string | null>(myPeerId)

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
                const localPeerId = myPeerIdRef.current
                if (!localPeerId) {
                    console.warn('Skipping ICE candidate update: peer id not set yet')
                    return
                }
                updatePeerConnections({
                    [localPeerId]: {
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
        const currentRoom = roomRef.current ?? room
        const roomCode = options?.roomCode ?? currentRoom?.room_code
        if (!roomCode) return null

        const currentConnections = options?.currentConnections ?? currentRoom?.peer_connections ?? {}
        const newConnections = mergePeerConnections(currentConnections, updates)

        const { error } = await supabase
            .from('rooms')
            .update({ peer_connections: newConnections })
            .eq('room_code', roomCode)

        if (error) {
            console.error('Error updating peer connections:', error)
            return null
        }

        if (currentRoom?.room_code === roomCode) {
            setRoom((prev) => (prev ? { ...prev, peer_connections: newConnections } : prev))
            roomRef.current = currentRoom ? { ...currentRoom, peer_connections: newConnections } : currentRoom
        }

        return newConnections
    }

    const handleSignalingUpdate = async (updatedRoom: any) => {
        const previousConnections = roomRef.current?.peer_connections || {}
        const incomingConnections = updatedRoom.peer_connections || {}
        const previousPeerIds = new Set(Object.keys(previousConnections))
        const localPeerId = myPeerIdRef.current

        for (const [peerId, peerData] of Object.entries(incomingConnections)) {
            if (peerId === localPeerId) continue
            if (!previousPeerIds.has(peerId)) {
                const playerName = (peerData as any)?.playerName || 'New player'
                notifications.show({
                    title: 'Player joined',
                    message: `${playerName} joined the room`,
                    color: 'green',
                })
            }
        }

        // Update room state to reflect latest peer_connections
        setRoom((prev) => (prev ? { ...prev, peer_connections: updatedRoom.peer_connections } : prev))
        roomRef.current = {
            ...(roomRef.current ?? {}),
            ...updatedRoom,
            peer_connections: updatedRoom.peer_connections,
        }

        if (!updatedRoom.peer_connections || !localPeerId) return

        const connections = updatedRoom.peer_connections

        // Handle offers directed at me
        for (const [peerId, peerData] of Object.entries(connections)) {
            if (peerId === localPeerId) continue

            const data = peerData as any

            // Check if there's an offer for me
            if (data.offers?.[localPeerId]) {
                let pc = peerConnections.get(peerId)
                if (!pc) {
                    console.log("Creating peer connection for", peerId)
                    pc = createPeerConnection(peerId)
                    setPeerConnections(prev => new Map(prev.set(peerId, pc!)))
                }

                const offer = JSON.parse(data.offers[localPeerId])
                await pc.setRemoteDescription(new RTCSessionDescription(offer))
                const answer = await pc.createAnswer()
                await pc.setLocalDescription(answer)

                // Send answer back
                await updatePeerConnections({
                    [localPeerId]: {
                        answers: {
                            [peerId]: JSON.stringify(answer)
                        }
                    }
                }, { currentConnections: updatedRoom.peer_connections })
            }

            // Check if there's an answer from someone I offered to
            if (data.answers?.[localPeerId]) {
                const pc = peerConnections.get(peerId)
                if (pc) {
                    const answer = JSON.parse(data.answers[localPeerId])
                    await pc.setRemoteDescription(new RTCSessionDescription(answer))
                }
            }

            // Handle ICE candidates
            if (data.iceCandidates?.[localPeerId]) {
                const pc = peerConnections.get(peerId)
                if (pc) {
                    for (const candidate of data.iceCandidates[localPeerId]) {
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
                        setRoom((prev) => (prev ? { ...prev, peer_connections: data.peer_connections } : (data as Room)))
                    }
                }
            })

        setChannel(roomChannel)
    }

    const handleCreateRoom = async (playerName: string) => {
        const roomCode = generateRoomCode()
        const peerId = crypto.randomUUID()

        setMyPeerId(peerId)
        myPeerIdRef.current = peerId

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

        const initialRoom = {
            room_code: roomCode,
            peer_connections: { [peerId]: { isHost: true, playerName: playerName } },
        }

        setRoom(initialRoom)
        roomRef.current = initialRoom

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
            myPeerIdRef.current = peerId

            // Create offers to all existing peers
            const existingConnections = data.peer_connections || {}
            const existingPeers = Object.keys(existingConnections)
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
            const updatedConnections = await updatePeerConnections(
                { [peerId]: { offers, playerName } },
                { roomCode: data.room_code, currentConnections: existingConnections }
            )

            if (updatedConnections) {
                const nextRoom = { ...data, peer_connections: updatedConnections } as Room
                setRoom(nextRoom)
                roomRef.current = nextRoom
            } else {
                const roomData = data as Room
                setRoom(roomData)
                roomRef.current = roomData
            }

            // Set up real-time subscription
            subscribeToRoom(roomCode)
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
        peerConnectionsRef.current = peerConnections
    }, [peerConnections])

    useEffect(() => {
        roomRef.current = room
    }, [room])

    useEffect(() => {
        myPeerIdRef.current = myPeerId
    }, [myPeerId])

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