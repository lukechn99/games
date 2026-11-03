/**
 * Haunted House computer player. Plays like a sensible beginner: explores,
 * patches itself up, then follows a small playbook for each haunt.
 * It only sees its own seat's view, so it can't peek at hidden omens.
 */
import type { BotLevel, PlayerId, RuleContext } from '@/lib/engine/types'
import { CARD_BY_ID } from './data/cards'
import { EXPLORERS } from './data/explorers'
import { TILE_BY_ID } from './data/tiles'
import { distances, rotateDoors, symbols, tileAt } from './engine/board'
import type { HauntedView } from './rules'
import type { HauntedAction, HauntedState, PlacedTile, Prompt, Trait } from './types'
import { DIRS, DX, DY, MENTAL, PHYSICAL, TRAITS } from './types'

type V = HauntedView
const asState = (v: V) => v as unknown as HauntedState

function pick<T>(xs: T[], random: () => number): T | undefined {
  return xs[Math.floor(random() * xs.length)]
}

function alive(v: V, pid: PlayerId) {
  const e = v.explorers[pid]
  return !!e && !e.dead && !e.removed
}

/** Moves from `from` to the nearest of `targets` (Infinity if unreachable). */
function distTo(v: V, from: string, targets: Set<string>, monster = false): number {
  if (targets.has(from)) return 0
  const d = distances(asState(v), v.tiles[from]!, { monster })
  let best = Infinity
  for (const t of targets) best = Math.min(best, d.get(t) ?? Infinity)
  return best
}

/** The candidate step that gets closest to any target; null if none helps. */
function stepToward(v: V, from: string, candidates: string[], targets: Set<string>, opts: { monster?: boolean; avoid?: Set<string> } = {}): string | null {
  if (!targets.size || !candidates.length) return null
  const here = distTo(v, from, targets, opts.monster)
  let best: string | null = null
  let bestD = here
  for (const c of candidates) {
    if (opts.avoid?.has(c)) continue
    const d = distTo(v, c, targets, opts.monster)
    if (d < bestD) {
      bestD = d
      best = c
    }
  }
  return best
}

const tilesWhere = (v: V, f: (t: PlacedTile) => boolean) => new Set(Object.values(v.tiles).filter(f).map((t) => t.uid))

function hasOpenDoor(v: V, t: PlacedTile) {
  return DIRS.some((d) => (t.flipped || t.doors & (1 << d)) && !tileAt(asState(v), t.region, t.x + DX[d]!, t.y + DY[d]!))
}

/* ------------------------------------------------------------------ */
/*  Prompts                                                            */
/* ------------------------------------------------------------------ */

function answerPrompt(v: V, me: PlayerId, p: Prompt, random: () => number): HauntedAction | null {
  const ex = v.explorers[me]
  switch (p.kind) {
    case 'haunt':
      // Leave this to the human host, so people get to read their briefings.
      return null
    case 'trade':
      return p.to === me ? { type: 'answerTrade', accept: false } : null
  }
  if (!('pid' in p) || p.pid !== me) return null
  switch (p.kind) {
    case 'place': {
      // Prefer the rotation that opens the most new doorways.
      const def = TILE_BY_ID.get(p.tileId)!
      let best = p.options[0]!
      let bestN = -1
      for (const rot of p.options) {
        const doors = rotateDoors(def.doors, rot)
        let n = 0
        for (const d of DIRS) if (doors & (1 << d) && !tileAt(asState(v), p.at.region, p.at.x + DX[d]!, p.at.y + DY[d]!)) n++
        if (n > bestN || (n === bestN && random() < 0.5)) {
          bestN = n
          best = rot
        }
      }
      return { type: 'place', rot: best }
    }
    case 'damage': {
      // Spread damage onto whichever allowed trait is healthiest.
      const brooch = ex!.items.some((c) => CARD_BY_ID.get(c)?.effect?.kind === 'brooch')
      const allowed: Trait[] = p.type === 'general' || brooch ? TRAITS : p.type === 'physical' ? PHYSICAL : MENTAL
      const idx = { ...ex!.idx }
      const split: Partial<Record<Trait, number>> = {}
      for (let i = 0; i < p.amount; i++) {
        const t = allowed.reduce((a, b) => (idx[b] > idx[a] ? b : a))
        idx[t]--
        split[t] = (split[t] ?? 0) + 1
      }
      return { type: 'allocate', split }
    }
    case 'event':
      return { type: 'rollEvent' }
    case 'card':
      return { type: 'continue' }
    case 'reroll':
      return { type: 'acceptRoll' }
    case 'gainChoice':
      return { type: 'gainPick', trait: p.traits.reduce((a, b) => (ex!.idx[b] < ex!.idx[a] ? b : a)) }
    case 'elevator':
      return { type: 'elevatorRegion', region: pick(['upper', 'ground', 'basement'] as const, random)! }
    case 'attackResult': {
      const victim = v.explorers[p.target]!
      if (victim.omens.includes('omenRing')) return { type: 'steal', card: 'omenRing' }
      return { type: 'steal', card: null }
    }
    case 'chooseTile':
      return { type: 'chooseTile', tile: chooseTile(v, me, p, random) }
  }
  return null
}

