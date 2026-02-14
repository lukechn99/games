'use client'

import { useState, useCallback, useRef } from 'react'
import type { ReactNode } from 'react'
import type { DieFace } from './types'

/* ------------------------------------------------------------------ */
/*  Single die display                                                 */
/* ------------------------------------------------------------------ */

function Die({ face, rolling }: { face: DieFace; rolling: boolean }) {
  const dots: Record<DieFace, ReactNode> = {
    0: <span className="text-gray-500">&ndash;</span>,
    1: (
      <div className="flex items-center justify-center h-full">
        <div className="w-2 h-2 rounded-full bg-white" />
      </div>
    ),
    2: (
      <div className="flex items-center justify-between h-full px-1">
        <div className="w-2 h-2 rounded-full bg-white" />
        <div className="w-2 h-2 rounded-full bg-white" />
      </div>
    ),
  }

  return (
    <div
      className={`
        w-10 h-10 rounded-lg flex items-center justify-center
        text-lg font-bold transition-all duration-300
        ${rolling ? 'animate-bounce' : ''}
      `}
      style={{
        background: rolling ? '#555' : '#1a1a2e',
        border: '2px solid rgba(255,255,255,0.3)',
        boxShadow: rolling ? 'none' : '0 2px 8px rgba(0,0,0,0.4)',
      }}
    >
      {rolling ? '?' : dots[face]}
    </div>
  )
}

/* ------------------------------------------------------------------ */
/*  Dice Roller                                                        */
/* ------------------------------------------------------------------ */

export function rollDice(count: number): DieFace[] {
  const result: DieFace[] = []
  for (let i = 0; i < count; i++) {
    result.push(Math.floor(Math.random() * 3) as DieFace)
  }
  return result
}

interface DiceRollerProps {
  diceCount: number
  result: DieFace[] | null
  onRoll?: () => void
  label?: string
  showTotal?: boolean
}

export default function DiceRoller({
  diceCount,
  result,
  onRoll,
  label,
  showTotal = true,
}: DiceRollerProps) {
  const [rolling, setRolling] = useState(false)
  const [animDice, setAnimDice] = useState<DieFace[]>(() =>
    Array(diceCount).fill(0 as DieFace)
  )
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null)

  // When rolling, show animDice; otherwise show result prop
  const displayDice = rolling
    ? animDice
    : result ?? Array(diceCount).fill(0 as DieFace) as DieFace[]

  const handleRoll = useCallback(() => {
    if (rolling) return
    setRolling(true)

    // Animate random faces for 600ms
    intervalRef.current = setInterval(() => {
      setAnimDice(rollDice(diceCount))
    }, 80)

    setTimeout(() => {
      if (intervalRef.current) clearInterval(intervalRef.current)
      setRolling(false)
      onRoll?.()
    }, 600)
  }, [rolling, diceCount, onRoll])

  const total = displayDice.reduce<number>((sum, d) => sum + d, 0)

  return (
    <div className="flex flex-col items-center gap-3">
      {label && (
        <p className="text-sm text-muted-foreground font-medium">{label}</p>
      )}

      <div className="flex items-center gap-2">
        {displayDice.map((face, i) => (
          <Die key={i} face={face} rolling={rolling} />
        ))}
      </div>

      {showTotal && result && !rolling && (
        <p className="text-xl font-bold text-white tabular-nums">
          Total: {total}
        </p>
      )}

      {onRoll && (
        <button
          type="button"
          onClick={handleRoll}
          disabled={rolling}
          className={`
            px-4 py-2 rounded-lg text-sm font-bold uppercase tracking-wider
            transition-all duration-200
            ${rolling
              ? 'bg-gray-600 text-gray-400 cursor-not-allowed'
              : 'bg-amber-600 hover:bg-amber-500 text-white cursor-pointer shadow-lg hover:shadow-amber-500/25'
            }
          `}
        >
          {rolling ? 'Rolling...' : `Roll ${diceCount} Dice`}
        </button>
      )}
    </div>
  )
}
