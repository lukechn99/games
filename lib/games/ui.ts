import type { ComponentType } from 'react'
import type { PlayerId, RoomSnapshot } from '@/lib/engine/types'
import SpyfallView from './spyfall/SpyfallView'
import HauntedView from './haunted/ui/HauntedView'
import FourView from './fourinarow/FourView'
import SHView from './secrethitler/SHView'

export interface GameViewProps<V = unknown, A = unknown> {
  view: V
  snapshot: RoomSnapshot
  me: PlayerId
  isHost: boolean
  /** Send a game action to the host. */
  act: (action: A) => void
  /** Host room actions available from inside a game. */
  playAgain: () => void
  backToLobby: () => void
  /** Current time on the host's clock, for countdowns. */
  hostNow: () => number
  nameOf: (id: PlayerId) => string
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const GAME_VIEWS: Record<string, ComponentType<GameViewProps<any, any>>> = {
  spyfall: SpyfallView,
  haunted: HauntedView,
  fourinarow: FourView,
  secrethitler: SHView,
}
