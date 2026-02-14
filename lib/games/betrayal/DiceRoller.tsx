'use client'

import { useState, useCallback, useRef } from 'react'
import type { ReactNode } from 'react'
import type { DieFace } from './types'

/* ------------------------------------------------------------------ */
/*  Single die display                                                 */
/* ------------------------------------------------------------------ */

function Die({ face, rolling }: { face: DieFace; rolling: boolean }) {
  const dots: Record<DieFace, ReactNode> = {
    0: <span className="text-gray-600 text-sm">&mdash;</span>,
    1: (
      <div className="flex items-center justify-center h-full">
        <div className="w-2.5 h-2.5 rounded-full bg-amber-200 shadow-sm" style={{ boxShadow: '0 0 4px rgba(251,191,36,0.4)' }} />
      </div>
    ),
    2: (
      <div className="flex items-center justify-between h-full px-1.5">
        <div className="w-2.5 h-2.5 rounded-full bg-amber-200 shadow-sm" style={{ boxShadow: '0 0 4px rgba(251,191,36,0.4)' }} />
        <div className="w-2.5 h-2.5 rounded-full bg-amber-200 shadow-sm" style={{ boxShadow: '0 0 4px rgba(251,191,36,0.4)' }} />
      </div>
    ),
  }

  return (
    <div
      className={`
        w-11 h-11 rounded-lg flex items-center justify-center
        text-lg font-bold transition-all duration-300
        ${rolling ? 'animate-bounce' : ''}
      `}
      style={{
        background: rolling
          ? 'linear-gradient(135deg, #444, #555)'
          : 'linear-gradient(135deg, #1a1a2e, #16162a)',
        border: `2px solid ${rolling ? 'rgba(255,255,255,0.2)' : 'rgba(201,165,90,0.4)'}`,
        boxShadow: rolling
          ? 'none'
          : '0 3px 10px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.1)',
      }}
    >
      {rolling ? <span className="text-gray-400 text-sm">?</span> : dots[face]}
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
        <p className="text-sm text-gray-400 font-medium" style={{ fontFamily: '"Palatino Linotype", "Book Antiqua", Palatino, Georgia, serif' }}>{label}</p>
      )}

      <div className="flex items-center gap-1.5 flex-wrap justify-center">
        {displayDice.map((face, i) => (
          <Die key={i} face={face} rolling={rolling} />
        ))}
      </div>

      {showTotal && result && !rolling && (
        <p className="text-xl font-bold text-amber-200 tabular-nums" style={{ fontFamily: '"Palatino Linotype", "Book Antiqua", Palatino, Georgia, serif' }}>
          Total: {total}
        </p>
      )}

      {onRoll && (
        <button
          type="button"
          onClick={handleRoll}
          disabled={rolling}
          className={`
            px-5 py-2.5 rounded-lg text-sm font-bold uppercase tracking-wider
            transition-all duration-200 border
            ${rolling
              ? 'bg-gray-700 text-gray-500 cursor-not-allowed border-gray-600'
              : 'bg-amber-800/60 hover:bg-amber-700/70 text-amber-100 cursor-pointer border-amber-700/40 shadow-lg hover:shadow-amber-700/20'
            }
          `}
        >
          {rolling ? 'Rolling...' : `Roll ${diceCount} Dice`}
        </button>
      )}
    </div>
  )
}
