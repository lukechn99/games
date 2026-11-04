import { describe, expect, it } from 'vitest'
import type { BotLevel, RuleContext } from '@/lib/engine/types'
import { secretHitler, type SHState, type SHAction } from '@/lib/games/secrethitler/rules'

function seeded(seed: number) {
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = Math.imul(a ^ (a >>> 15), a | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}
const ctx = (random: () => number): RuleContext => ({ now: 0, random })
const ids = (n: number) => Array.from({ length: n }, (_, i) => `p${i}`)

function must(s: SHState, pid: string, a: SHAction, c: RuleContext): SHState {
  const r = secretHitler.action(s, pid, a, c)
  if ('error' in r) throw new Error(`${pid} ${JSON.stringify(a)}: ${r.error}`)
  return r.state
}

/** Every bot gets a turn to act; returns the final state. */
function playOut(n: number, seed: number, level: BotLevel = 'medium') {
  const rnd = seeded(seed)
  const c = ctx(rnd)
  let s = secretHitler.setup(ids(n), c)
  for (let step = 0; step < 4000 && s.phase !== 'over'; step++) {
    let acted = false
    for (const pid of s.seats) {
      const a = secretHitler.bot!(secretHitler.view(s, pid), c, level, 0)
      if (!a) continue
      const r = secretHitler.action(s, pid, a, c)
      if ('error' in r) throw new Error(`${s.phase} ${pid} ${JSON.stringify(a)}: ${r.error}`)
      s = r.state
      acted = true
      break
    }
    if (!acted) throw new Error(`stuck in ${s.phase}`)
    // Policies are never lost or duplicated.
    const total = s.deck.length + s.discard.length + s.hand.length + s.liberal + s.fascist
    expect(total).toBe(17)
  }
  return s
}

describe('secret hitler rules', () => {
  it('deals the right roles for every player count', () => {
    for (let n = 5; n <= 10; n++) {
      const s = secretHitler.setup(ids(n), ctx(seeded(n)))
      const roles = Object.values(s.roles)
      expect(roles.filter((r) => r === 'hitler')).toHaveLength(1)
      expect(roles.filter((r) => r === 'fascist')).toHaveLength(n <= 6 ? 1 : n <= 8 ? 2 : 3)
      expect(s.deck).toHaveLength(17)
    }
  })

  it('hides roles: Liberals see only themselves; Hitler sees the team only at 5–6', () => {
    for (const n of [5, 7]) {
      const s = secretHitler.setup(ids(n), ctx(seeded(3)))
      const lib = s.seats.find((id) => s.roles[id] === 'liberal')!
      const fas = s.seats.find((id) => s.roles[id] === 'fascist')!
      const hit = s.seats.find((id) => s.roles[id] === 'hitler')!
      expect(Object.keys(secretHitler.view(s, lib).known)).toEqual([lib])
      expect(Object.keys(secretHitler.view(s, fas).known)).toHaveLength(n <= 6 ? 2 : 3)
      expect(Object.keys(secretHitler.view(s, hit).known).length).toBe(n <= 6 ? 2 : 1)
      expect(secretHitler.view(s, null).known).toEqual({})
    }
  })

  it('enforces term limits and counts a failed election', () => {
    const c = ctx(seeded(9))
    let s = secretHitler.setup(ids(7), c)
    const pres = s.president
    expect(secretHitler.action(s, pres, { type: 'nominate', target: pres }, c)).toHaveProperty('error')
    const chan = s.seats.find((id) => id !== pres)!
    s = must(s, pres, { type: 'nominate', target: chan }, c)
    for (const id of s.seats) s = must(s, id, { type: 'vote', ja: false }, c)
    expect(s.tracker).toBe(1)
    expect(s.president).not.toBe(pres)
    // Passing a government makes both ineligible next time (7 players).
    const p2 = s.president
    const c2 = s.seats.find((id) => id !== p2)!
    s = must(s, p2, { type: 'nominate', target: c2 }, c)
    for (const id of s.seats) s = must(s, id, { type: 'vote', ja: true }, c)
    expect(s.phase).toBe('president')
    s = must(s, p2, { type: 'discard', index: 0 }, c)
    s = must(s, c2, { type: 'enact', index: 0 }, c)
    expect(s.tracker).toBe(0)
    if (s.phase === 'nominate') {
      expect(secretHitler.view(s, s.president).eligible).not.toContain(c2)
      expect(secretHitler.view(s, s.president).eligible).not.toContain(p2)
    }
  })

  it('enacts the top policy after three failed elections and resets term limits', () => {
    const c = ctx(seeded(4))
    let s = secretHitler.setup(ids(5), c)
    const top = s.deck[0]
    for (let i = 0; i < 3; i++) {
      const pres = s.president
      s = must(s, pres, { type: 'nominate', target: secretHitler.view(s, pres).eligible[0]! }, c)
      for (const id of s.seats) s = must(s, id, { type: 'vote', ja: false }, c)
    }
    expect(s.tracker).toBe(0)
    expect(top === 'L' ? s.liberal : s.fascist).toBe(1)
    expect(s.lastChancellor).toBeNull()
  })

  it('Hitler elected Chancellor after three Fascist policies wins for the Fascists', () => {
    const c = ctx(seeded(5))
    let s = secretHitler.setup(ids(7), c)
    s = { ...s, fascist: 3 }
    const hitler = s.seats.find((id) => s.roles[id] === 'hitler')!
    // Find a president who isn't Hitler.
    while (s.president === hitler) s = { ...s, presIdx: (s.presIdx + 1) % 7, president: s.seats[(s.presIdx + 1) % 7]! }
    s = must(s, s.president, { type: 'nominate', target: hitler }, c)
    for (const id of s.seats) s = must(s, id, { type: 'vote', ja: true }, c)
    expect(s.winner).toBe('fascist')
  })

  it('executing Hitler wins for the Liberals; special election resumes the order', () => {
    const c = ctx(seeded(6))
    let s = secretHitler.setup(ids(7), c)
    const hitler = s.seats.find((id) => s.roles[id] === 'hitler')!
    const presIdx = s.seats.findIndex((id) => id !== hitler)
    s = { ...s, presIdx, president: s.seats[presIdx]!, phase: 'power', power: 'special' }
    const target = s.seats[(presIdx + 3) % 7]!
    s = must(s, s.president, { type: 'power', target }, c)
    expect(s.president).toBe(target)
    // After the special President's turn, the seat after the caller is next.
    const s2 = { ...s, phase: 'power' as const, power: 'execute' as const }
    const victim = s2.seats.find((id) => id !== target && id !== hitler)!
    const after = must(s2, target, { type: 'power', target: victim }, c)
    const expectedIdx = [1, 2, 3].map((d) => (presIdx + d) % 7).find((i) => !after.dead.includes(after.seats[i]!))!
    expect(after.presIdx).toBe(expectedIdx)
    const s3 = { ...s, phase: 'power' as const, power: 'execute' as const }
    expect(must(s3, target === hitler ? s.seats[presIdx]! : target, { type: 'power', target: hitler }, c).winner).toBe('liberal')
  })
})

describe('secret hitler bots', () => {
  it('finish games at every player count and level without illegal moves', () => {
    const wins = { liberal: 0, fascist: 0 }
    for (let n = 5; n <= 10; n++) {
      for (const level of ['easy', 'medium', 'hard'] as const) {
        for (let seed = 0; seed < 12; seed++) {
          const s = playOut(n, seed * 31 + n, level)
          expect(s.phase).toBe('over')
          wins[s.winner!]++
        }
      }
    }
    console.log('secret hitler bot sims', wins)
    // Both teams should win a real share of the time.
    expect(wins.liberal).toBeGreaterThan(30)
    expect(wins.fascist).toBeGreaterThan(30)
  })
})
