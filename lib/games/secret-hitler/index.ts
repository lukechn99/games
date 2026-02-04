import { registerGame } from '@/lib/game-types'
import ComingSoon from '../coming-soon'

registerGame({
  id: 'secret-hitler',
  name: 'Secret Hitler',
  maxPlayers: 10,
  minPlayers: 5,
  rules: 'Hidden roles and policy cards. Liberals vs Fascists. Find Hitler before it’s too late.',
  component: ComingSoon,
})
