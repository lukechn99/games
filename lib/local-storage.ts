const STORAGE_KEY = 'active-game-session'

export interface GameSession {
  roomCode: string
  playerName: string
  peerId: string
  timestamp: number
}

export function saveGameSession(session: Omit<GameSession, 'timestamp'>): void {
  try {
    const data: GameSession = { ...session, timestamp: Date.now() }
    localStorage.setItem(STORAGE_KEY, JSON.stringify(data))
  } catch {
    // localStorage may be unavailable (e.g. SSR, private browsing quota)
  }
}

export function loadGameSession(): GameSession | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return null
    return JSON.parse(raw) as GameSession
  } catch {
    return null
  }
}

export function clearGameSession(): void {
  try {
    localStorage.removeItem(STORAGE_KEY)
  } catch {
    // ignore
  }
}
