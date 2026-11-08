import { describe, expect, it } from 'vitest'
import { racing, type RacingState } from '@/lib/games/racing/rules'

const ctx = (now = 1000) => ({ now, random: () => 0.3 })

function ok(r: ReturnType<typeof racing.action>): RacingState {
  if ('error' in r) throw new Error(r.error)
  return r.state
}

/** A new race with the track already picked (Meadow Loop). */
function setup(players: string[]) {
  return ok(racing.action(racing.setup(players, ctx()), players[0]!, { type: 'track', id: 'meadow' }, ctx()))
}

describe('racing rules', () => {
  it('the track is picked first', () => {
    const s = racing.setup(['h', 'g'], ctx())
    expect(s.phase).toBe('track')
    expect('error' in racing.action(s, 'x', { type: 'track', id: 'mine' }, ctx())).toBe(true)
    expect('error' in racing.action(s, 'h', { type: 'track', id: 'moon' } as never, ctx())).toBe(true)
    expect('error' in racing.action(s, 'h', { type: 'pick', chassis: 'frame', tires: 'slicks', driver: 'fox' }, ctx())).toBe(true)
    const t = ok(racing.action(s, 'h', { type: 'track', id: 'mine' }, ctx()))
    expect(t).toMatchObject({ track: 'mine', phase: 'pick' })
  })

  it('starts the countdown once everyone is ready', () => {
    let s = setup(['a', 'b'])
    expect(s.phase).toBe('pick')
    s = ok(racing.action(s, 'a', { type: 'pick', chassis: 'racer', tires: 'knobby', driver: 'deer' }, ctx()))
    expect(s.picks.a).toMatchObject({ chassis: 'racer', tires: 'knobby', driver: 'deer' })
    s = ok(racing.action(s, 'a', { type: 'ready' }, ctx()))
    expect(s.phase).toBe('pick')
    s = ok(racing.action(s, 'b', { type: 'ready' }, ctx(2000)))
    expect(s.phase).toBe('race')
    expect(s.startAt).toBe(13500)
  })

  it('rejects unknown parts and picks after the start', () => {
    const s = setup(['a'])
    expect('error' in racing.action(s, 'a', { type: 'pick', chassis: 'tank', tires: 'slicks', driver: 'fox' }, ctx())).toBe(true)
    const started = ok(racing.action(s, 'a', { type: 'ready' }, ctx()))
    expect('error' in racing.action(started, 'a', { type: 'pick', chassis: 'frame', tires: 'slicks', driver: 'fox' }, ctx())).toBe(true)
  })

  it('records finishes, lets a game report its computer drivers, and ends', () => {
    let s = setup(['a', 'bot'])
    s = ok(racing.action(s, 'bot', { type: 'pick', chassis: 'frame', tires: 'slicks', driver: 'frog', bot: true }, ctx()))
    s = ok(racing.action(s, 'bot', { type: 'ready' }, ctx()))
    s = ok(racing.action(s, 'a', { type: 'ready' }, ctx()))
    expect('error' in racing.action(s, 'bot', { type: 'finish', time: 50, who: 'a' }, ctx())).toBe(true)
    s = ok(racing.action(s, 'a', { type: 'finish', time: 61.25, who: 'bot' }, ctx()))
    expect(s.phase).toBe('race')
    s = ok(racing.action(s, 'a', { type: 'finish', time: 64 }, ctx()))
    expect(s.finish).toEqual({ bot: 61.25, a: 64 })
    expect(s.phase).toBe('done')
    expect(racing.isOver!(s)).toBe(true)
  })

  it('ends the race a while after the first finisher', () => {
    let s = setup(['a', 'b'])
    s = ok(racing.action(s, 'a', { type: 'ready' }, ctx()))
    s = ok(racing.action(s, 'b', { type: 'ready' }, ctx()))
    s = ok(racing.action(s, 'a', { type: 'finish', time: 60 }, ctx(10000)))
    expect(racing.tick!(s, ctx(20000)).phase).toBe('race')
    expect(racing.tick!(s, ctx(41000)).phase).toBe('done')
  })

  it('computer drivers pick a kart and get ready', () => {
    let s = setup(['h', 'bot'])
    const a1 = racing.bot!(racing.view(s, 'bot'), ctx(), 'easy', 0)
    expect(a1?.type).toBe('pick')
    s = ok(racing.action(s, 'bot', a1!, ctx()))
    expect(racing.bot!(racing.view(s, 'bot'), ctx(), 'easy', 0)).toEqual({ type: 'ready' })
  })

  it('runs a Grand Prix: every track in turn, with points carried over', () => {
    let s = ok(racing.action(racing.setup(['a', 'b', 'c'], ctx()), 'a', { type: 'track', id: 'gp' }, ctx()))
    expect(s).toMatchObject({ phase: 'pick', track: 'meadow', cup: { race: 0, points: { a: 0, b: 0, c: 0 } } })
    s = ok(racing.action(s, 'a', { type: 'pick', chassis: 'racer', tires: 'knobby', driver: 'deer' }, ctx()))
    const race = (st: RacingState, times: Record<string, number>) => {
      for (const id of ['a', 'b', 'c']) st = ok(racing.action(st, id, { type: 'ready' }, ctx()))
      for (const [id, t] of Object.entries(times)) st = ok(racing.action(st, id, { type: 'finish', time: t }, ctx(5000)))
      return st.phase === 'done' ? st : racing.tick!(st, ctx(60000))
    }
    // Race 1: c, a, b.
    s = race(s, { c: 60, a: 61, b: 62 })
    expect(s.phase).toBe('done')
    expect(s.cup!.points).toEqual({ c: 15, a: 12, b: 10 })
    expect(racing.isOver!(s)).toBe(false)
    expect('error' in racing.action(s, 'a', { type: 'track', id: 'mine' }, ctx())).toBe(true)
    s = ok(racing.action(s, 'b', { type: 'next' }, ctx()))
    expect(s).toMatchObject({ phase: 'pick', track: 'mine', finish: {}, cup: { race: 1 } })
    expect(s.picks.a).toMatchObject({ chassis: 'racer', ready: false })   // builds kept
    // Race 2: a wins, b doesn't finish.
    s = race(s, { a: 70, c: 75 })
    expect(s.cup!.points).toEqual({ c: 27, a: 27, b: 10 })
    expect(s.cup!.last).toEqual({ a: 15, c: 12, b: 0 })
    s = ok(racing.action(s, 'a', { type: 'next' }, ctx()))
    expect(s.track).toBe('frost')
    s = race(s, { b: 50, a: 51, c: 52 })
    expect(s.cup!.points).toEqual({ a: 39, c: 37, b: 25 })
    expect(racing.isOver!(s)).toBe(true)
    expect('error' in racing.action(s, 'a', { type: 'next' }, ctx())).toBe(true)
  })
})
