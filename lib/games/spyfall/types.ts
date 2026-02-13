export type SpyfallPhase = 'waiting' | 'playing' | 'voting' | 'ended'

export interface SpyfallGameState {
  phase: SpyfallPhase
  spyPeerId?: string
  location?: string
  startedAt?: number
  result?: {
    spyPeerId: string
    votedOutPeerId: string | null
    win: 'spy' | 'innocents'
  }
}

export const SPYFALL_DURATION_MS = 15 * 60 * 1000 // 15 minutes
