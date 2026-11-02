import type { PlayerId } from '@/lib/engine/types'
import { isLanding } from '../engine/board'
import { alive, ask, rand } from '../engine/core'
import type { HauntedState, MonsterState, PlacedTile } from '../types'

/** Pick a value by player count: {3/4/5/6}. */
export function byCount<T>(s: HauntedState, values: [T, T, T, T]): T {
  const n = Math.min(6, Math.max(3, s.seats.length))
  return values[n - 3]!
}

export function traitor(s: HauntedState) {
  return s.explorers[s.haunt!.traitor!]!
}

export function heroes(s: HauntedState) {
  return Object.values(s.explorers).filter((e) => e.side === 'hero')
}

export function livingHeroes(s: HauntedState) {
  return heroes(s).filter((e) => alive(e))
}

export function allHeroesDead(s: HauntedState) {
  return livingHeroes(s).length === 0
}

export function addMonster(
  s: HauntedState,
  m: Omit<MonsterState, 'id' | 'stunned'>,
): MonsterState {
  const monster: MonsterState = { ...m, id: `${m.kind}${++s.seq}`, stunned: false }
  s.monsters.push(monster)
  return monster
}

export function nonLandingTiles(s: HauntedState): PlacedTile[] {
  return Object.values(s.tiles).filter((t) => !isLanding(t))
}

/** The first living hero to play after the traitor (decides hero-side choices). */
export function nextHero(s: HauntedState): PlayerId | null {
  const ti = s.order.indexOf(s.haunt!.traitor!)
  for (let k = 1; k <= s.order.length; k++) {
    const pid = s.order[(ti + k) % s.order.length]!
    const ex = s.explorers[pid]!
    if (ex.side === 'hero' && alive(ex)) return pid
  }
  return null
}

/** Ask a player to pick a tile; picks automatically when there's only one choice. */
export function chooseTile(
  s: HauntedState,
  pid: PlayerId,
  purpose: string,
  label: string,
  options: string[],
  data: Record<string, unknown>,
  onPick: (tile: string) => void,
) {
  if (options.length === 0) return
  if (options.length === 1) {
    onPick(options[0]!)
    return
  }
  ask(s, { kind: 'chooseTile', pid, purpose, label, options, data })
}

export function pickRandom<T>(items: T[]): T | undefined {
  return items[Math.floor(rand() * items.length)]
}