function heroTiles(v: V) {
  return new Set(Object.values(v.explorers).filter((e) => e.side === 'hero' && !e.dead && !e.removed).map((e) => e.tile))
}

function chooseTile(v: V, me: PlayerId, p: Extract<Prompt, { kind: 'chooseTile' }>, random: () => number): string {
  const heroes = heroTiles(v)
  const closest = (targets: Set<string>) => {
    let best = p.options[0]!
    let bestD = Infinity
    for (const o of p.options) {
      const d = distTo(v, o, targets)
      if (d < bestD || (d === bestD && random() < 0.5)) {
        bestD = d
        best = o
      }
    }
    return best
  }
  if (p.purpose === 'flood' || p.purpose === 'flood-setup') return closest(heroes)
  if (p.purpose === 'compel') {
    const altar = tilesWhere(v, (t) => t.tokens.includes('altar'))
    return altar.size ? closest(altar) : pick(p.options, random)!
  }
  return pick(p.options, random)!
}

/* ------------------------------------------------------------------ */
/*  Turns                                                              */
/* ------------------------------------------------------------------ */

function healIfHurt(v: V, me: PlayerId): HauntedAction | null {
  const ex = v.explorers[me]!
  const critical = TRAITS.filter((t) => ex.idx[t] === 0)
  if (!critical.length) return null
  for (const c of ex.items) {
    if (ex.newThisTurn.includes(c)) continue
    const k = CARD_BY_ID.get(c)?.effect?.kind
    if (k === 'firstAid') return { type: 'useItem', card: c }
    if (k === 'mirror' && critical.some((t) => MENTAL.includes(t))) return { type: 'useItem', card: c }
    if (k === 'medicine' && critical.some((t) => PHYSICAL.includes(t))) return { type: 'useItem', card: c }
  }
  return null
}

/** Walk toward the nearest unexplored doorway, or explore one right here. */
function explore(v: V, me: PlayerId, random: () => number): HauntedAction | null {
  const o = v.options!
  if (o.explore.length) return { type: 'move', dir: pick(o.explore, random)! }
  if (v.stackCount === 0) return null
  const from = v.explorers[me]!.tile
  const step = stepToward(v, from, o.moves, tilesWhere(v, (t) => hasOpenDoor(v, t)))
  return step ? { type: 'moveTo', tile: step } : null
}

function special(v: V, id: string, extra: { count?: number; tile?: string } = {}): HauntedAction | null {
  const sp = v.options!.specials.find((s) => s.id === id)
  if (!sp || sp.reason) return null
  return { type: 'special', id, ...extra }
}

/** Rooms a hero would rather not walk into: monsters, the traitor, and their doorsteps. */
function danger(v: V): Set<string> {
  const hot = new Set<string>()
  const traitor = v.haunt?.traitor ? v.explorers[v.haunt.traitor] : undefined
  const sources = [...v.monsters.filter((m) => !m.stunned).map((m) => m.tile), ...(traitor && alive(v, traitor.pid) ? [traitor.tile] : [])]
  for (const t of sources) {
    hot.add(t)
    for (const [uid, d] of distances(asState(v), v.tiles[t]!, { monster: true })) if (d <= 1) hot.add(uid)
  }
  return hot
}

/** Step away from danger if we're in it. */
function flee(v: V, from: string, moves: string[], hot: Set<string>): HauntedAction | null {
  if (!hot.has(from)) return null
  const safe = moves.filter((m) => !hot.has(m))
  return safe.length ? { type: 'moveTo', tile: safe[0]! } : null
}

