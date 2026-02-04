import { registerGame } from '@/lib/game-types'
import ComingSoon from '../coming-soon'

registerGame({
  id: 'betrayal',
  name: 'Betrayal at House on the Hill',
  maxPlayers: 6,
  minPlayers: 3,
  rules: 'Explore a haunted house. One traitor will be revealed—survive the haunt.',
  component: ComingSoon,
})
