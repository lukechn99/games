import type { GameModule, PlayerId } from '@/lib/engine/types'

/**
 * Hide and Seek (docs/hideseek/DESIGN.md).
 *
 * For now (milestone H0) each player gets their own copy of the practice
 * barn: a solo sandbox with three practice hiders, run entirely by the
 * Godot game (public/hideseek). The shared round (teams, timers, tags)
 * moves into these rules in H2, mirroring hideseek/scripts/rules.gd.
 */
export interface HideSeekState {
  phase: 'practice'
  seats: PlayerId[]
}

export type HideSeekAction = never

export interface HideSeekView {
  phase: 'practice'
  seated: boolean
}

export const hideSeek: GameModule<HideSeekState, HideSeekAction, HideSeekView> = {
  id: 'hideseek',
  name: 'Hide and Seek',
  description: 'Prop hunt on a farm. Solo practice for now: everyone gets their own barn to explore.',
  minPlayers: 1,
  maxPlayers: 10,
  setup: (playerIds) => ({ phase: 'practice', seats: [...playerIds] }),
  action: () => ({ error: 'Hide and Seek has no shared moves yet' }),
  view: (state, playerId) => ({ phase: state.phase, seated: !!playerId && state.seats.includes(playerId) }),
  isOver: () => false,
}
