/**
 * Shared engine helpers: dice, log, explorer traits, damage and healing.
 * All functions mutate the draft state they're given (the rules module
 * clones state once per action).
 */
import type { PlayerId, RuleContext } from '@/lib/engine/types'
import { CARD_BY_ID } from '../data/cards'
import { EXPLORER_BY_ID } from '../data/explorers'
import type {
  Continuation,
  DamageType,
  ExplorerState,
  HauntedState,
  Prompt,
  Trait,
} from '../types'
import { MENTAL, PHYSICAL, TRAITS } from '../types'

/** Per-action context (random source and clock). Set by the rules module. */
export const env: { ctx: RuleContext } = { ctx: { now: 0, random: Math.random } }

export function rand(): number {
  return env.ctx.random()
}

export function shuffle<T>(items: T[]): T[] {
  const a = [...items]
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1))
    ;[a[i], a[j]] = [a[j]!, a[i]!]
  }
  return a
}

/** Betrayal dice: two faces each of 0, 1 and 2. */
export function rollDice(n: number): number[] {
  const out: number[] = []
  for (let i = 0; i < Math.max(0, Math.min(8, n)); i++) out.push(Math.floor(rand() * 3))
  return out
}

export function recordRoll(s: HauntedState, by: string, label: string, dice: number[], bonus = 0): number {
  const total = dice.reduce((a, b) => a + b, 0) + bonus
  s.rolls = [...s.rolls.slice(-11), { id: ++s.seq, by, label, dice, bonus, total }]
  return total
}

export function log(s: HauntedState, text: string, to?: PlayerId[]) {
  s.log = [...s.log.slice(-79), { id: ++s.seq, text, to }]
}

export function nameOf(s: HauntedState, pid: PlayerId): string {
  const ex = s.explorers[pid]
  return ex ? EXPLORER_BY_ID.get(ex.explorerId)?.name ?? 'Someone' : 'Someone'
}

export function cardName(id: string): string {
  return CARD_BY_ID.get(id)?.name ?? id
}

/* ------------------------------------------------------------------ */
/*  Prompts                                                            */
/* ------------------------------------------------------------------ */

/** Show a prompt now, or queue it behind the current one. */
export function ask(s: HauntedState, p: Prompt) {
  if (s.prompt) s.queue.push(p)
  else s.prompt = p
}

/** Ask before anything already queued (used for nested interrupts). */
export function askFirst(s: HauntedState, p: Prompt) {
  if (s.prompt) s.queue.unshift(p)
  else s.prompt = p
}

/* ------------------------------------------------------------------ */
/*  Traits                                                             */
/* ------------------------------------------------------------------ */

export function track(ex: ExplorerState, t: Trait) {
  return EXPLORER_BY_ID.get(ex.explorerId)!.traits[t]
}

export function value(ex: ExplorerState, t: Trait): number {
  const i = ex.idx[t]
  if (i < 0) return 0
  return track(ex, t).values[i]!
}

export function hasCard(ex: ExplorerState, kind: string): string | undefined {
  return [...ex.items, ...ex.omens].find((c) => CARD_BY_ID.get(c)?.effect?.kind === kind)
}

export function alive(ex: ExplorerState | undefined): ex is ExplorerState {
  return !!ex && !ex.dead && !ex.removed
}

/** Lowest index a trait may drop to right now (critical before the haunt). */
function floorFor(s: HauntedState, ex: ExplorerState, t: Trait): number {
  if (s.phase !== 'haunt') return 0
  // Haunt 30: the possessed traitor's traits can't go below their starting values.
  if (s.haunt?.number === 30 && ex.side === 'traitor') return track(ex, t).start
  return -1
}

export function gain(s: HauntedState, ex: ExplorerState, t: Trait, n: number) {
  if (!alive(ex) || n <= 0) return
  ex.idx[t] = Math.min(7, ex.idx[t] + n)
}

/** Direct trait loss (not damage). May kill after the haunt starts. */
export function lose(s: HauntedState, ex: ExplorerState, t: Trait, n: number) {
  if (!alive(ex) || n <= 0) return
  ex.idx[t] = Math.max(floorFor(s, ex, t), ex.idx[t] - n)
  checkDeath(s, ex)
}

