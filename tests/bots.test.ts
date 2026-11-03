import { describe, expect, it } from 'vitest'
import type { BotLevel, RuleContext } from '@/lib/engine/types'
import { applyAction, botStep, createRoom } from '@/lib/engine/room'
import { getGameModule } from '@/lib/games/modules'
import { hauntedHouse } from '@/lib/games/haunted/rules'
import type { HauntedState } from '@/lib/games/haunted/types'

function seeded(seed: number) {
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = Math.imul(a ^ (a >>> 15), a | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

const ctxOf = (random: () => number): RuleContext => ({ now: 0, random })

describe('room engine bots', () => {
  it('adds bots, seats them in games that support bots, and plays them', () => {
    const rnd = seeded(1)
    let room = createRoom('ABCDE', { id: 'host', name: 'Host' }, 0)
    const add = (level: BotLevel) => {
      const r = applyAction(room, 'host', { type: 'addBot', level }, ctxOf(rnd), getGameModule)
      if ('error' in r) throw new Error(r.error)
      room = r.state
    }
    add('hard')
    expect(room.players[1]!.bot).toEqual({ level: 'hard' })
    for (const a of [{ type: 'selectGame', gameId: 'fourinarow' }, { type: 'startGame' }] as const) {
      const r = applyAction(room, 'host', a, ctxOf(rnd), getGameModule)
      if ('error' in r) throw new Error(r.error)
      room = r.state
    }
    expect(room.game!.seats).toHaveLength(2)
    // Whoever's turn it is, the bot answers when it's the bot's.
    const before = room.version
    const next = botStep(room, ctxOf(rnd), getGameModule)
    const st = room.game!.state as { turn: number; players: string[] }
    if (st.players[st.turn] === room.players[1]!.id) expect(next!.version).toBeGreaterThan(before)
    else expect(next).toBeNull()
  })

  it("doesn't seat bots in Spyfall", () => {
    const rnd = seeded(2)
    let room = createRoom('ABCDE', { id: 'host', name: 'Host' }, 0)
    for (let i = 0; i < 3; i++) {
      const r = applyAction(room, 'host', { type: 'addBot', level: 'easy' }, ctxOf(rnd), getGameModule)
      if (!('error' in r)) room = r.state
    }
    const sel = applyAction(room, 'host', { type: 'selectGame', gameId: 'spyfall' }, ctxOf(rnd), getGameModule)
    if ('error' in sel) throw new Error(sel.error)
    const start = applyAction(sel.state, 'host', { type: 'startGame' }, ctxOf(rnd), getGameModule)
    expect(start).toEqual({ error: 'Spyfall needs at least 3 connected players.' })
  })
})

describe('haunted house bots', () => {
  function playAllBots(seed: number, n: number, scenario: string) {
    const rnd = seeded(seed)
    const ctx = ctxOf(rnd)
    const seats = ['host', ...Array.from({ length: n - 1 }, (_, i) => `bot${i}`)]
    let s = hauntedHouse.setup(seats, ctx)
    const levels: BotLevel[] = ['easy', 'medium', 'hard']
    const step = (pid: string, a: unknown) => {
      const r = hauntedHouse.action(s, pid, a as never, ctx)
      if ('error' in r) return false
      s = r.state
      return true
    }
    let steps = 0
    while (s.phase !== 'over' && steps < 6000) {
      steps++
      if (s.phase === 'setup') {
        for (const p of seats) {
          const a = hauntedHouse.bot!(hauntedHouse.view(s, p), ctx, 'medium', 0)
          if (a) step(p, a)
        }
        step('host', { type: 'pickScenario', scenarioId: scenario })
        step('host', { type: 'begin' })
        continue
      }
      if (s.prompt?.kind === 'haunt') {
        step('host', { type: 'continue' })
        continue
      }
      let moved = false
      for (const [i, p] of seats.entries()) {
        for (let attempt = 0; attempt < 3 && !moved; attempt++) {
          const a = hauntedHouse.bot!(hauntedHouse.view(s, p), ctx, levels[i % 3]!, attempt)
          if (!a) break
          moved = step(p, a)
        }
        if (moved) break
      }
      if (!moved) throw new Error(`stuck (seed ${seed}): prompt=${JSON.stringify(s.prompt)} turn=${JSON.stringify(s.turn)}`)
    }
    return { s: s as HauntedState, steps }
  }

  it('bots finish full games without getting stuck', () => {
    const scenarios = ['missingFriend', 'ghostHunters', 'curse', 'openHouse', 'invitation']
    const out = { heroes: 0, traitor: 0, unfinished: 0, byHaunt: {} as Record<number, { heroes: number; traitor: number }> }
    for (let seed = 1; seed <= 60; seed++) {
      const { s } = playAllBots(seed, 3 + (seed % 4), scenarios[seed % 5]!)
      if (s.phase !== 'over') {
        out.unfinished++
        continue
      }
      out[s.winner!]++
      const h = (out.byHaunt[s.haunt!.number] ??= { heroes: 0, traitor: 0 })
      h[s.winner!]++
    }
    console.log('bot games', JSON.stringify(out))
    expect(out.unfinished).toBeLessThanOrEqual(3)
    expect(out.heroes).toBeGreaterThan(0)
  }, 300_000)
})