function heroTurn(v: V, me: PlayerId, random: () => number): HauntedAction | null {
  const o = v.options!
  const ex = v.explorers[me]!
  const from = ex.tile
  const n = v.haunt!.number
  const data = v.haunt!.data as Record<string, unknown>
  const hot = danger(v)

  // Cornered by a monster that can be stunned: hit it, which costs it a turn.
  const stunnable = o.attack.find((a) => a.id.startsWith('m:') && v.monsters.find((m) => `m:${m.id}` === a.id && m.canStun && !m.stunned && m.tile === from))
  const canFlee = o.moves.some((m) => !hot.has(m))
  const myMight = EXPLORERS.find((e) => e.id === ex.explorerId)!.traits.might.values[ex.idx.might] ?? 0
  const theirMight = stunnable ? v.monsters.find((m) => `m:${m.id}` === stunnable.id)!.might : 99
  if (stunnable && !canFlee && myMight + (stunnable.weapons.length ? 1 : 0) >= theirMight - 1) {
    const weapon = stunnable.weapons.find((w) => CARD_BY_ID.get(w)?.effect?.kind === 'weapon') ?? null
    return { type: 'attack', target: stunnable.id, weapon }
  }

  if (n === 44) {
    const burning = (t: PlacedTile) => t.flipped === 'burning' || t.tokens.includes('fire')
    const act = special(v, 'setFire')
    if (act) return act
    const run = flee(v, from, o.moves, hot)
    if (run) return run
    const dry = tilesWhere(v, (t) => !burning(t) && !hot.has(t.uid))
    const avoid = new Set([...tilesWhere(v, burning), ...hot])
    const step = stepToward(v, from, o.moves, dry, { avoid }) ?? stepToward(v, from, o.moves, dry, { avoid: hot })
    if (step) return { type: 'moveTo', tile: step }
    return null
  }

  if (n === 28) {
    const traps = ((data.traps as Record<string, number> | undefined) ?? {})[me] ?? 0
    const dynamite = ex.items.some((c) => CARD_BY_ID.get(c)?.effect?.kind === 'dynamite')
    const might = EXPLORERS.find((e) => e.id === ex.explorerId)!.traits.might.values[ex.idx.might] ?? 0
    const bonus = traps * 2 + (dynamite ? 2 : 0)
    const ready = bonus + might >= 9 || (traps > 0 && Number(data.pool ?? 0) === 0)
    const force = ready ? special(v, 'force', { count: traps }) : null
    if (force) return force
    const search = special(v, 'search')
    if (search && !ready) return search
    const shark = new Set(v.monsters.filter((m) => m.kind === 'shark').map((m) => m.tile))
    if (!ready) {
      const run = flee(v, from, o.moves, hot)
      if (run) return run
    }
    const itemRooms = tilesWhere(v, (t) => symbols(t).includes('item') && t.uid !== from && !hot.has(t.uid))
    const target = ready ? shark : itemRooms
    const step = stepToward(v, from, o.moves, target, { avoid: ready ? undefined : hot })
    if (step) return { type: 'moveTo', tile: step }
    if (!ready) return explore(v, me, random)
    return null
  }

  if (n === 30) {
    const altar = tilesWhere(v, (t) => t.tokens.includes('altar'))
    const ceremony = special(v, 'ceremony')
    if (ceremony) return ceremony
    const traitor = v.haunt!.traitor ? v.explorers[v.haunt!.traitor] : undefined
    const hasRing = ex.omens.includes('omenRing')
    if (hasRing && altar.size && traitor && !altar.has(traitor.tile)) {
      const compel = special(v, 'compel')
      if (compel) return compel
    }
    if (!altar.size) return explore(v, me, random)
    // The Ring holder keeps away from the spirit; everyone else heads to the altar.
    if (hasRing && traitor && distTo(v, from, new Set([traitor.tile])) <= 1 && !altar.has(traitor.tile)) {
      const away = o.moves.find((m) => distTo(v, m, new Set([traitor.tile])) > 1)
      if (away) return { type: 'moveTo', tile: away }
    }
    const avoid = hasRing ? new Set([...hot].filter((t) => !altar.has(t))) : undefined
    const step = stepToward(v, from, o.moves, altar, { avoid }) ?? stepToward(v, from, o.moves, altar)
    if (step) return { type: 'moveTo', tile: step }
    return null
  }
  return explore(v, me, random)
}

