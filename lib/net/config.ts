import type { PeerOptions } from 'peerjs'
import { iceServers } from './turn'

/**
 * Prefix for broker ids. The public PeerJS broker is shared by everyone who
 * uses it, so the prefix keeps our room codes from colliding with other apps.
 */
export const PEER_PREFIX = 'lukechn99-games-'

export function hostPeerId(code: string): string {
  return `${PEER_PREFIX}${code.toUpperCase()}`
}

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' // no I, O, 0, 1
export const CODE_LENGTH = 5

export function generateRoomCode(): string {
  const bytes = new Uint8Array(CODE_LENGTH)
  crypto.getRandomValues(bytes)
  return Array.from(bytes, (b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join('')
}

export function normalizeCode(raw: string): string {
  return raw.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, CODE_LENGTH)
}

export function isValidCode(code: string): boolean {
  return code.length === CODE_LENGTH && [...code].every((c) => CODE_ALPHABET.includes(c))
}

/**
 * Broker + ICE settings. With no environment variables this uses the free
 * public PeerJS broker and public STUN servers. To use your own broker (the
 * `peer` npm package) or add a TURN relay, set these at build time:
 *
 *   NEXT_PUBLIC_PEER_HOST=my-broker.onrender.com
 *   NEXT_PUBLIC_PEER_PORT=443
 *   NEXT_PUBLIC_PEER_PATH=/
 *   NEXT_PUBLIC_PEER_SECURE=true
 *   NEXT_PUBLIC_TURN_URL=turn:turn.example.com:3478
 *   NEXT_PUBLIC_TURN_USERNAME=...
 *   NEXT_PUBLIC_TURN_CREDENTIAL=...
 *   NEXT_PUBLIC_TURN_WORKER=https://games-turn.you.workers.dev  (Cloudflare relay, see worker/)
 */
export function peerOptions(): PeerOptions {
  const options: PeerOptions = { config: { iceServers }, debug: 1 }
  const host = process.env.NEXT_PUBLIC_PEER_HOST
  if (host) {
    options.host = host
    options.port = Number(process.env.NEXT_PUBLIC_PEER_PORT || 443)
    options.path = process.env.NEXT_PUBLIC_PEER_PATH || '/'
    options.secure = (process.env.NEXT_PUBLIC_PEER_SECURE ?? 'true') !== 'false'
  }
  return options
}

/** How often each side sends a heartbeat, and how long silence means "gone". */
export const HEARTBEAT_MS = 2000
export const TIMEOUT_MS = 8000
