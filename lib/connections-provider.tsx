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
                console.log(`[ice] Local ICE candidate generated for ${remotePeerId}:`, event.candidate.type, event.candidate.address)
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
                    console.warn('[ice] Skipping ICE candidate update: peer id not set yet')
                    return
                }
                updatePeerConnections({
                    [localPeerId]: {
                        iceCandidates: {
                            [remotePeerId]: [event.candidate]
                        }
                    }
                })
            } else {
                console.log(`[ice] ICE gathering complete for ${remotePeerId}`)
            }
        }

        pc.oniceconnectionstatechange = () => {
            console.log(`[ice] ICE connection state for ${remotePeerId}: ${pc.iceConnectionState}`)
        }

        pc.onconnectionstatechange = () => {
            console.log(`[rtc] Connection state for ${remotePeerId}: ${pc.connectionState}`)
        }

        pc.onsignalingstatechange = () => {
            console.log(`[rtc] Signaling state for ${remotePeerId}: ${pc.signalingState}`)
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
        if (!roomCode) {
            console.warn('[updatePC] No room code available, skipping update')
            return null
        }

        const currentConnections = options?.currentConnections ?? currentRoom?.peer_connections ?? {}
        const newConnections = mergePeerConnections(currentConnections, updates)

        console.log('[updatePC] Writing to DB:', {
            roomCode,
            updateKeys: Object.keys(updates),
            resultingPeerIds: Object.keys(newConnections),
        })

        const { error } = await supabase
            .from('rooms')
            .update({ peer_connections: newConnections })
            .eq('room_code', roomCode)

        if (error) {
            console.error('[updatePC] Error updating peer connections:', error)
            return null
        }

        console.log('[updatePC] DB write successful')

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

        console.log('[signaling] handleSignalingUpdate entered', {
            localPeerId,
            previousPeerIds: [...previousPeerIds],
            incomingPeerIds: Object.keys(incomingConnections),
            roomRefExists: !!roomRef.current,
        })

        for (const [peerId, peerData] of Object.entries(incomingConnections)) {
            if (peerId === localPeerId) continue
            if (!previousPeerIds.has(peerId)) {
                const playerName = (peerData as any)?.playerName || 'New player'
                console.log(`[signaling] New peer detected: ${peerId} (${playerName})`)
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

        if (!updatedRoom.peer_connections || !localPeerId) {
            console.warn('[signaling] Early return — missing peer_connections or localPeerId', {
                hasPeerConnections: !!updatedRoom.peer_connections,
                localPeerId,
            })
            return
        }

        const connections = updatedRoom.peer_connections

        // Handle offers directed at me
        for (const [peerId, peerData] of Object.entries(connections)) {
            if (peerId === localPeerId) continue

            const data = peerData as any

            // Check if there's an offer for me
            if (data.offers?.[localPeerId]) {
                console.log(`[signaling] Found offer from ${peerId} directed at me (${localPeerId})`)
                let pc = peerConnections.get(peerId)
                const pcFromRef = peerConnectionsRef.current.get(peerId)
                console.log(`[signaling] PeerConnection lookup for ${peerId}:`, {
                    fromState: !!pc,
                    fromRef: !!pcFromRef,
                    stateSize: peerConnections.size,
                    refSize: peerConnectionsRef.current.size,
                })
                if (!pc) {
                    console.log(`[signaling] Creating new peer connection for ${peerId}`)
                    pc = createPeerConnection(peerId)
                    setPeerConnections(prev => new Map(prev.set(peerId, pc!)))
                }

                const offer = JSON.parse(data.offers[localPeerId])
                await pc.setRemoteDescription(new RTCSessionDescription(offer))
                const answer = await pc.createAnswer()
                await pc.setLocalDescription(answer)
                console.log(`[signaling] Created answer for ${peerId}, writing to DB...`)

                // Send answer back
                await updatePeerConnections({
                    [localPeerId]: {
                        answers: {
                            [peerId]: JSON.stringify(answer)
                        }
                    }
                }, { currentConnections: updatedRoom.peer_connections })
                console.log(`[signaling] Answer for ${peerId} written to DB`)
            }

            // Check if there's an answer from someone I offered to
            if (data.answers?.[localPeerId]) {
                console.log(`[signaling] Found answer from ${peerId} directed at me (${localPeerId})`)
                const pc = peerConnections.get(peerId)
                const pcFromRef = peerConnectionsRef.current.get(peerId)
                console.log(`[signaling] PeerConnection lookup for answer from ${peerId}:`, {
                    fromState: !!pc,
                    fromRef: !!pcFromRef,
                    stateSize: peerConnections.size,
                    refSize: peerConnectionsRef.current.size,
                })
                if (pc) {
                    const answer = JSON.parse(data.answers[localPeerId])
                    await pc.setRemoteDescription(new RTCSessionDescription(answer))
                    console.log(`[signaling] Set remote description (answer) from ${peerId}`)
                } else {
                    console.warn(`[signaling] No PeerConnection found for answer from ${peerId} — answer DROPPED`)
                }
            }

            // Handle ICE candidates
            if (data.iceCandidates?.[localPeerId]) {
                const pc = peerConnections.get(peerId)
                const pcFromRef = peerConnectionsRef.current.get(peerId)
                console.log(`[signaling] Found ICE candidates from ${peerId} directed at me:`, {
                    count: data.iceCandidates[localPeerId].length,
                    hasPc: !!pc,
                    hasPcFromRef: !!pcFromRef,
                })
                if (pc) {
                    for (const candidate of data.iceCandidates[localPeerId]) {
                        await pc.addIceCandidate(new RTCIceCandidate(candidate))
                    }
                    console.log(`[signaling] Added ${data.iceCandidates[localPeerId].length} ICE candidates from ${peerId}`)
                } else {
                    console.warn(`[signaling] No PeerConnection found for ICE candidates from ${peerId} — candidates DROPPED`)
                }
            }
        }
        console.log('[signaling] handleSignalingUpdate complete')
    }

    const subscribeToRoom = (roomCode: string) => {
        console.log(`[subscribe] Setting up Realtime subscription for room ${roomCode}`)
        const roomChannel = supabase
            .channel(`room-${roomCode}`)
            .on('postgres_changes', { 
                event: 'UPDATE', 
                schema: 'public', 
                table: 'rooms',
                filter: `room_code=eq.${roomCode}`
            }, (payload) => {
                console.log('[subscribe] Received postgres_changes UPDATE event:', {
                    peerIds: Object.keys(payload.new?.peer_connections || {}),
                    payloadKeys: Object.keys(payload.new || {}),
                })
                handleSignalingUpdate(payload.new)
            })
            .subscribe(async (status, err) => {
                console.log(`[subscribe] Subscription status changed: ${status}`, err ? { error: err } : '')
                if (status === 'SUBSCRIBED') {
                    console.log(`[subscribe] Successfully subscribed to room ${roomCode}, fetching latest state...`)
                    const { data, error } = await supabase
                        .from('rooms')
                        .select('room_code, peer_connections')
                        .eq('room_code', roomCode)
                        .maybeSingle()

                    if (error) {
                        console.error('[subscribe] Error fetching latest room state:', error)
                        return
                    }

                    if (data) {
                        console.log('[subscribe] Fetched latest room state:', {
                            peerIds: Object.keys(data.peer_connections || {}),
                        })
                        setRoom((prev) => (prev ? { ...prev, peer_connections: data.peer_connections } : (data as Room)))
                    } else {
                        console.warn('[subscribe] No room data found after subscribing')
                    }
                } else if (status === 'CHANNEL_ERROR') {
                    console.error(`[subscribe] Channel error for room ${roomCode}`)
                } else if (status === 'TIMED_OUT') {
                    console.error(`[subscribe] Subscription timed out for room ${roomCode}`)
                } else if (status === 'CLOSED') {
                    console.warn(`[subscribe] Channel closed for room ${roomCode}`)
                }
            })

        setChannel(roomChannel)
    }

    const handleCreateRoom = async (playerName: string) => {
        const roomCode = generateRoomCode()
        const peerId = crypto.randomUUID()

        console.log(`[create] Creating room ${roomCode} as "${playerName}", peerId: ${peerId}`)
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
            console.error('[create] Error creating room:', error)
            if (error.code === '23505') {
                console.log('[create] Room code collision, retrying...')
                return handleCreateRoom(playerName) // Retry with new code
            }
            return
        }

        console.log(`[create] Room ${roomCode} created successfully in DB`)

        const initialRoom = {
            room_code: roomCode,
            peer_connections: { [peerId]: { isHost: true, playerName: playerName } },
        }

        setRoom(initialRoom)
        roomRef.current = initialRoom

        // Set up real-time subscription
        console.log(`[create] Setting up Realtime subscription for room ${roomCode}...`)
        subscribeToRoom(roomCode)

        return roomCode
    }

    const handleJoinRoom = async (roomCode: string, playerName: string) => {
        console.log(`[join] Attempting to join room ${roomCode} as "${playerName}"`)
        const { data, error } = await supabase
            .from('rooms')
            .select('room_code, peer_connections')
            .eq('room_code', roomCode)
            .maybeSingle()

        if (error) {
            console.error('[join] Error fetching room:', error)
            return
        }

        if (!data) {
            console.error(`[join] Room ${roomCode} not found`)
            return
        }

        console.log('[join] Room found:', {
            roomCode: data.room_code,
            existingPeerIds: Object.keys(data.peer_connections || {}),
        })

        const peerId = crypto.randomUUID()
        console.log(`[join] Generated local peerId: ${peerId}`)
        setMyPeerId(peerId)
        myPeerIdRef.current = peerId

        // Create offers to all existing peers
        const existingConnections = data.peer_connections || {}
        const existingPeers = Object.keys(existingConnections)
        const offers: any = {}

        console.log(`[join] Creating offers to ${existingPeers.length} existing peers:`, existingPeers)
        for (const existingPeerId of existingPeers) {
            const pc = createPeerConnection(existingPeerId)
            setupDataChannel(pc, existingPeerId)
            setPeerConnections(prev => new Map(prev.set(existingPeerId, pc)))

            const offer = await pc.createOffer()
            await pc.setLocalDescription(offer)
            offers[existingPeerId] = JSON.stringify(offer)
            console.log(`[join] Created offer for peer ${existingPeerId}`)
        }

        // Store my offers
        console.log('[join] Writing offers to DB...')
        const updatedConnections = await updatePeerConnections(
            { [peerId]: { offers, playerName } },
            { roomCode: data.room_code, currentConnections: existingConnections }
        )

        if (updatedConnections) {
            console.log('[join] DB write successful, updated peer_connections:', {
                peerIds: Object.keys(updatedConnections),
            })
            const nextRoom = { ...data, peer_connections: updatedConnections } as Room
            setRoom(nextRoom)
            roomRef.current = nextRoom
        } else {
            console.error('[join] DB write returned null — updatePeerConnections failed')
            const roomData = data as Room
            setRoom(roomData)
            roomRef.current = roomData
        }

        // Set up real-time subscription
        console.log('[join] Setting up Realtime subscription...')
        subscribeToRoom(roomCode)
        console.log('[join] handleJoinRoom complete')
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