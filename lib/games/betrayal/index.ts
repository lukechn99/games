import { registerGame } from '@/lib/game-types'
import BetrayalGame from './BetrayalGame'

registerGame({
  id: 'betrayal',
  name: 'Betrayal at House on the Hill',
  maxPlayers: 6,
  minPlayers: 3,
  rules: 'Explore a haunted house. One traitor will be revealed—survive the haunt.',
  component: BetrayalGame,
})

export { BetrayalGame }
export type { BetrayalGameState } from './types'
