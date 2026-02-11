'use client'

import { createContext, useContext, useState, useEffect, useRef, useCallback } from 'react'
import { createClient } from '@/utils/supabase/client'
import { notifications } from '@mantine/notifications'
import { Room } from './room'
import type { RealtimeChannel } from '@supabase/supabase-js'

export type GameMessageHandler = (fromPeerId: string, msg: unknown) => void

// Broadcast message types for WebRTC signaling
type SignalMessage =
    | { type: 'offer'; from: string; to: string; sdp: string }
    | { type: 'answer'; from: string; to: string; sdp: string }
    | { type: 'ice-candidate'; from: string; to: string; candidate: RTCIceCandidateInit }

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
    const [channel, setChannel] = useState<RealtimeChannel | null>(null)
    const gameMessageHandlerRef = useRef<GameMessageHandler | null>(null)
    const setGameMessageHandler = useCallback((handler: GameMessageHandler | null) => {
        gameMessageHandlerRef.current = handler
    }, [])
    const peerConnectionsRef = useRef(peerConnections)
    const roomRef = useRef<Room | null>(room)
    const myPeerIdRef = useRef<string | null>(myPeerId)
    const channelRef = useRef<RealtimeChannel | null>(null)

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

    // Send a signaling message via Supabase Broadcast
    const sendSignal = (msg: SignalMessage) => {
        const ch = channelRef.current
        if (!ch) {
            console.warn('[signal] Cannot send signal — channel not ready')
            return
        }
        ch.send({
            type: 'broadcast',
            event: 'signal',
            payload: msg,
        })
    }

    const createPeerConnection = (remotePeerId: string): RTCPeerConnection => {
        const pc = new RTCPeerConnection({
            iceServers: [
                { urls: 'stun:stun.l.google.com:19302' },
            ]
        })

        pc.onicecandidate = (event) => {
            if (event.candidate) {
                const localPeerId = myPeerIdRef.current
                if (!localPeerId) {
                    console.warn('[ice] Skipping ICE candidate: peer id not set yet')
                    return
                }
                sendSignal({
                    type: 'ice-candidate',
                    from: localPeerId,
                    to: remotePeerId,
                    candidate: event.candidate.toJSON(),
                })
            }
        }

        pc.onconnectionstatechange = () => {
            console.log(`[rtc] Connection state for ${remotePeerId}: ${pc.connectionState}`)
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

    // Handle incoming signaling messages from Broadcast
    const handleSignalMessage = async (msg: SignalMessage) => {
        const localPeerId = myPeerIdRef.current
        if (!localPeerId) return

        // Ignore messages not addressed to us
        if (msg.to !== localPeerId) return

        if (msg.type === 'offer') {
            console.log(`[signal] Received offer from ${msg.from}`)

            // Create a new peer connection for the offerer
            const pc = createPeerConnection(msg.from)
            peerConnectionsRef.current = new Map(peerConnectionsRef.current).set(msg.from, pc)
            setPeerConnections(prev => new Map(prev).set(msg.from, pc))

            const offer = JSON.parse(msg.sdp)
            await pc.setRemoteDescription(new RTCSessionDescription(offer))
            const answer = await pc.createAnswer()
            await pc.setLocalDescription(answer)

            console.log(`[signal] Sending answer to ${msg.from}`)
            sendSignal({
                type: 'answer',
                from: localPeerId,
                to: msg.from,
                sdp: JSON.stringify(answer),
            })
        } else if (msg.type === 'answer') {
            console.log(`[signal] Received answer from ${msg.from}`)
            const pc = peerConnectionsRef.current.get(msg.from)
            if (pc) {
                const answer = JSON.parse(msg.sdp)
                await pc.setRemoteDescription(new RTCSessionDescription(answer))
                console.log(`[signal] Set remote description (answer) from ${msg.from}`)
            } else {
                console.warn(`[signal] No PeerConnection for answer from ${msg.from} — DROPPED`)
            }
        } else if (msg.type === 'ice-candidate') {
            const pc = peerConnectionsRef.current.get(msg.from)
            if (pc) {
                await pc.addIceCandidate(new RTCIceCandidate(msg.candidate))
            } else {
                console.warn(`[signal] No PeerConnection for ICE candidate from ${msg.from} — DROPPED`)
            }
        }
    }

    // Update just the player list in the DB (no signaling data)
    const updatePlayerList = async (
        roomCode: string,
        peerId: string,
        playerInfo: { playerName: string; isHost?: boolean }
    ) => {
        // Fetch current player list, merge, and write back
        const { data, error: fetchError } = await supabase
            .from('rooms')
            .select('peer_connections')
            .eq('room_code', roomCode)
            .maybeSingle()

        if (fetchError || !data) {
            console.error('[playerList] Error fetching room for player list update:', fetchError)
            return null
        }

        const current = data.peer_connections || {}
        const updated = { ...current, [peerId]: playerInfo }

        const { error } = await supabase
            .from('rooms')
            .update({ peer_connections: updated })
            .eq('room_code', roomCode)

        if (error) {
            console.error('[playerList] Error updating player list:', error)
            return null
        }

        return updated
    }

    const subscribeToRoom = (roomCode: string) => {
        console.log(`[subscribe] Setting up channel for room ${roomCode}`)
        const roomChannel = supabase
            .channel(`room-${roomCode}`, { config: { broadcast: { self: false } } })
            // Listen for signaling messages via Broadcast
            .on('broadcast', { event: 'signal' }, (payload) => {
                handleSignalMessage(payload.payload as SignalMessage)
            })
            // Listen for player list changes via Postgres Changes
            .on('postgres_changes', {
                event: 'UPDATE',
                schema: 'public',
                table: 'rooms',
                filter: `room_code=eq.${roomCode}`
            }, (payload) => {
                const updatedRoom = payload.new
                const previousConnections = roomRef.current?.peer_connections || {}
                const incomingConnections = updatedRoom.peer_connections || {}
                const previousPeerIds = new Set(Object.keys(previousConnections))
                const localPeerId = myPeerIdRef.current

                // Detect new players for notifications
                for (const [peerId, peerData] of Object.entries(incomingConnections)) {
                    if (peerId === localPeerId) continue
                    if (!previousPeerIds.has(peerId)) {
                        const playerName = (peerData as Record<string, unknown>)?.playerName as string || 'New player'
                        notifications.show({
                            title: 'Player joined',
                            message: `${playerName} joined the room`,
                            color: 'green',
                        })
                    }
                }

                // Update room state (player list only)
                setRoom((prev) => (prev ? { ...prev, peer_connections: incomingConnections } : prev))
                roomRef.current = {
                    ...(roomRef.current ?? { room_code: roomCode }),
                    peer_connections: incomingConnections,
                } as Room
            })
            .subscribe(async (status, err) => {
                console.log(`[subscribe] Status: ${status}`, err ? { error: err } : '')
                if (status === 'SUBSCRIBED') {
                    console.log(`[subscribe] Subscribed to room ${roomCode}`)
                    // Fetch latest player list
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
                        setRoom((prev) => (prev ? { ...prev, peer_connections: data.peer_connections } : (data as Room)))
                        roomRef.current = {
                            ...(roomRef.current ?? {}),
                            ...data,
                        } as Room
                    }
                }
            })

        channelRef.current = roomChannel
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
                peer_connections: { [peerId]: { isHost: true, playerName } }
            })

        if (error) {
            console.error('[create] Error creating room:', error)
            if (error.code === '23505') {
                return handleCreateRoom(playerName)
            }
            return
        }

        console.log(`[create] Room ${roomCode} created successfully`)

        const initialRoom = {
            room_code: roomCode,
            peer_connections: { [peerId]: { isHost: true, playerName } },
        }

        setRoom(initialRoom)
        roomRef.current = initialRoom

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

        const peerId = crypto.randomUUID()
        console.log(`[join] Generated peerId: ${peerId}`)
        setMyPeerId(peerId)
        myPeerIdRef.current = peerId

        // Set room state BEFORE creating peer connections so refs are available
        const existingConnections = data.peer_connections || {}
        const roomData = { ...data, peer_connections: existingConnections } as Room
        setRoom(roomData)
        roomRef.current = roomData

        // Subscribe to channel BEFORE sending offers so we can receive answers
        subscribeToRoom(roomCode)

        // Wait a tick for the subscription to be set up
        await new Promise(resolve => setTimeout(resolve, 100))

        // Add ourselves to the player list in DB
        console.log('[join] Adding to player list in DB...')
        const updatedPlayers = await updatePlayerList(roomCode, peerId, { playerName })

        if (updatedPlayers) {
            const nextRoom = { ...data, peer_connections: updatedPlayers } as Room
            setRoom(nextRoom)
            roomRef.current = nextRoom
        }

        // Create offers to all existing peers
        const existingPeers = Object.keys(existingConnections)
        console.log(`[join] Creating offers to ${existingPeers.length} existing peers:`, existingPeers)

        for (const existingPeerId of existingPeers) {
            const pc = createPeerConnection(existingPeerId)
            setupDataChannel(pc, existingPeerId)
            peerConnectionsRef.current = new Map(peerConnectionsRef.current).set(existingPeerId, pc)
            setPeerConnections(prev => new Map(prev).set(existingPeerId, pc))

            const offer = await pc.createOffer()
            await pc.setLocalDescription(offer)

            console.log(`[join] Sending offer to ${existingPeerId} via Broadcast`)
            sendSignal({
                type: 'offer',
                from: peerId,
                to: existingPeerId,
                sdp: JSON.stringify(offer),
            })
        }

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

    // Keep refs in sync
    useEffect(() => {
        peerConnectionsRef.current = peerConnections
    }, [peerConnections])

    useEffect(() => {
        roomRef.current = room
    }, [room])

    useEffect(() => {
        myPeerIdRef.current = myPeerId
    }, [myPeerId])

    // Cleanup on unmount
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
