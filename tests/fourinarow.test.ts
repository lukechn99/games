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
