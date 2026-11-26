import type { GameModule, PlayerId, RuleResult } from '@/lib/engine/types'

/**
 * Hide and Seek (docs/hideseek/DESIGN.md, section 13).
 *
 * The round runs in the Godot game embedded in the room page. These rules
 * hold what everyone must agree on: who seeks, each hider's prop, rerolls,
 * paintballs, who has been found, the round clock and the scores. Positions
 * and paintball flights are too fast for the rules: they go player to player
 * through the room's relay. The game's solo practice mirrors these rules in
 * hideseek/scripts/rules.gd; keep the two in step (tests on both sides).
 *
 * Bots are played by the host's game, which acts for them with `as`.
 */

/** Props a hider can be: everything used as scenery (Props.KINDS). */
export const PROPS = ['bale', 'trash_can', 'tire', 'chair', 'crate', 'bucket', 'rake'] as const
export type PropKind = (typeof PROPS)[number]

export const HIDE_MS = 45_000
export const SEEK_MS = 180_000
export const RESULTS_MS = 8_000
export const START_AMMO = 100
export const AMMO_PER_FIND = 3
export const REROLLS = 2
export const DECOYS = 3

export interface Member {
  role: 'hider' | 'seeker'
  /** The hider's prop ('' for seekers who started as seekers). */
  prop: PropKind | ''
  rerolls: number
  /** Decoys left to drop this round (hiders). */
  decoys: number
  ammo: number
  /** Ms into the round when found, or null. */
  foundAt: number | null
}

export interface HideSeekState {
  round: number
  /** Seeds the spark order, shared by every phone. */
  seed: number
  /** Host clock (ms) when the hide phase began. */
  startAt: number
  hideMs: number
  seekMs: number
  seats: PlayerId[]
  members: Record<PlayerId, Member>
  /** Hiders when the round began: the spark schedule is built from these. */
  hidersAtStart: PlayerId[]
  finds: { seeker: PlayerId; hider: PlayerId; at: number }[]
  /** Copies of hiders' props dropped as decoys; painting one pops it. */
  decoys: Decoy[]
  /** Match points (design 5). */
  scores: Record<PlayerId, number>
  winner: 'seekers' | 'hiders' | null
  /** Host clock when the round was decided. */
  overAt: number | null
  /** How many times each player has sought this match. */
  sought: Record<PlayerId, number>
}

export interface Decoy {
  id: string
  by: PlayerId
  prop: PropKind
  /** Where it stands (x, y, z) and how it's turned (quaternion x, y, z, w). */
  at: [number, number, number]
  q: [number, number, number, number]
}

export type HideSeekAction =
  | { type: 'reroll'; as?: PlayerId }
  | { type: 'decoy'; at: [number, number, number]; q: [number, number, number, number]; as?: PlayerId }
  | { type: 'pop'; decoy: string; as?: PlayerId }
  | { type: 'shoot'; as?: PlayerId }
  | { type: 'find'; hider: PlayerId; as?: PlayerId }

export type HideSeekView = HideSeekState & { me: PlayerId | null }

/** Seekers for a room of `n` players (bots count): about one per two or three hiders. */
export function seekerCount(n: number): number {
  return Math.max(1, Math.floor((n + 1) / 3))
}

function pick<T>(list: readonly T[], random: () => number): T {
  return list[Math.min(list.length - 1, Math.floor(random() * list.length))]!
}

function randomProp(random: () => number, not?: string): PropKind {
  const choices = PROPS.filter((p) => p !== not)
  return pick(choices, random)
}

/** Deal a new round: seekers at random, a random prop for every hider. */
function deal(s: Pick<HideSeekState, 'seats' | 'scores' | 'sought'> & { round: number }, now: number, random: () => number): HideSeekState {
  const pool = [...s.seats].sort()
  const seekers = new Set<PlayerId>()
  for (let i = 0; i < seekerCount(pool.length); i++) seekers.add(pool.splice(Math.floor(random() * pool.length), 1)[0]!)
  const members: Record<PlayerId, Member> = {}
  for (const id of s.seats) {
    const seeker = seekers.has(id)
    members[id] = {
      role: seeker ? 'seeker' : 'hider',
      prop: seeker ? '' : randomProp(random),
      rerolls: seeker ? 0 : REROLLS,
      decoys: seeker ? 0 : DECOYS,
      ammo: seeker ? START_AMMO : 0,
      foundAt: null,
    }
  }
  const sought = { ...s.sought }
  for (const id of seekers) sought[id] = (sought[id] ?? 0) + 1
  return {
    round: s.round + 1,
    seed: Math.floor(random() * 1e9),
    startAt: now,
    hideMs: HIDE_MS,
    seekMs: SEEK_MS,
    seats: s.seats,
    members,
    hidersAtStart: s.seats.filter((id) => !seekers.has(id)),
    finds: [],
    decoys: [],
    scores: s.scores,
    winner: null,
    overAt: null,
    sought,
  }
}

/** Ms into the round at host time `now`. */
export function elapsed(s: HideSeekState, now: number): number {
  return now - s.startAt
}

export function phase(s: HideSeekState, now: number): 'hide' | 'seek' | 'over' {
  if (s.winner) return 'over'
  return elapsed(s, now) < s.hideMs ? 'hide' : 'seek'
}

/** Who has won at `now`, if anyone (design 4, 7). */
export function decide(s: HideSeekState, now: number): 'seekers' | 'hiders' | null {
  const t = elapsed(s, now)
  if (t < s.hideMs) return null
  const ids = Object.keys(s.members)
  const hiders = ids.filter((id) => s.members[id]!.role === 'hider')
  if (hiders.length === 0) return 'seekers'
  if (t >= s.hideMs + s.seekMs) return 'hiders'
  const seekers = ids.filter((id) => s.members[id]!.role === 'seeker')
  if (seekers.length > 0 && seekers.every((id) => s.members[id]!.ammo <= 0)) return 'hiders'
  return null
}

