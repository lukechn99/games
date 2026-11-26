import { describe, expect, it } from 'vitest'
import { hideSeek, seekerCount, decide, phase, START_AMMO, AMMO_PER_FIND, HIDE_MS, SEEK_MS, RESULTS_MS, PROPS, DECOYS, type HideSeekState } from '@/lib/games/hideseek/rules'
import { getGameModule } from '@/lib/games/modules'
import { GAME_VIEWS } from '@/lib/games/ui'

function rng(seed = 1) {
  let x = seed
  return () => ((x = (x * 16807) % 2147483647) - 1) / 2147483646
}
const ctx = (now: number, seed = 1) => ({ now, random: rng(seed) })

function ok(r: ReturnType<typeof hideSeek.action>): HideSeekState {
  if ('error' in r) throw new Error(r.error)
  return r.state
}

const SEEK = 1000 + HIDE_MS + 1   // a moment into the seek phase

describe('hide and seek rules', () => {
  it('is on the game list with a view, bots can sit, one person can start it', () => {
    expect(getGameModule('hideseek')).toBe(hideSeek)
    expect(GAME_VIEWS.hideseek).toBeDefined()
    expect(hideSeek.minPlayers).toBe(1)
    expect(hideSeek.bot).toBeDefined()
  })

  it('deals seekers by room size, at random', () => {
    expect([2, 3, 4, 5, 6, 7, 8, 9, 10].map(seekerCount)).toEqual([1, 1, 1, 2, 2, 2, 3, 3, 3])
    const seen = new Set<string>()
    for (let i = 1; i < 60; i++) {
      const s = hideSeek.setup(['a', 'b', 'c', 'd', 'e', 'f'], ctx(1000, i))
      const seekers = Object.keys(s.members).filter((id) => s.members[id]!.role === 'seeker')
      expect(seekers.length).toBe(2)
      seekers.forEach((id) => seen.add(id))
      for (const id of s.hidersAtStart) expect(PROPS).toContain(s.members[id]!.prop)
    }
    expect(seen.size).toBe(6)
  })

  it('hiders reroll twice, to a different prop each time', () => {
    let s = hideSeek.setup(['a', 'b', 'c', 'd'], ctx(1000, 3))
    const h = s.hidersAtStart[0]!
    const props = [s.members[h]!.prop]
    s = ok(hideSeek.action(s, h, { type: 'reroll' }, ctx(2000)))
    props.push(s.members[h]!.prop)
    s = ok(hideSeek.action(s, h, { type: 'reroll' }, ctx(3000)))
    props.push(s.members[h]!.prop)
    expect(props[1]).not.toBe(props[0])
    expect(props[2]).not.toBe(props[1])
    expect('error' in hideSeek.action(s, h, { type: 'reroll' }, ctx(4000))).toBe(true)
  })

  it('paintballs: none in the hide phase, 100 to spend, +3 for a find', () => {
    let s = hideSeek.setup(['a', 'b', 'c', 'd'], ctx(1000, 5))
    const seeker = Object.keys(s.members).find((id) => s.members[id]!.role === 'seeker')!
    const hider = s.hidersAtStart[0]!
    expect('error' in hideSeek.action(s, seeker, { type: 'shoot' }, ctx(2000))).toBe(true)
    s = ok(hideSeek.action(s, seeker, { type: 'shoot' }, ctx(SEEK)))
    expect(s.members[seeker]!.ammo).toBe(START_AMMO - 1)
    s = ok(hideSeek.action(s, seeker, { type: 'find', hider }, ctx(SEEK + 10)))
    expect(s.members[seeker]!.ammo).toBe(START_AMMO - 1 + AMMO_PER_FIND)
    expect(s.members[hider]).toMatchObject({ role: 'seeker', ammo: START_AMMO })
    expect('error' in hideSeek.action(s, seeker, { type: 'find', hider }, ctx(SEEK + 20))).toBe(true)
  })

  it('hiders drop three decoys of their prop; a seeker painting one pops it', () => {
    let s = hideSeek.setup(['a', 'b', 'c', 'd'], ctx(1000, 5))
    const h = s.hidersAtStart[0]!
    const seeker = Object.keys(s.members).find((id) => s.members[id]!.role === 'seeker')!
    for (let i = 0; i < DECOYS; i++) s = ok(hideSeek.action(s, h, { type: 'decoy', at: [i, 0, 1], q: [0, 0, 0, 1] }, ctx(2000)))
    expect(s.decoys.map((d) => d.prop)).toEqual([s.members[h]!.prop, s.members[h]!.prop, s.members[h]!.prop])
    expect('error' in hideSeek.action(s, h, { type: 'decoy', at: [0, 0, 0], q: [0, 0, 0, 1] }, ctx(2000))).toBe(true)
    expect('error' in hideSeek.action(s, seeker, { type: 'decoy', at: [0, 0, 0], q: [0, 0, 0, 1] }, ctx(2000))).toBe(true)
    expect('error' in hideSeek.action(s, seeker, { type: 'pop', decoy: s.decoys[0]!.id }, ctx(2000))).toBe(true)
    s = ok(hideSeek.action(s, seeker, { type: 'pop', decoy: s.decoys[0]!.id }, ctx(SEEK)))
    expect(s.decoys.length).toBe(DECOYS - 1)
    const next = hideSeek.tick!({ ...s, winner: 'hiders', overAt: SEEK }, ctx(SEEK + RESULTS_MS))
    expect(next.decoys).toEqual([])
  })

  it('a player can act for a bot (the host game plays them)', () => {
    let s = hideSeek.setup(['a', 'bot1', 'bot2', 'bot3'], ctx(1000, 7))
    const seeker = Object.keys(s.members).find((id) => s.members[id]!.role === 'seeker')!
    const actor = seeker === 'a' ? 'bot1' : 'a'
    s = ok(hideSeek.action(s, actor, { type: 'shoot', as: seeker }, ctx(SEEK)))
    expect(s.members[seeker]!.ammo).toBe(START_AMMO - 1)
  })

  it('seekers win when all are found; then a new round deals again', () => {
    let s = hideSeek.setup(['a', 'b', 'c'], ctx(1000, 9))
    const seeker = Object.keys(s.members).find((id) => s.members[id]!.role === 'seeker')!
    for (const h of s.hidersAtStart) s = ok(hideSeek.action(s, seeker, { type: 'find', hider: h }, ctx(SEEK + 5000)))
    expect(s.winner).toBe('seekers')
    expect(s.scores[seeker]).toBe(3 * 2)
    expect(phase(s, SEEK + 6000)).toBe('over')
    const same = hideSeek.tick!(s, ctx(SEEK + 5000 + RESULTS_MS - 1))
    expect(same.round).toBe(1)
    const next = hideSeek.tick!(s, ctx(SEEK + 5000 + RESULTS_MS, 4))
    expect(next.round).toBe(2)
    expect(next.winner).toBeNull()
    expect(next.scores[seeker]).toBe(6)
  })

  it('hiders win when time runs out, scoring for time survived', () => {
    const s = hideSeek.setup(['a', 'b'], ctx(1000, 11))
    const end = 1000 + HIDE_MS + SEEK_MS
    expect(decide(s, end - 1)).toBeNull()
    const done = hideSeek.tick!(s, ctx(end))
    expect(done.winner).toBe('hiders')
    const h = s.hidersAtStart[0]!
    expect(done.scores[h]).toBe(6 + 3)   // 180 s = 6 x 30 s, plus surviving
  })

  it('hiders win when every seeker is out of paint', () => {
    let s = hideSeek.setup(['a', 'b', 'c', 'd'], ctx(1000, 13))
    const seeker = Object.keys(s.members).find((id) => s.members[id]!.role === 'seeker')!
    s = { ...s, members: { ...s.members, [seeker]: { ...s.members[seeker]!, ammo: 1 } } }
    s = ok(hideSeek.action(s, seeker, { type: 'shoot' }, ctx(SEEK)))
    expect(s.winner).toBe('hiders')
  })

  it('a player leaving drops out of the round', () => {
    const s = hideSeek.setup(['a', 'b', 'c'], ctx(1000, 2))
    const left = hideSeek.playerLeft!(s, 'b', ctx(2000))
    expect(left.members.b).toBeUndefined()
    expect(left.seats).toEqual(['a', 'c'])
  })
})
