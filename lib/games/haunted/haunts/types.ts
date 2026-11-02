import type { PlayerId } from '@/lib/engine/types'
import type { TraitorRule } from '../data/scenarios'
import type { HauntedState, PlacedTile, Prompt } from '../types'

export interface Briefing {
  intro: string
  goal: string
  rules: string[]
}

export interface SpecialDef {
  id: string
  label: string
  side: 'hero' | 'traitor'
  rules: string
  /** Return a reason it can't be used now, or null if it can. */
  check(s: HauntedState, pid: PlayerId): string | null
  /** Asks for a number (e.g. how many explosives to use). */
  countPrompt?: (s: HauntedState, pid: PlayerId) => { label: string; max: number } | null
  /** Asks the player to pick a tile. */
  tilePrompt?: (s: HauntedState, pid: PlayerId) => { label: string; options: string[] } | null
  run(s: HauntedState, pid: PlayerId, args: { tile?: string; count?: number }): string | null
  /** Called with the result of a trait roll started by `run`. */
  resolve?(s: HauntedState, pid: PlayerId, total: number, data?: Record<string, unknown>): void
}

export interface HauntDef {
  number: number
  title: string
  traitorRule: TraitorRule
  hero: Briefing
  traitor: Briefing
  /** 'instead': the traitor's turn is a monster turn. 'after': monsters go after the traitor. */
  monsterTurn: 'instead' | 'after' | 'none'
  /** Runs once the traitor is known. */
  setup(s: HauntedState): void
  specials: SpecialDef[]
  onHeroTurnStart?(s: HauntedState, pid: PlayerId): void
  onMonsterTurnEnd?(s: HauntedState): void
  onTurnEnd?(s: HauntedState, pid: PlayerId, actor: 'player' | 'monsters'): void
  /** An explorer entered a tile by moving. */
  onEnter?(s: HauntedState, pid: PlayerId, tile: PlacedTile): void
  onDiscover?(s: HauntedState, tile: PlacedTile): void
  onTraitorAttack?(s: HauntedState, target: PlayerId): void
  onChooseTile?(s: HauntedState, prompt: Extract<Prompt, { kind: 'chooseTile' }>, tile: string): void
  /** Can this explorer leave their tile? Return a reason if not. */
  blockLeave?(s: HauntedState, pid: PlayerId): string | null
  checkWin(s: HauntedState): { winner: 'heroes' | 'traitor'; text: string } | null
}