/** Points for the round just decided (design 5). */
function score(s: HideSeekState, now: number): Record<PlayerId, number> {
  const scores = { ...s.scores }
  const end = Math.min(elapsed(s, now), s.hideMs + s.seekMs)
  for (const id of s.hidersAtStart) {
    const m = s.members[id]!
    const until = m.foundAt ?? end
    const survived = Math.max(0, until - s.hideMs)
    scores[id] = (scores[id] ?? 0) + Math.floor(survived / 30_000) + (m.foundAt === null ? 3 : 0)
  }
  for (const f of s.finds) scores[f.seeker] = (scores[f.seeker] ?? 0) + 3
  return scores
}

export const hideSeek: GameModule<HideSeekState, HideSeekAction, HideSeekView> = {
  id: 'hideseek',
  name: 'Hide and Seek',
  description: 'Prop hunt on a farm: hiders become barn objects, seekers hunt them with paintballs.',
  // Someone has to hide: at least two, and computer players count.
  minPlayers: 2,
  maxPlayers: 10,
  botDelayMs: 1000,

  setup(playerIds, ctx) {
    return deal({ seats: [...playerIds], scores: {}, sought: {}, round: 0 }, ctx.now, ctx.random)
  },

  action(s, pid, a, ctx): RuleResult<HideSeekState> {
    const who = a.as ?? pid
    const m = s.members[who]
    if (!m) return { error: 'You are not in this round.' }
    if (who !== pid && !s.seats.includes(pid)) return { error: 'Only players can act for a bot.' }
    const ph = phase(s, ctx.now)
    if (ph === 'over') return { error: 'The round is over.' }
    switch (a.type) {
      case 'reroll': {
        if (m.role !== 'hider') return { error: 'Only hiders reroll.' }
        if (m.rerolls <= 0) return { error: 'No rerolls left.' }
        const members = { ...s.members, [who]: { ...m, rerolls: m.rerolls - 1, prop: randomProp(ctx.random, m.prop) } }
        return { state: { ...s, members } }
      }
      case 'decoy': {
        if (m.role !== 'hider' || !m.prop) return { error: 'Only hiders drop decoys.' }
        if (m.decoys <= 0) return { error: 'No decoys left.' }
        if (!isVec(a.at, 3) || !isVec(a.q, 4)) return { error: 'Bad decoy.' }
        const id = `${who}-${DECOYS - m.decoys + 1}`
        const decoy: Decoy = { id, by: who, prop: m.prop, at: a.at, q: a.q }
        return { state: { ...s, members: { ...s.members, [who]: { ...m, decoys: m.decoys - 1 } }, decoys: [...s.decoys, decoy] } }
      }
      case 'pop': {
        if (m.role !== 'seeker') return { error: 'Only seekers pop decoys.' }
        if (ph !== 'seek') return { error: 'Wait for the seek phase.' }
        if (!s.decoys.some((d) => d.id === a.decoy)) return { error: 'No such decoy.' }
        return { state: { ...s, decoys: s.decoys.filter((d) => d.id !== a.decoy) } }
      }
      case 'shoot': {
        if (m.role !== 'seeker') return { error: 'Only seekers shoot.' }
        if (ph !== 'seek') return { error: 'Wait for the seek phase.' }
        if (m.ammo <= 0) return { error: 'Out of paint.' }
        return { state: settle({ ...s, members: { ...s.members, [who]: { ...m, ammo: m.ammo - 1 } } }, ctx.now) }
      }
      case 'find': {
        if (m.role !== 'seeker') return { error: 'Only seekers find.' }
        if (ph !== 'seek') return { error: 'Wait for the seek phase.' }
        const h = s.members[a.hider]
        if (!h || h.role !== 'hider') return { error: 'Not a hider.' }
        const at = elapsed(s, ctx.now)
        const members = {
          ...s.members,
          [who]: { ...m, ammo: m.ammo + AMMO_PER_FIND },
          // A found hider joins the seekers, with fresh paint.
          [a.hider]: { ...h, role: 'seeker' as const, ammo: START_AMMO, foundAt: at },
        }
        return { state: settle({ ...s, members, finds: [...s.finds, { seeker: who, hider: a.hider, at }] }, ctx.now) }
      }
    }
  },

  view: (s, playerId) => ({ ...s, me: playerId }),

  tick(s, ctx) {
    if (s.winner) {
      // Results, then the next round with new roles.
      if (s.overAt !== null && ctx.now - s.overAt >= RESULTS_MS) return deal(s, ctx.now, ctx.random)
      return s
    }
    return settle(s, ctx.now)
  },

  playerLeft(s, playerId) {
    const members = { ...s.members }
    delete members[playerId]
    return { ...s, seats: s.seats.filter((id) => id !== playerId), members, hidersAtStart: s.hidersAtStart.filter((id) => id !== playerId) }
  },

  isOver: () => false,

  // Bots are played by the host's game (it acts for them with `as`); the room
  // only needs to know they can be seated.
  bot: () => null,
}

function isVec(v: unknown, n: number): boolean {
  return Array.isArray(v) && v.length === n && v.every((x) => typeof x === 'number' && Number.isFinite(x))
}

/** Decide the round if it's over. */
function settle(s: HideSeekState, now: number): HideSeekState {
  if (s.winner) return s
  const w = decide(s, now)
  if (!w) return s
  return { ...s, winner: w, overAt: now, scores: score(s, now) }
}
