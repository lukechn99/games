'use client'

import { Skull } from 'lucide-react'
import { CARD_BY_ID } from '../data/cards'
import { EXPLORER_BY_ID } from '../data/explorers'
import type { ExplorerState, Trait } from '../types'
import { INK } from './pieces'

const LABEL: Record<Trait, string> = { speed: 'Speed', might: 'Might', sanity: 'Sanity', knowledge: 'Knowledge' }
const ORDER: Trait[] = ['speed', 'might', 'sanity', 'knowledge']

/** A character card: four tracks, with a clip on the current value. */
export function CharacterSheet({ ex, compact = false }: { ex: ExplorerState; compact?: boolean }) {
  const def = EXPLORER_BY_ID.get(ex.explorerId)!
  return (
    <div className="rounded-lg border border-white/10 bg-[#1d1822] p-3">
      {!compact && (
        <div className="mb-2 flex items-center gap-2">
          <span className="size-3 rounded-full" style={{ background: def.color }} aria-hidden="true" />
          <span className="font-display font-bold">{def.name}</span>
          <span className="text-xs text-white/50">{def.age}</span>
          {ex.dead && <span className="ml-auto text-xs font-semibold text-red-300">Dead</span>}
        </div>
      )}
      <div className="flex flex-col gap-1.5">
        {ORDER.map((t) => {
          const track = def.traits[t]
          return (
            <div key={t} className="flex items-center gap-1.5">
              <span className="w-[4.5rem] shrink-0 text-xs text-white/70">{LABEL[t]}</span>
              <span className={`grid size-6 place-items-center rounded ${ex.idx[t] < 0 ? 'bg-red-500 text-white' : 'text-white/40'}`} aria-label="death">
                <Skull className="size-3.5" />
              </span>
              {track.values.map((v, i) => {
                const current = ex.idx[t] === i
                return (
                  <span
                    key={i}
                    aria-current={current ? 'true' : undefined}
                    className={`grid h-6 w-6 place-items-center rounded text-xs tabular-nums ${
                      current ? 'bg-[#f6d860] font-bold text-black' : i === 0 ? 'text-red-300' : 'text-white/70'
                    } ${i === track.start ? 'underline decoration-emerald-400 decoration-2 underline-offset-2' : ''}`}
                  >
                    {v}
                  </span>
                )
              })}
            </div>
          )
        })}
      </div>
    </div>
  )
}

export function CardChip({ id, onClick, active }: { id: string; onClick?: () => void; active?: boolean }) {
  if (id === 'hidden') {
    return <span className="rounded-md border border-white/10 bg-white/5 px-2 py-1 text-xs text-white/50">Hidden omen</span>
  }
  const c = CARD_BY_ID.get(id)
  if (!c) return null
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={!onClick}
      title={c.rules}
      className={`rounded-md border px-2 py-1 text-left text-xs ${active ? 'border-[#f6d860]' : 'border-white/15'} bg-white/5 disabled:cursor-default`}
      style={{ color: INK[c.kind] }}
    >
      {c.name}
    </button>
  )
}

export function CardFace({ id }: { id: string }) {
  const c = CARD_BY_ID.get(id)
  if (!c) return null
  return (
    <div className="rounded-xl border-2 bg-[#f3ecdf] p-4 text-[#2a2420]" style={{ borderColor: INK[c.kind] }}>
      <p className="text-xs font-semibold uppercase tracking-wide" style={{ color: INK[c.kind] === '#e9c46a' ? '#8a6d1d' : INK[c.kind] }}>
        {c.kind}
      </p>
      <p className="font-display text-2xl font-extrabold">{c.name}</p>
      <p className="mt-1 text-sm italic opacity-75">{c.flavor}</p>
      <p className="mt-3 text-sm">{c.rules}</p>
      {c.approx && <p className="mt-2 text-xs opacity-60">Effect approximated: the real card text couldn&apos;t be sourced.</p>}
    </div>
  )
}