function traitorTurn(v: V, me: PlayerId): HauntedAction | null {
  const o = v.options!
  const ex = v.explorers[me]!
  const n = v.haunt!.number
  // Loot the Ring off a body if it's visible.
  const ring = o.loot.find((l) => l.card === 'omenRing')
  if (ring) return { type: 'loot', card: ring.card }

  const ringHolder = Object.values(v.explorers).find((e) => e.side === 'hero' && alive(v, e.pid) && e.omens.includes('omenRing'))
  const preferred = n === 30 && ringHolder ? ringHolder.pid : null
  const targets = o.attack.filter((a) => a.id.startsWith('p:') && v.explorers[a.id.slice(2)]?.tile === ex.tile)
  const target = targets.find((a) => a.id === `p:${preferred}`) ?? targets[0]
  if (target) {
    const weapon = target.weapons.find((w) => CARD_BY_ID.get(w)?.effect?.kind === 'weapon') ?? null
    return { type: 'attack', target: target.id, weapon }
  }
  const goal = preferred ? new Set([v.explorers[preferred]!.tile]) : heroTiles(v)
  const avoid = n === 30 ? tilesWhere(v, (t) => t.tokens.includes('altar')) : undefined
  const step = stepToward(v, ex.tile, o.moves, goal, { avoid })
  return step ? { type: 'moveTo', tile: step } : null
}

function monsterTurn(v: V, me: PlayerId): HauntedAction {
  const o = v.options!
  const heroes = heroTiles(v)
  const ringHolder = Object.values(v.explorers).find((e) => e.side === 'hero' && alive(v, e.pid) && e.omens.includes('omenRing'))
  for (const m of o.monsters) {
    if (m.targets.length) {
      const t = m.targets.find((p) => p === ringHolder?.pid) ?? m.targets[0]!
      return { type: 'monsterAttack', monster: m.id, target: `p:${t}` }
    }
  }
  for (const m of o.monsters) {
    if (m.attacked || !m.moves.length) continue
    const mon = v.monsters.find((x) => x.id === m.id)!
    const step = stepToward(v, mon.tile, m.moves, heroes, { monster: true })
    if (step) return { type: 'monsterMove', monster: m.id, tile: step }
  }
  // The creature in haunt 28 can surge to any flooded room near the heroes.
  const music = o.specials.find((s) => s.id === 'music' && !s.reason)
  if (music?.tiles?.options.length) {
    const shark = v.monsters.find((m) => m.kind === 'shark')
    const best = music.tiles.options.reduce((a, b) => (distTo(v, b, heroes, true) < distTo(v, a, heroes, true) ? b : a))
    if (shark && distTo(v, best, heroes, true) < distTo(v, shark.tile, heroes, true)) return { type: 'special', id: 'music', tile: best }
  }
  void me
  return { type: 'endMonsterTurn' }
}

/** Safe "just move the game along" answer, used when a smarter choice was rejected. */
function fallback(v: V, me: PlayerId): HauntedAction | null {
  const p = v.prompt
  if (p) {
    if (p.kind === 'reroll' && p.pid === me) return { type: 'acceptRoll' }
    if (p.kind === 'attackResult' && p.pid === me) return { type: 'steal', card: null }
    if (p.kind === 'chooseTile' && p.pid === me) return { type: 'chooseTile', tile: p.options[0]! }
    return null
  }
  if (v.turn?.pid !== me) return null
  return v.turn.actor === 'monsters' ? { type: 'endMonsterTurn' } : { type: 'endTurn' }
}

export function hauntedBot(v: V, ctx: RuleContext, level: BotLevel, attempt = 0): HauntedAction | null {
  const me = v.me
  if (!me || v.phase === 'over') return null
  const random = ctx.random
  if (attempt > 0) return fallback(v, me)

  if (v.phase === 'setup') {
    if (v.picks[me]) return null
    const taken = new Set(Object.values(v.picks).filter(Boolean).map((id) => EXPLORERS.find((e) => e.id === id)!.colorName))
    const free = EXPLORERS.filter((e) => !taken.has(e.colorName))
    const choice = pick(free, random)
    return choice ? { type: 'pickExplorer', explorerId: choice.id } : null
  }

  if (v.prompt) return answerPrompt(v, me, v.prompt, random)
  const o = v.options
  if (!o || v.turn?.pid !== me) return null
  if (v.turn.actor === 'monsters') return monsterTurn(v, me)

  // Easy bots wander a bit.
  if (level === 'easy' && random() < 0.25) {
    if (o.explore.length) return { type: 'move', dir: pick(o.explore, random)! }
    if (o.moves.length && random() < 0.5) return { type: 'moveTo', tile: pick(o.moves, random)! }
  }
  const heal = healIfHurt(v, me)
  if (heal) return heal

  const ex = v.explorers[me]!
  let action: HauntedAction | null
  if (v.phase === 'haunt' && ex.side === 'traitor') action = traitorTurn(v, me)
  else if (v.phase === 'haunt') action = heroTurn(v, me, random)
  else action = explore(v, me, random)
  return action ?? { type: 'endTurn' }
}
