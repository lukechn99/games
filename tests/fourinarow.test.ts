import { describe, expect, it } from 'vitest'
import { fourInARow, type FourState } from '@/lib/games/fourinarow/rules'

const ctx = (r = 0) => ({ now: 0, random: () => r })

function play(cols: number[], first: 0 | 1 = 0) {
  let s = fourInARow.setup(['a', 'b'], ctx(first === 0 ? 0 : 0.9))
  for (const c of cols) {
    const pid = s.players[s.turn]
    const r = fourInARow.action(s, pid, { type: 'drop', col: c }, ctx())
    if ('error' in r) throw new Error(r.error)
    s = r.state
  }
  return s
}

describe('four in a row', () => {
  it('stacks discs and alternates turns', () => {
    const s = play([3, 3])
    expect(s.cols[3]).toEqual([0, 1])
    expect(s.turn).toBe(0)
  })

  it('detects horizontal, vertical and diagonal wins', () => {
    expect(play([0, 0, 1, 1, 2, 2, 3]).winner).toBe(0)
    expect(play([0, 1, 0, 1, 0, 1, 0]).winner).toBe(0)
    // diagonal up-right for red: (0,0) (1,1) (2,2) (3,3)
    expect(play([0, 1, 1, 2, 2, 3, 2, 3, 3, 6, 3]).winner).toBe(0)
  })

  it('rejects out-of-turn moves and full columns', () => {
    const s = play([0, 0, 0, 0, 0, 0])
    expect(fourInARow.action(s, s.players[s.turn], { type: 'drop', col: 0 }, ctx())).toEqual({ error: 'That column is full.' })
    expect(fourInARow.action(s, s.players[1 - s.turn]!, { type: 'drop', col: 1 }, ctx())).toEqual({ error: "It's not your turn." })
  })

  it('calls a draw on a full board with no line', () => {
    // A known drawn fill order: columns in pairs shifted so no four line up.
    const order = [0, 1, 0, 1, 0, 1, 1, 0, 1, 0, 1, 0, 2, 3, 2, 3, 2, 3, 3, 2, 3, 2, 3, 2, 4, 5, 4, 5, 4, 5, 5, 4, 5, 4, 5, 4, 6, 6, 6, 6, 6, 6]
    const s = play(order)
    expect(s.winner).toBeNull()
    expect(s.draw).toBe(true)
  })

  it('the remaining player wins if the other leaves', () => {
    const s = fourInARow.playerLeft!(play([3]), 'b', ctx()) as FourState
    expect(s.winner).toBe(0)
  })
})

import { chooseColumn } from '@/lib/games/fourinarow/bot'
import type { BotLevel } from '@/lib/engine/types'

function seeded(seed: number) {
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = Math.imul(a ^ (a >>> 15), a | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

function match(red: BotLevel, yellow: BotLevel, seed: number): 0 | 1 | null {
  const rnd = seeded(seed)
  let s = fourInARow.setup(['a', 'b'], { now: 0, random: rnd })
  const levels = [red, yellow] as const
  while (s.winner === null && !s.draw) {
    const pid = s.players[s.turn]
    const col = chooseColumn(fourInARow.view(s, pid), levels[s.turn], rnd)!
    const r = fourInARow.action(s, pid, { type: 'drop', col }, { now: 0, random: rnd })
    if ('error' in r) throw new Error(r.error)
    s = r.state
  }
  return s.winner
}

describe('four in a row bot', () => {
  it('takes a winning move and blocks an obvious loss', () => {
    // Red has three in column 0; red to move should win there.
    let s = play([0, 1, 0, 1, 0, 2])
    expect(chooseColumn(fourInARow.view(s, s.players[s.turn]), 'easy', () => 0.99)).toBe(0)
    // Yellow must block red's column 0.
    s = play([0, 1, 0, 1, 0])
    expect(chooseColumn(fourInARow.view(s, s.players[s.turn]), 'medium', () => 0.99)).toBe(0)
  })

  it('harder bots beat easier ones most of the time', () => {
    const tally = (a: BotLevel, b: BotLevel) => {
      let aWins = 0
      for (let i = 0; i < 20; i++) {
        // swap colors each game
        const w = i % 2 ? match(b, a, i) : match(a, b, i)
        if (w !== null && (i % 2 ? w === 1 : w === 0)) aWins++
      }
      return aWins
    }
    const hardVsEasy = tally('hard', 'easy')
    const medVsEasy = tally('medium', 'easy')
    console.log({ hardVsEasy, medVsEasy })
    expect(hardVsEasy).toBeGreaterThanOrEqual(17)
    expect(medVsEasy).toBeGreaterThanOrEqual(13)
  }, 60_000)

  it('hard thinks fast enough on an empty board', () => {
    const s = fourInARow.setup(['a', 'b'], { now: 0, random: () => 0 })
    const t = performance.now()
    chooseColumn(fourInARow.view(s, s.players[s.turn]), 'hard', () => 0.5)
    expect(performance.now() - t).toBeLessThan(1500)
  })
})
