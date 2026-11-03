/**
 * Four in a Row computer player: negamax search with alpha-beta pruning.
 * Difficulty = how many moves ahead it looks, plus how often it plays loosely.
 */
import type { BotLevel, RuleContext } from '@/lib/engine/types'
import { COLS, ROWS, type FourAction, type FourView } from './rules'

type Grid = number[][] // grid[c][r]: -1 empty, 0 or 1
const ORDER = [3, 2, 4, 1, 5, 0, 6] // try the center first: better pruning

const DEPTH: Record<BotLevel, number> = { easy: 2, medium: 4, hard: 7 }
const SLOPPY: Record<BotLevel, number> = { easy: 0.35, medium: 0.08, hard: 0 }

function toGrid(view: FourView): Grid {
  return view.cols.map((col) => Array.from({ length: ROWS }, (_, r) => (r < col.length ? col[r]! : -1)))
}

const height = (g: Grid, c: number) => g[c]!.indexOf(-1) === -1 ? ROWS : g[c]!.indexOf(-1)

function wins(g: Grid, c: number, r: number, who: number): boolean {
  for (const [dc, dr] of [[1, 0], [0, 1], [1, 1], [1, -1]] as const) {
    let n = 1
    for (const s of [1, -1]) {
      let x = c + dc * s
      let y = r + dr * s
      while (x >= 0 && x < COLS && y >= 0 && y < ROWS && g[x]![y] === who) {
        n++
        x += dc * s
        y += dr * s
      }
    }
    if (n >= 4) return true
  }
  return false
}

/** Static score from `who`'s point of view: open lines of 2 and 3, and the center. */
function evaluate(g: Grid, who: number): number {
  let score = 0
  const opp = 1 - who
  for (let r = 0; r < ROWS; r++) if (g[3]![r] === who) score += 3
  for (let c = 0; c < COLS; c++) {
    for (let r = 0; r < ROWS; r++) {
      for (const [dc, dr] of [[1, 0], [0, 1], [1, 1], [1, -1]] as const) {
        const ec = c + dc * 3
        const er = r + dr * 3
        if (ec < 0 || ec >= COLS || er < 0 || er >= ROWS) continue
        let mine = 0
        let theirs = 0
        for (let k = 0; k < 4; k++) {
          const v = g[c + dc * k]![r + dr * k]
          if (v === who) mine++
          else if (v === opp) theirs++
        }
        if (theirs === 0) score += mine === 3 ? 5 : mine === 2 ? 2 : 0
        else if (mine === 0) score -= theirs === 3 ? 4 : theirs === 2 ? 1 : 0
      }
    }
  }
  return score
}

function negamax(g: Grid, depth: number, alpha: number, beta: number, who: number, filled: number): number {
  if (filled === COLS * ROWS) return 0
  if (depth === 0) return evaluate(g, who)
  let best = -Infinity
  for (const c of ORDER) {
    const r = height(g, c)
    if (r >= ROWS) continue
    g[c]![r] = who
    // Faster wins score higher, so the bot finishes the game when it can.
    const score = wins(g, c, r, who) ? 100000 + depth : -negamax(g, depth - 1, -beta, -alpha, 1 - who, filled + 1)
    g[c]![r] = -1
    if (score > best) best = score
    if (best > alpha) alpha = best
    if (alpha >= beta) break
  }
  return best
}

export function chooseColumn(view: FourView, level: BotLevel, random: () => number): number | null {
  const me = view.me
  if (me === null || view.turn !== me || view.winner !== null || view.draw) return null
  const g = toGrid(view)
  const legal = ORDER.filter((c) => height(g, c) < ROWS)
  if (!legal.length) return null
  const filled = view.cols.reduce((a, c) => a + c.length, 0)

  // Never miss an immediate win, even when playing loosely.
  for (const c of legal) {
    const r = height(g, c)
    g[c]![r] = me
    const w = wins(g, c, r, me)
    g[c]![r] = -1
    if (w) return c
  }
  if (random() < SLOPPY[level]) return legal[Math.floor(random() * legal.length)]!

  let best = -Infinity
  let picks: number[] = []
  for (const c of legal) {
    const r = height(g, c)
    g[c]![r] = me
    const score = -negamax(g, DEPTH[level] - 1, -Infinity, Infinity, 1 - me, filled + 1)
    g[c]![r] = -1
    if (score > best) {
      best = score
      picks = [c]
    } else if (score === best) picks.push(c)
  }
  return picks[Math.floor(random() * picks.length)]!
}

export function fourBot(view: FourView, ctx: RuleContext, level: BotLevel): FourAction | null {
  const col = chooseColumn(view, level, ctx.random)
  return col === null ? null : { type: 'drop', col }
}