export function heal(ex: ExplorerState, traits: Trait[]) {
  for (const t of traits) ex.idx[t] = Math.max(ex.idx[t], track(ex, t).start)
}

export function checkDeath(s: HauntedState, ex: ExplorerState) {
  if (ex.dead || s.phase !== 'haunt') return
  if (TRAITS.some((t) => ex.idx[t] < 0)) {
    ex.dead = true
    for (const t of TRAITS) ex.idx[t] = Math.max(ex.idx[t], -1)
    log(s, `${nameOf(s, ex.pid)} has died.`)
    // Haunt 30: a dead hero's omens are turned face up.
    if (s.haunt?.number === 30) ex.revealed = [...ex.omens]
  }
}

/* ------------------------------------------------------------------ */
/*  Damage                                                             */
/* ------------------------------------------------------------------ */

export function damageTraits(ex: ExplorerState, type: DamageType): Trait[] {
  if (type === 'general' || hasCard(ex, 'brooch')) return TRAITS
  return type === 'physical' ? PHYSICAL : MENTAL
}

/**
 * Deal damage. Applies item reductions, then asks the player how to split
 * it unless there's only one sensible way.
 */
export function damage(
  s: HauntedState,
  pid: PlayerId,
  type: DamageType,
  amount: number,
  reason: string,
  opts: { fromAttack?: boolean; then?: Continuation } = {},
) {
  const ex = s.explorers[pid]
  if (!alive(ex)) return
  let n = amount
  if (type === 'mental' && hasCard(ex, 'headphones')) n -= 1
  if (opts.fromAttack && hasCard(ex, 'armor')) n -= 1
  if (opts.fromAttack && s.haunt?.number === 44 && ex.side === 'traitor') n -= 1
  if (n <= 0) {
    log(s, `${nameOf(s, pid)} shrugs off the damage.`)
    return
  }
  const options = damageTraits(ex, type).filter((t) => ex.idx[t] > floorFor(s, ex, t) || s.phase === 'haunt')
  if (options.length === 1) {
    applyDamage(s, ex, { [options[0]!]: n }, type)
    return
  }
  ask(s, { kind: 'damage', pid, type, amount: n, reason, then: opts.then })
}

/** Validate and apply a split chosen by the player. Returns an error or null. */
export function allocate(
  s: HauntedState,
  ex: ExplorerState,
  type: DamageType,
  amount: number,
  split: Partial<Record<Trait, number>>,
): string | null {
  const allowed = damageTraits(ex, type)
  let total = 0
  for (const [t, v] of Object.entries(split) as [Trait, number][]) {
    if (!v) continue
    if (!Number.isInteger(v) || v < 0) return 'Invalid amount.'
    if (!allowed.includes(t)) return `This damage can't go on ${t}.`
    total += v
  }
  if (total !== amount) return `Assign exactly ${amount}.`
  if (s.phase !== 'haunt') {
    // Before the haunt: you can't push damage into a critical trait while
    // another allowed trait could still take it.
    const roomLeft = (t: Trait) => ex.idx[t]
    for (const t of allowed) {
      const take = split[t] ?? 0
      if (take > roomLeft(t)) {
        const others = allowed.filter((o) => o !== t).reduce((a, o) => a + Math.max(0, roomLeft(o) - (split[o] ?? 0)), 0)
        if (others > 0) return 'Put the damage on traits that are not yet critical first.'
      }
    }
  }
  applyDamage(s, ex, split, type)
  return null
}

export function applyDamage(s: HauntedState, ex: ExplorerState, split: Partial<Record<Trait, number>>, type: DamageType) {
  const parts: string[] = []
  let physicalTaken = 0
  for (const [t, v] of Object.entries(split) as [Trait, number][]) {
    if (!v) continue
    ex.idx[t] = Math.max(floorFor(s, ex, t), ex.idx[t] - v)
    parts.push(`${v} ${t}`)
    if (PHYSICAL.includes(t) && type !== 'general') physicalTaken += v
  }
  if (parts.length) log(s, `${nameOf(s, ex.pid)} takes ${parts.join(', ')} damage.`)
  checkDeath(s, ex)
  if (physicalTaken > 0 && hasCard(ex, 'amulet') && alive(ex)) gain(s, ex, 'sanity', 1)
}
