import { describe, expect, it } from 'vitest'
import { racing, type RacingState } from '@/lib/games/racing/rules'

const ctx = (now = 1000) => ({ now, random: () => 0.3 })

function ok(r: ReturnType<typeof racing.action>): RacingState {
  if ('error' in r) throw new Error(r.error)
  return r.state
}

describe('racing rules', () => {
  it('starts the countdown once everyone is ready', () => {
    let s = racing.setup(['a', 'b'], ctx())
    expect(s.phase).toBe('pick')
    s = ok(racing.action(s, 'a', { type: 'pick', chassis: 'racer', tires: 'knobby', driver: 'deer' }, ctx()))
    expect(s.picks.a).toMatchObject({ chassis: 'racer', tires: 'knobby', driver: 'deer' })
    s = ok(racing.action(s, 'a', { type: 'ready' }, ctx()))
    expect(s.phase).toBe('pick')
    s = ok(racing.action(s, 'b', { type: 'ready' }, ctx(2000)))
    expect(s.phase).toBe('race')
    expect(s.startAt).toBe(7000)
  })

  it('rejects unknown parts and picks after the start', () => {
    const s = racing.setup(['a'], ctx())
    expect('error' in racing.action(s, 'a', { type: 'pick', chassis: 'tank', tires: 'slicks', driver: 'fox' }, ctx())).toBe(true)
    const started = ok(racing.action(s, 'a', { type: 'ready' }, ctx()))
    expect('error' in racing.action(started, 'a', { type: 'pick', chassis: 'frame', tires: 'slicks', driver: 'fox' }, ctx())).toBe(true)
  })

  it('records finishes, lets a game report its computer drivers, and ends', () => {
    let s = racing.setup(['a', 'bot'], ctx())
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
    let s = racing.setup(['a', 'b'], ctx())
    s = ok(racing.action(s, 'a', { type: 'ready' }, ctx()))
    s = ok(racing.action(s, 'b', { type: 'ready' }, ctx()))
    s = ok(racing.action(s, 'a', { type: 'finish', time: 60 }, ctx(10000)))
    expect(racing.tick!(s, ctx(20000)).phase).toBe('race')
    expect(racing.tick!(s, ctx(41000)).phase).toBe('done')
  })

  it('computer drivers pick a kart and get ready', () => {
    let s = racing.setup(['h', 'bot'], ctx())
    const a1 = racing.bot!(racing.view(s, 'bot'), ctx(), 'easy', 0)
    expect(a1?.type).toBe('pick')
    s = ok(racing.action(s, 'bot', a1!, ctx()))
    expect(racing.bot!(racing.view(s, 'bot'), ctx(), 'easy', 0)).toEqual({ type: 'ready' })
  })
})
