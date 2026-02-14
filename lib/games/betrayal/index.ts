import { registerGame } from '@/lib/game-types'
import BetrayalGame from './BetrayalGame'

registerGame({
  id: 'betrayal',
  name: 'Betrayal at House on the Hill',
  maxPlayers: 6,
  minPlayers: 3,
  rules: 'Explore a haunted house by placing room tiles. Draw Events, Items, and Omens as you go. When an Omen triggers the haunt, one explorer becomes the traitor — heroes must survive. 3rd Edition rules: 3-6 players, 60-90 min.',
  component: BetrayalGame,
})

export { BetrayalGame }
export type { BetrayalGameState } from './types'
