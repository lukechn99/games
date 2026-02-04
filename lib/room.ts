export interface Room {
    room_code: string;
    peer_connections: Record<string, { isHost?: boolean; playerName: string }>;
}