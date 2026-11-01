import { registerGame } from '@/lib/game-types'
import ComingSoon from '../coming-soon'

registerGame({
  id: 'codenames',
  name: 'Codenames',
  maxPlayers: 8,
  minPlayers: 2,
  rules: 'Give one-word clues to help your team guess words on the board. Avoid the assassin.',
  component: ComingSoon,
})
