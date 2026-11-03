'use client'

import { useEffect, useRef, useState } from 'react'
import type { RollRecord } from '../types'
import { Die } from './pieces'

const ROLL_MS = 700
const SHOW_MS = 1700

/**
 * Shows each new dice roll as it happens: the dice tumble for a moment,
 * then land on the real faces and the total. Rolls queue up so none are
 * missed when several happen at once (an attack and its defense).
 */
export default function DiceRolls({ rolls }: { rolls: RollRecord[] }) {
  const seen = useRef<Set<number> | null>(null)
  const [queue, setQueue] = useState<RollRecord[]>([])
  const [rolling, setRolling] = useState(true)
  const [faces, setFaces] = useState<number[]>([])

  // Queue rolls we haven't shown. Rolls that existed before we mounted are history.
  useEffect(() => {
    if (!seen.current) {
      seen.current = new Set(rolls.map((r) => r.id))
      return
    }
    const fresh = rolls.filter((r) => !seen.current!.has(r.id))
    fresh.forEach((r) => seen.current!.add(r.id))
    // New rolls arrive from the host: an external event.
     
    if (fresh.length) setQueue((q) => [...q, ...fresh].slice(-6))
  }, [rolls])

  const current = queue[0]
  const reduce = typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
  useEffect(() => {
    if (!current) return
    // Hurry through a backlog so the display keeps up with the game.
    const speed = queue.length > 2 ? 0.5 : 1
    const n = Math.max(1, current.dice.length)
     
    setRolling(!reduce && current.dice.length > 0)
    const tumble = setInterval(() => setFaces(Array.from({ length: n }, () => Math.floor(Math.random() * 3))), 70)
    const land = setTimeout(() => {
      clearInterval(tumble)
      setRolling(false)
    }, reduce ? 0 : ROLL_MS * speed)
    const done = setTimeout(() => setQueue((q) => q.slice(1)), (reduce ? 0 : ROLL_MS * speed) + SHOW_MS * speed)
    return () => {
      clearInterval(tumble)
      clearTimeout(land)
      clearTimeout(done)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [current?.id])

  if (!current) return null
  const shown = rolling ? faces : current.dice
  return (
    <div className="pointer-events-none absolute inset-x-0 top-3 z-10 flex justify-center px-3" aria-live="polite">
      <div className="rounded-xl border border-white/15 bg-[#1b1620] px-4 py-3 text-center shadow-xl">
        <p className="text-xs text-white/70">
          {current.by}: {current.label}
        </p>
        <div className="mt-2 flex flex-wrap justify-center gap-1.5">
          {shown.map((d, i) => (
            <span key={i} className={rolling ? 'dice-tumble' : 'dice-land'} style={{ animationDelay: `${i * 40}ms` }}>
              <Die value={d} size={30} />
            </span>
          ))}
          {current.dice.length === 0 && <span className="text-sm text-white/70">chosen result</span>}
        </div>
        <p className={`mt-1 font-display text-2xl font-extrabold tabular-nums transition-opacity ${rolling ? 'opacity-0' : 'opacity-100'}`}>
          {rolling ? '…' : <>= {current.total}{current.bonus ? <span className="ml-1 text-sm font-normal text-white/60">(incl. +{current.bonus})</span> : null}</>}
        </p>
      </div>
      <style>{`
        @keyframes dice-tumble { 0% { transform: translateY(0) rotate(0deg); } 50% { transform: translateY(-6px) rotate(180deg); } 100% { transform: translateY(0) rotate(360deg); } }
        @keyframes dice-land { 0% { transform: scale(1.25); } 100% { transform: scale(1); } }
        .dice-tumble { display: inline-block; animation: dice-tumble 0.35s linear infinite; }
        .dice-land { display: inline-block; animation: dice-land 0.25s ease-out; }
      `}</style>
    </div>
  )
}
