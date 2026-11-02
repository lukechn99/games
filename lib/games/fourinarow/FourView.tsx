'use client'

import { useState } from 'react'
import { Button } from '@/components/ui/button'
import type { GameViewProps } from '@/lib/games/ui'
import { COLS, ROWS, type FourAction, type FourView as View } from './rules'

const CELL = 60
const DISC = ['#e63946', '#ffc93c'] as const
const DISC_NAME = ['Red', 'Yellow'] as const

export default function FourView({ view, act, isHost, playAgain, backToLobby, nameOf }: GameViewProps<View, FourAction>) {
  const [hover, setHover] = useState<number | null>(null)
  const over = view.winner !== null || view.draw
  const myTurn = !over && view.me === view.turn
  const onLine = (c: number, r: number) => view.line?.some(([x, y]) => x === c && y === r)

  let status: string
  if (view.winner !== null) {
    const name = nameOf(view.players[view.winner])
    status = view.forfeit ? `${name} wins: the other player left.` : view.me === view.winner ? 'You win!' : `${name} wins.`
  } else if (view.draw) status = "It's a draw: the board is full."
  else if (myTurn) status = 'Your turn. Tap a column.'
  else status = `${nameOf(view.players[view.turn])}'s turn.`

  return (
    <div className="mx-auto flex max-w-lg flex-col items-center gap-5 px-4 py-6">
      <div className="flex w-full items-center justify-between gap-3">
        {[0, 1].map((i) => (
          <div key={i} className={`flex min-w-0 items-center gap-2 rounded-lg px-3 py-2 ${!over && view.turn === i ? 'bg-secondary' : ''}`}>
            <span className="size-5 shrink-0 rounded-full border-2 border-black/20" style={{ background: DISC[i] }} aria-hidden="true" />
            <span className="truncate font-medium">
              {nameOf(view.players[i]!)}
              {view.me === i && <span className="text-muted-foreground"> (you)</span>}
            </span>
          </div>
        ))}
      </div>

      <p className={`w-full rounded-lg px-4 py-2 text-center font-medium ${myTurn ? 'bg-primary text-primary-foreground' : 'bg-secondary'}`} role="status">
        {status}
      </p>

      <svg
        viewBox={`0 0 ${COLS * CELL} ${ROWS * CELL + CELL}`}
        className="w-full touch-manipulation select-none"
        role="grid"
        aria-label="Game board"
        onPointerLeave={() => setHover(null)}
      >
        <defs>
          <mask id="holes">
            <rect width={COLS * CELL} height={ROWS * CELL} fill="#fff" />
            {Array.from({ length: COLS * ROWS }, (_, i) => (
              <circle key={i} cx={(i % COLS) * CELL + CELL / 2} cy={Math.floor(i / COLS) * CELL + CELL / 2} r={CELL * 0.38} fill="#000" />
            ))}
          </mask>
        </defs>
        {/* preview disc above the hovered column */}
        {myTurn && hover !== null && view.cols[hover]!.length < ROWS && (
          <circle cx={hover * CELL + CELL / 2} cy={CELL / 2} r={CELL * 0.38} fill={DISC[view.me!]} opacity="0.6" />
        )}
        <g transform={`translate(0 ${CELL})`}>
          {view.cols.map((col, c) =>
            col.map((who, r) => {
              const isLast = view.last?.[0] === c && view.last?.[1] === r
              const y = (ROWS - 1 - r) * CELL + CELL / 2
              return (
                <circle
                  key={`${c}-${r}`}
                  cx={c * CELL + CELL / 2}
                  cy={y}
                  r={CELL * 0.38}
                  fill={DISC[who]}
                  stroke={onLine(c, r) ? '#fff' : 'none'}
                  strokeWidth="4"
                  style={isLast ? { animation: 'drop 0.35s cubic-bezier(.5,0,.75,0)', ['--from' as string]: `${-y - CELL}px` } : undefined}
                />
              )
            }),
          )}
          <rect width={COLS * CELL} height={ROWS * CELL} rx="12" fill="#1d4ed8" mask="url(#holes)" />
          {Array.from({ length: COLS }, (_, c) => (
            <rect
              key={c}
              x={c * CELL}
              y={-CELL}
              width={CELL}
              height={ROWS * CELL + CELL}
              fill="transparent"
              role="gridcell"
              aria-label={`Column ${c + 1}${view.cols[c]!.length >= ROWS ? ', full' : ''}`}
              style={{ cursor: myTurn ? 'pointer' : 'default' }}
              onPointerEnter={() => setHover(c)}
              onClick={() => myTurn && view.cols[c]!.length < ROWS && act({ type: 'drop', col: c })}
            />
          ))}
        </g>
      </svg>
      <style>{`@keyframes drop { from { transform: translateY(var(--from)); } to { transform: translateY(0); } } @media (prefers-reduced-motion: reduce) { circle { animation: none !important; } }`}</style>

      {view.me !== null && !over && (
        <p className="text-sm text-muted-foreground">You are {DISC_NAME[view.me].toLowerCase()}.</p>
      )}

      {over &&
        (isHost ? (
          <div className="flex w-full flex-col gap-2">
            <Button size="lg" className="h-12" onClick={playAgain}>Play again</Button>
            <Button size="lg" variant="outline" className="h-12" onClick={backToLobby}>Back to lobby</Button>
          </div>
        ) : (
          <p className="text-muted-foreground">Waiting for the host to start another game.</p>
        ))}
    </div>
  )
}
