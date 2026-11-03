import type { GameModule, PlayerId, RuleResult } from '@/lib/engine/types'
import { fourBot } from './bot'

export const COLS = 7
export const ROWS = 6

/** Board is column-major: cols[c][r], r = 0 is the bottom. */
export interface FourState {
  players: [PlayerId, PlayerId] // [red, yellow]
  cols: (0 | 1)[][]
  turn: 0 | 1
  winner: 0 | 1 | null
  draw: boolean
  line: [number, number][] | null
  last: [number, number] | null
  forfeit: PlayerId | null
}

export type FourAction = { type: 'drop'; col: number }

export type FourView = FourState & { me: 0 | 1 | null }

const DIRS: [number, number][] = [[1, 0], [0, 1], [1, 1], [1, -1]]

function findLine(cols: (0 | 1)[][], c: number, r: number): [number, number][] | null {
  const who = cols[c]![r]
  for (const [dc, dr] of DIRS) {
    const line: [number, number][] = [[c, r]]
    for (const sign of [1, -1]) {
      let x = c + dc * sign
      let y = r + dr * sign
      while (x >= 0 && x < COLS && y >= 0 && y < ROWS && cols[x]![y] === who) {
        line.push([x, y])
        x += dc * sign
        y += dr * sign
      }
    }
    if (line.length >= 4) return line
  }
  return null
}

export const fourInARow: GameModule<FourState, FourAction, FourView> = {
  id: 'fourinarow',
  name: 'Four in a Row',
  description: 'Take turns dropping discs into the grid. First to line up four in a row, across, down or diagonally, wins.',
  minPlayers: 2,
  maxPlayers: 2,

  setup(players, ctx) {
    const first = ctx.random() < 0.5 ? 0 : 1
    return {
      players: [players[0]!, players[1]!],
      cols: Array.from({ length: COLS }, () => []),
      turn: first,
      winner: null,
      draw: false,
      line: null,
      last: null,
      forfeit: null,
    }
  },

  action(s, pid, a): RuleResult<FourState> {
    if (s.winner !== null || s.draw) return { error: 'The game is over.' }
    const me = s.players.indexOf(pid)
    if (me < 0) return { error: "You're watching this game." }
    if (me !== s.turn) return { error: "It's not your turn." }
    if (a?.type !== 'drop' || !Number.isInteger(a.col) || a.col < 0 || a.col >= COLS) return { error: 'Pick a column.' }
    if (s.cols[a.col]!.length >= ROWS) return { error: 'That column is full.' }
    const cols = s.cols.map((c) => [...c])
    cols[a.col]!.push(me as 0 | 1)
    const r = cols[a.col]!.length - 1
    const line = findLine(cols, a.col, r)
    const full = cols.every((c) => c.length >= ROWS)
    return {
      state: {
        ...s,
        cols,
        last: [a.col, r],
        line,
        winner: line ? (me as 0 | 1) : null,
        draw: !line && full,
        turn: (1 - me) as 0 | 1,
      },
    }
  },

  playerLeft(s, pid) {
    const i = s.players.indexOf(pid)
    if (i < 0 || s.winner !== null || s.draw) return s
    return { ...s, winner: (1 - i) as 0 | 1, forfeit: pid }
  },

  isOver(s) {
    return s.winner !== null || s.draw
  },

  view(s, pid) {
    const i = pid ? s.players.indexOf(pid) : -1
    return { ...s, me: i < 0 ? null : (i as 0 | 1) }
  },

  bot: (view, ctx, level, attempt) => (attempt > 0 ? null : fourBot(view, ctx, level)),
}
