import { describe, expect, it } from 'vitest'
import type { RuleContext } from '@/lib/engine/types'
import { CARD_BY_ID } from '@/lib/games/haunted/data/cards'
import { EXPLORERS } from '@/lib/games/haunted/data/explorers'
import { ROOM_TILES } from '@/lib/games/haunted/data/tiles'
import { neighbors, placedByTileId } from '@/lib/games/haunted/engine/board'
import { env, value } from '@/lib/games/haunted/engine/core'
import { startHaunt } from '@/lib/games/haunted/engine/haunt'
import { settle } from '@/lib/games/haunted/engine/play'
import { hauntedHouse, type HauntedView } from '@/lib/games/haunted/rules'
import type { HauntedAction, HauntedState, Trait } from '@/lib/games/haunted/types'

function seeded(seed: number): () => number {
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

function ctxFor(random: () => number): RuleContext {
  return { now: 0, random }
}

function ok(s: HauntedState, pid: string, a: HauntedAction, random: () => number): HauntedState {
  const r = hauntedHouse.action(s, pid, a, ctxFor(random))
  if ('error' in r) throw new Error(`${pid} ${JSON.stringify(a)}: ${r.error}`)
  return r.state
}

const SEATS = ['a', 'b', 'c', 'd']

function started(seed = 1, n = 4, scenario = 'missingFriend'): { s: HauntedState; rnd: () => number } {
  const rnd = seeded(seed)
  env.ctx = ctxFor(rnd)
  let s = hauntedHouse.setup(SEATS.slice(0, n), ctxFor(rnd))
  const picks = ['vera', 'milo', 'rosa', 'dex', 'harold', 'wren']
  SEATS.slice(0, n).forEach((p, i) => (s = ok(s, p, { type: 'pickExplorer', explorerId: picks[i]! }, rnd)))
  s = ok(s, 'a', { type: 'pickScenario', scenarioId: scenario }, rnd)
  s = ok(s, 'a', { type: 'begin' }, rnd)
  return { s, rnd }
}

describe('data', () => {
  it('has 12 explorers with 8-step tracks and starting values on the track', () => {
    expect(EXPLORERS).toHaveLength(12)
    for (const e of EXPLORERS) {
      for (const t of ['speed', 'might', 'sanity', 'knowledge'] as Trait[]) {
        expect(e.traits[t].values).toHaveLength(8)
        expect(e.traits[t].start).toBeGreaterThanOrEqual(0)
        expect(e.traits[t].start).toBeLessThan(8)
      }
    }
    expect(ROOM_TILES).toHaveLength(42)
  })
})

describe('setup and exploring', () => {
  it('rejects two explorers of the same color', () => {
    const rnd = seeded(1)
    let s = hauntedHouse.setup(['a', 'b', 'c'], ctxFor(rnd))
    s = ok(s, 'a', { type: 'pickExplorer', explorerId: 'vera' }, rnd)
    const r = hauntedHouse.action(s, 'b', { type: 'pickExplorer', explorerId: 'odessa' }, ctxFor(rnd))
    expect(r).toEqual({ error: 'Someone already plays the blue board.' })
  })

  it('starts everyone in the Entrance Hall with starting traits', () => {
    const { s } = started()
    const entrance = placedByTileId(s, 'entrance')!
    for (const ex of Object.values(s.explorers)) {
      expect(ex.tile).toBe(entrance.uid)
      expect(ex.idx.speed).toBe(EXPLORERS.find((e) => e.id === ex.explorerId)!.traits.speed.start)
    }
    expect(s.phase).toBe('explore')
    expect(s.turn?.movesLeft).toBe(value(s.explorers[s.turn!.pid]!, 'speed'))
  })

  it('walks through connected doors and spends movement', () => {
    const { s, rnd } = started()
    const pid = s.turn!.pid
    const hallway = placedByTileId(s, 'hallway')!
    const s2 = ok(s, pid, { type: 'moveTo', tile: hallway.uid }, rnd)
    expect(s2.explorers[pid]!.tile).toBe(hallway.uid)
    expect(s2.turn!.movesLeft).toBe(s.turn!.movesLeft - 1)
  })

  it('discovering a room asks for a rotation, then ends the turn after resolving cards', () => {
    const started_ = started(3)
    let s = started_.s
    const rnd = started_.rnd
    const pid = s.turn!.pid
    s = ok(s, pid, { type: 'move', dir: 3 }, rnd) // west door of the Entrance Hall
    expect(s.prompt?.kind).toBe('place')
    const p = s.prompt as Extract<HauntedState['prompt'], { kind: 'place' }>
    s = ok(s, pid, { type: 'place', rot: p.options[0]! }, rnd)
    expect(Object.keys(s.tiles)).toHaveLength(6)
    // Resolve whatever cards were drawn.
    for (let i = 0; i < 20 && s.prompt; i++) s = answerAny(s, rnd)
    expect(s.turn!.pid === pid && s.phase === 'explore').toBe(false)
  })

  it('upper landing connects to the ground floor staircase both ways', () => {
    const { s } = started()
    const up = placedByTileId(s, 'upperLanding')!
    const stairs = placedByTileId(s, 'groundStairs')!
    expect(neighbors(s, up)).toContain(stairs)
    expect(neighbors(s, stairs)).toContain(up)
    expect(neighbors(s, stairs).map((t) => t.tileId)).not.toContain('basementLanding')
  })
})

describe('damage', () => {
  it("before the haunt, traits stop at critical and can't kill", () => {
    const started_ = started()
    let s = started_.s
    const rnd = started_.rnd
    const pid = s.turn!.pid
    s.explorers[pid]!.idx.might = 0
    s.explorers[pid]!.idx.speed = 0
    env.ctx = ctxFor(rnd)
    s.prompt = { kind: 'damage', pid, type: 'physical', amount: 3, reason: 'test' }
    s = ok(s, pid, { type: 'allocate', split: { might: 2, speed: 1 } }, rnd)
    expect(s.explorers[pid]!.dead).toBe(false)
    expect(s.explorers[pid]!.idx.might).toBe(0)
  })
})

function forceHaunt(seed: number, scenario: string, omen: string): { s: HauntedState; rnd: () => number } {
  const { s, rnd } = started(seed, 4, scenario)
  env.ctx = ctxFor(rnd)
  const pid = s.turn!.pid
  s.explorers[pid]!.omens.push(omen)
  startHaunt(s, pid, omen)
  settle(s)
  return { s, rnd }
}

describe('haunts', () => {
  it('haunt 44: traitor is left of the revealer, mannequins on landings, revealer room burning', () => {
    const { s } = forceHaunt(5, 'missingFriend', 'omenMask')
    expect(s.haunt!.number).toBe(44)
    const revealer = s.haunt!.revealer
    const i = s.order.indexOf(revealer)
    expect(s.haunt!.traitor).toBe(s.order[(i + 1) % s.order.length])
    expect(s.monsters).toHaveLength(2)
    const t = s.tiles[s.explorers[revealer]!.tile]!
    expect(t.flipped === 'burning' || t.tokens.includes('fire')).toBe(true)
    expect(s.prompt?.kind).toBe('haunt')
  })

  it('haunt 28: the traitor is swallowed and the creature appears', () => {
    const { s } = forceHaunt(6, 'ghostHunters', 'omenIdol')
    expect(s.haunt!.number).toBe(28)
    const t = s.explorers[s.haunt!.traitor!]!
    expect(t.removed).toBe(true)
    expect(t.items).toHaveLength(0)
    expect(s.monsters[0]!.kind).toBe('shark')
  })

  it('unbuilt haunts are replaced by a stand-in with its own traitor rule', () => {
    const { s } = forceHaunt(7, 'curse', 'omenIdol')
    expect([28, 44]).toContain(s.haunt!.number)
    expect(s.haunt!.substitute).toBe(true)
    expect(s.haunt!.chartNumber).toBe(23)
  })

  it('haunt 30: traitor has lowest sanity excluding the revealer, and hero omens are hidden from them', () => {
    const { s } = forceHaunt(8, 'missingFriend', 'omenRing')
    expect(s.haunt!.number).toBe(30)
    const traitor = s.haunt!.traitor!
    expect(traitor).not.toBe(s.haunt!.revealer)
    const revealer = s.haunt!.revealer
    expect(s.explorers[revealer]!.omens).toContain('omenRing')
    const view = hauntedHouse.view(s, traitor) as HauntedView
    expect(view.explorers[revealer]!.omens).toContain('hidden')
    expect(view.haunt!.brief!.goal).toMatch(/Ring/)
    const heroView = hauntedHouse.view(s, revealer) as HauntedView
    expect(heroView.haunt!.brief!.goal).toMatch(/ceremony/)
  })

  it('haunt 30: the traitor wins on getting the Ring', () => {
    const { s } = forceHaunt(9, 'missingFriend', 'omenRing')
    const ring = s.explorers[s.haunt!.revealer]!
    ring.omens = ring.omens.filter((c) => c !== 'omenRing')
    s.explorers[s.haunt!.traitor!]!.omens.push('omenRing')
    settle(s)
    expect(s.phase).toBe('over')
    expect(s.winner).toBe('traitor')
  })
})

/* ------------------------------------------------------------------ */
/*  Fuzz: random legal play                                            */
/* ------------------------------------------------------------------ */

function answerAny(s: HauntedState, rnd: () => number): HauntedState {
  const p = s.prompt!
  const pick = <T,>(xs: T[]) => xs[Math.floor(rnd() * xs.length)]!
  const tryAll = (pid: string, actions: HauntedAction[]) => {
    for (const a of actions) {
      const r = hauntedHouse.action(s, pid, a, ctxFor(rnd))
      if (!('error' in r)) return r.state
    }
    throw new Error(`stuck on prompt ${JSON.stringify(p)}`)
  }
  switch (p.kind) {
    case 'place':
      return ok(s, p.pid, { type: 'place', rot: pick(p.options) }, rnd)
    case 'damage': {
      const ex = s.explorers[p.pid]!
      const traits: Trait[] = p.type === 'physical' ? ['speed', 'might'] : p.type === 'mental' ? ['sanity', 'knowledge'] : ['speed', 'might', 'sanity', 'knowledge']
      if (ex.items.includes('brooch')) traits.splice(0, traits.length, 'speed', 'might', 'sanity', 'knowledge')
      const tries: HauntedAction[] = []
      for (let i = 0; i <= p.amount; i++) {
        for (let a = 0; a < traits.length; a++) {
          for (let b = 0; b < traits.length; b++) {
            const split: Partial<Record<Trait, number>> = {}
            split[traits[a]!] = (split[traits[a]!] ?? 0) + i
            split[traits[b]!] = (split[traits[b]!] ?? 0) + (p.amount - i)
            tries.push({ type: 'allocate', split })
          }
        }
      }
      return tryAll(p.pid, tries)
    }
    case 'event':
      return ok(s, p.pid, { type: 'rollEvent' }, rnd)
    case 'card':
      return ok(s, p.pid, { type: 'continue' }, rnd)
    case 'reroll':
      return ok(s, p.pid, { type: 'acceptRoll' }, rnd)
    case 'gainChoice':
      return ok(s, p.pid, { type: 'gainPick', trait: pick(p.traits) }, rnd)
    case 'trade':
      return ok(s, p.to, { type: 'answerTrade', accept: rnd() < 0.5 }, rnd)
    case 'chooseTile':
      return ok(s, p.pid, { type: 'chooseTile', tile: pick(p.options) }, rnd)
    case 'haunt':
      return ok(s, s.haunt!.revealer, { type: 'continue' }, rnd)
    case 'elevator':
      return ok(s, p.pid, { type: 'elevatorRegion', region: pick(['upper', 'ground', 'basement'] as const) }, rnd)
    case 'attackResult':
      return ok(s, p.pid, { type: 'steal', card: null }, rnd)
  }
}

function randomAction(s: HauntedState, rnd: () => number): HauntedState {
  const pid = s.turn!.pid
  const v = hauntedHouse.view(s, pid) as HauntedView
  const o = v.options
  if (!o) throw new Error(`no options for ${pid} ${JSON.stringify(s.turn)}`)
  const pick = <T,>(xs: T[]) => xs[Math.floor(rnd() * xs.length)]!
  const choices: HauntedAction[] = []
  if (s.turn!.actor === 'monsters') {
    for (const m of o.monsters) {
      for (const t of m.targets) choices.push({ type: 'monsterAttack', monster: m.id, target: `p:${t}` })
      for (const t of m.moves) choices.push({ type: 'monsterMove', monster: m.id, tile: t })
    }
    for (const sp of o.specials) if (!sp.reason && sp.tiles?.options.length) choices.push({ type: 'special', id: sp.id, tile: pick(sp.tiles.options) })
    if (!choices.length || rnd() < 0.15) return ok(s, pid, { type: 'endMonsterTurn' }, rnd)
    return ok(s, pid, pick(choices), rnd)
  }
  for (const d of o.explore) choices.push({ type: 'move', dir: d }, { type: 'move', dir: d })
  for (const m of o.moves) choices.push({ type: 'moveTo', tile: m })
  for (const a of o.attack) choices.push({ type: 'attack', target: a.id, weapon: a.weapons[0] ?? null })
  for (const l of o.loot) choices.push({ type: 'loot', card: l.card })
  for (const sp of o.specials) {
    if (sp.reason) continue
    choices.push({ type: 'special', id: sp.id, count: sp.count?.max, tile: sp.tiles?.options[0] })
  }
  if (o.canLift) choices.push({ type: 'special', id: 'lift' })
  const me = s.explorers[pid]!
  for (const c of me.items) {
    const k = CARD_BY_ID.get(c)?.effect?.kind
    if (k === 'mirror' || k === 'medicine' || k === 'firstAid' || k === 'stopwatch') choices.push({ type: 'useItem', card: c })
  }
  if (!choices.length || rnd() < 0.1) return ok(s, pid, { type: 'endTurn' }, rnd)
  const a = pick(choices)
  const r = hauntedHouse.action(s, pid, a, ctxFor(rnd))
  if ('error' in r) return ok(s, pid, { type: 'endTurn' }, rnd)
  return r.state
}

describe('fuzz', () => {
  const scenarios = ['curse', 'ghostHunters', 'openHouse', 'invitation', 'missingFriend']
  it('plays 150 random games without crashing or getting stuck', () => {
    const results = { heroes: 0, traitor: 0, unfinished: 0, haunts: new Set<number>() }
    for (let seed = 1; seed <= 150; seed++) {
      const n = 3 + (seed % 4)
      const started_ = started(seed, Math.min(n, 4), scenarios[seed % scenarios.length]!)
      let s = started_.s
      const rnd = started_.rnd
      let steps = 0
      while (s.phase !== 'over' && steps < 4000) {
        steps++
        s = s.prompt ? answerAny(s, rnd) : randomAction(s, rnd)
        // Invariants
        expect(s.turn).not.toBeNull()
        for (const ex of Object.values(s.explorers)) {
          if (!ex.dead) for (const t of ['speed', 'might', 'sanity', 'knowledge'] as Trait[]) expect(ex.idx[t]).toBeGreaterThanOrEqual(0)
          expect(s.tiles[ex.tile]).toBeDefined()
        }
      }
      if (s.haunt) results.haunts.add(s.haunt.number)
      if (s.phase === 'over') results[s.winner!]++
      else results.unfinished++
    }
    console.log('fuzz results', { ...results, haunts: [...results.haunts] })
    expect(results.heroes + results.traitor).toBeGreaterThan(50)
    expect(results.haunts.size).toBe(3)
  }, 120_000)
})

describe('rules visibility', () => {
  it('shares public haunt rules with everyone, and the other book only in teaching mode', () => {
    const { s } = forceHaunt(5, 'missingFriend', 'omenMask')
    const hero = s.haunt!.revealer
    const traitor = s.haunt!.traitor!
    const hv = hauntedHouse.view(s, hero) as HauntedView
    const tv = hauntedHouse.view(s, traitor) as HauntedView
    expect(hv.haunt!.shared.length).toBeGreaterThan(0)
    expect(tv.haunt!.shared).toEqual(hv.haunt!.shared)
    expect(tv.haunt!.otherBrief).toBeNull()
    s.openBooks = true
    const tv2 = hauntedHouse.view(s, traitor) as HauntedView
    expect(tv2.haunt!.otherBrief!.goal).toMatch(/Burn the whole house/)
  })

  it('only the host can turn on teaching mode', () => {
    const rnd = seeded(3)
    const s = hauntedHouse.setup(['a', 'b', 'c'], ctxFor(rnd))
    expect(hauntedHouse.action(s, 'b', { type: 'setOpenBooks', on: true }, ctxFor(rnd))).toEqual({ error: 'The host chooses this.' })
    const r = hauntedHouse.action(s, 'a', { type: 'setOpenBooks', on: true }, ctxFor(rnd))
    expect('state' in r && r.state.openBooks).toBe(true)
  })
})
