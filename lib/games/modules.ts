/**
 * Game rules registry. Kept free of React so the engine and tests can import
 * it without pulling in UI code. UI components live in `./ui.ts`.
 */
import type { GameModule } from '@/lib/engine/types'
import type { GameLookup } from '@/lib/engine/room'
import { spyfall } from './spyfall/rules'
import { hauntedHouse } from './haunted/rules'
import { fourInARow } from './fourinarow/rules'
import { secretHitler } from './secrethitler/rules'

export const GAME_MODULES: GameModule[] = [spyfall as GameModule, hauntedHouse as GameModule, fourInARow as GameModule, secretHitler as GameModule]

const byId = new Map(GAME_MODULES.map((g) => [g.id, g]))

export const getGameModule: GameLookup = (id) => byId.get(id)

/** Games still being ported to the new engine. Shown greyed out in the lobby. */
export const COMING_SOON = [
  { name: 'Codenames', players: '4–8' },
]
