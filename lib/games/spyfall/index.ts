import { registerGame } from '@/lib/game-types'
import SpyfallGame from './SpyfallGame'

registerGame({
  id: 'spyfall',
  name: 'Spyfall',
  maxPlayers: 12,
  minPlayers: 2,
  rules: 'One player is the spy. Everyone else shares a secret location. Ask questions to find the spy before time runs out, then vote.',
  component: SpyfallGame,
})

export { SpyfallGame }
export { SPYFALL_LOCATIONS } from './locations'
export type { SpyfallGameState, SpyfallPhase } from './types'
