import { registerGame } from '@/lib/game-types'
import SecretHitlerGame from './SecretHitlerGame'

registerGame({
  id: 'secret-hitler',
  name: 'Secret Hitler',
  maxPlayers: 10,
  minPlayers: 5,
  rules: 'Hidden roles and policy cards. Liberals vs Fascists. Find and stop Secret Hitler before it\'s too late! 5-10 players.',
  component: SecretHitlerGame,
})

export { SecretHitlerGame }
export type { SecretHitlerGameState } from './types'
