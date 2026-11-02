'use client'

import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { CARD_BY_ID, EVENT_BY_ID } from '../data/cards'
import { TILE_BY_ID } from '../data/tiles'
import { rotateDoors } from '../engine/board'
import type { HauntedAction, Prompt, Trait } from '../types'
import type { HauntedView } from '../rules'
import { CardChip, CardFace } from './Sheet'
import { Die, T, TileArt } from './pieces'

type Act = (a: HauntedAction) => void

const LABEL: Record<Trait, string> = { speed: 'Speed', might: 'Might', sanity: 'Sanity', knowledge: 'Knowledge' }

/** Who must answer a prompt. */
export function promptOwner(view: HauntedView, p: Prompt): string | null {
  switch (p.kind) {
    case 'trade':
      return p.to
    case 'haunt':
      return view.haunt?.revealer ?? null
    default:
      return p.pid
  }
}

export function describeWait(p: Prompt): string {
  switch (p.kind) {
    case 'place':
      return 'placing a new room'
    case 'damage':
      return 'taking damage'
    case 'event':
      return 'facing an event'
    case 'card':
      return 'looking at a new card'
    case 'reroll':
      return 'deciding on a reroll'
    case 'gainChoice':
      return 'choosing a trait'
    case 'trade':
      return 'considering a trade'
    case 'chooseTile':
      return 'choosing a room'
    case 'haunt':
      return 'reading their briefing'
    case 'elevator':
      return 'steering the lift'
    case 'attackResult':
      return 'deciding what to take'
  }
}

export function Modal({ children, title }: { children: React.ReactNode; title: string }) {
  return (
    <div className="fixed inset-0 z-40 flex items-end justify-center bg-black/60 p-3 sm:items-center" role="dialog" aria-modal="true" aria-label={title}>
      <div className="max-h-[88dvh] w-full max-w-md overflow-y-auto rounded-2xl border border-white/10 bg-[#1b1620] p-5 text-white shadow-2xl">
        {children}
      </div>
    </div>
  )
}

export function PromptPanel({ view, act, nameOf }: { view: HauntedView; act: Act; nameOf: (id: string) => string }) {
  const p = view.prompt!
  switch (p.kind) {
    case 'place':
      return <PlacePrompt p={p} act={act} region={p.at.region} />
    case 'damage':
      return <DamagePrompt p={p} act={act} view={view} />
    case 'event': {
      const ev = EVENT_BY_ID.get(p.cardId)!
      return (
        <Modal title={ev.name}>
          <div className="rounded-xl border-2 border-[#7fd1c7] bg-[#f3ecdf] p-4 text-[#2a2420]">
            <p className="text-xs font-semibold uppercase tracking-wide text-[#2a7f74]">Event</p>
            <p className="font-display text-2xl font-extrabold">{ev.name}</p>
            <p className="mt-1 text-sm italic opacity-75">{ev.flavor}</p>
            <ul className="mt-3 space-y-1 text-sm">
              {ev.outcomes.map((o) => (
                <li key={o.min}>
                  {ev.roll && <strong className="tabular-nums">{o.min}+ </strong>}
                  {o.text}
                </li>
              ))}
            </ul>
            {ev.approx && <p className="mt-2 text-xs opacity-60">Stand-in event: the real 3rd-edition events couldn&apos;t be sourced.</p>}
          </div>
          <Button className="mt-4 h-11 w-full" onClick={() => act({ type: 'rollEvent' })}>
            {ev.roll ? `Roll ${LABEL[ev.roll]}` : 'Continue'}
          </Button>
        </Modal>
      )
    }
    case 'card':
      return (
        <Modal title="New card">
          <CardFace id={p.cardId} />
          <Button className="mt-4 h-11 w-full" onClick={() => act({ type: 'continue' })}>
            Take it
          </Button>
        </Modal>
      )
    case 'reroll':
      return <RerollPrompt p={p} act={act} view={view} />
    case 'gainChoice':
      return (
        <Modal title="Choose a trait">
          <p className="font-display text-xl font-bold">{p.reason}</p>
          <div className="mt-4 grid grid-cols-2 gap-2">
            {p.traits.map((t) => (
              <Button key={t} variant="outline" className="h-11" onClick={() => act({ type: 'gainPick', trait: t })}>
                +{p.amount} {LABEL[t]}
              </Button>
            ))}
          </div>
        </Modal>
      )
    case 'trade':
      return (
        <Modal title="Trade offer">
          <p className="font-display text-xl font-bold">{nameOf(p.from)} wants to trade</p>
          <p className="mt-3 text-sm text-white/60">You get</p>
          <div className="mt-1 flex flex-wrap gap-1">{p.give.length ? p.give.map((c) => <CardChip key={c} id={c} />) : <span className="text-sm">Nothing</span>}</div>
          <p className="mt-3 text-sm text-white/60">You give</p>
          <div className="mt-1 flex flex-wrap gap-1">{p.take.length ? p.take.map((c) => <CardChip key={c} id={c} />) : <span className="text-sm">Nothing</span>}</div>
          <div className="mt-5 grid grid-cols-2 gap-2">
            <Button variant="outline" className="h-11" onClick={() => act({ type: 'answerTrade', accept: false })}>Decline</Button>
            <Button className="h-11" onClick={() => act({ type: 'answerTrade', accept: true })}>Accept</Button>
          </div>
        </Modal>
      )
    case 'elevator':
      return (
        <Modal title="Wandering Lift">
          <p className="font-display text-xl font-bold">You rolled {p.roll}. Where to?</p>
          <div className="mt-4 grid grid-cols-3 gap-2">
            {(['upper', 'ground', 'basement'] as const).map((r) => (
              <Button key={r} variant="outline" className="h-11" onClick={() => act({ type: 'elevatorRegion', region: r })}>
                {r === 'upper' ? 'Upper' : r === 'ground' ? 'Ground' : 'Basement'}
              </Button>
            ))}
          </div>
        </Modal>
      )
    case 'attackResult': {
      const victim = view.explorers[p.target]!
      const cards = [...victim.items, ...victim.omens].filter((c) => c !== 'hidden')
      return (
        <Modal title="You won the fight">
          <p className="font-display text-xl font-bold">You won by {p.margin}</p>
          <p className="mt-1 text-sm text-white/60">Deal {p.margin} Physical damage, or steal one card instead.</p>
          <div className="mt-3 flex flex-wrap gap-1">
            {cards.map((c) => (
              <CardChip key={c} id={c} onClick={() => act({ type: 'steal', card: c })} />
            ))}
          </div>
          <Button className="mt-4 h-11 w-full" onClick={() => act({ type: 'steal', card: null })}>
            Deal {p.margin} damage
          </Button>
        </Modal>
      )
    }
    default:
      return null
  }
}

function PlacePrompt({ p, act, region }: { p: Extract<Prompt, { kind: 'place' }>; act: Act; region: 'upper' | 'ground' | 'basement' }) {
  const def = TILE_BY_ID.get(p.tileId)!
  const [i, setI] = useState(0)
  const rot = p.options[i % p.options.length]!
  const preview = { uid: 'preview', tileId: p.tileId, region, x: 0, y: 0, rot: rot as 0 | 1 | 2 | 3, doors: rotateDoors(def.doors, rot), tokens: [] }
  return (
    <Modal title="Place the new room">
      <p className="text-sm text-white/60">You discovered</p>
      <p className="font-display text-2xl font-bold">{def.name}</p>
      {def.rules && <p className="mt-1 text-sm text-white/70">{def.rules}</p>}
      <div className="mt-4 flex justify-center">
        <svg width="180" height="180" viewBox={`-10 -10 ${T + 20} ${T + 20}`} aria-label="Room preview">
          <TileArt tile={preview} />
          {/* the doorway you came through */}
          <path
            d={['M50 -8h20', `M${T + 8} 50v20`, `M50 ${T + 8}h20`, 'M-8 50v20'][(p.viaDir + 2) % 4]}
            stroke="#9ae6b4"
            strokeWidth="5"
            strokeLinecap="round"
          />
        </svg>
      </div>
      <p className="text-center text-xs text-white/50">The green mark is the doorway you came through.</p>
      <div className="mt-4 grid grid-cols-2 gap-2">
        <Button variant="outline" className="h-11" disabled={p.options.length < 2} onClick={() => setI((x) => x + 1)}>
          Rotate ({p.options.length} ways)
        </Button>
        <Button className="h-11" onClick={() => act({ type: 'place', rot })}>Place room</Button>
      </div>
    </Modal>
  )
}

function DamagePrompt({ p, act, view }: { p: Extract<Prompt, { kind: 'damage' }>; act: Act; view: HauntedView }) {
  const ex = view.explorers[p.pid]!
  const brooch = ex.items.some((c) => CARD_BY_ID.get(c)?.effect?.kind === 'brooch')
  const traits: Trait[] =
    p.type === 'general' || brooch ? ['speed', 'might', 'sanity', 'knowledge'] : p.type === 'physical' ? ['speed', 'might'] : ['sanity', 'knowledge']
  const [split, setSplit] = useState<Partial<Record<Trait, number>>>({})
  const used = Object.values(split).reduce((a, b) => a + (b ?? 0), 0)
  return (
    <Modal title="Take damage">
      <p className="font-display text-xl font-bold">
        Take {p.amount} {p.type === 'general' ? '' : p.type} damage
      </p>
      <p className="text-sm text-white/60">{p.reason} Split it across your traits.</p>
      <div className="mt-4 flex flex-col gap-2">
        {traits.map((t) => (
          <div key={t} className="flex items-center justify-between rounded-lg bg-white/5 px-3 py-2">
            <span>{LABEL[t]}</span>
            <span className="flex items-center gap-2">
              <Button size="icon-sm" variant="outline" aria-label={`Less on ${t}`} disabled={!split[t]}
                onClick={() => setSplit((s) => ({ ...s, [t]: (s[t] ?? 0) - 1 }))}>−</Button>
              <span className="w-5 text-center tabular-nums">{split[t] ?? 0}</span>
              <Button size="icon-sm" variant="outline" aria-label={`More on ${t}`} disabled={used >= p.amount}
                onClick={() => setSplit((s) => ({ ...s, [t]: (s[t] ?? 0) + 1 }))}>+</Button>
            </span>
          </div>
        ))}
      </div>
      <Button className="mt-4 h-11 w-full" disabled={used !== p.amount} onClick={() => act({ type: 'allocate', split })}>
        {used === p.amount ? 'Take the damage' : `Assign ${p.amount - used} more`}
      </Button>
    </Modal>
  )
}

function RerollPrompt({ p, act, view }: { p: Extract<Prompt, { kind: 'reroll' }>; act: Act; view: HauntedView }) {
  const ex = view.explorers[p.pid]!
  const tools = [...ex.items, ...ex.omens].filter((c) => ['doll', 'coin', 'rabbitFoot', 'idol', 'feather'].includes(CARD_BY_ID.get(c)?.effect?.kind ?? '') && !p.roll.rerolled.includes(c))
  const total = p.roll.dice.reduce((a, b) => a + b, 0) + p.roll.bonus
  const [die, setDie] = useState<number | null>(null)
  const [feather, setFeather] = useState(8)
  return (
    <Modal title="Your roll">
      <p className="text-sm text-white/60">{p.roll.label}</p>
      <p className="font-display text-4xl font-extrabold tabular-nums">{total}</p>
      <div className="mt-2 flex flex-wrap gap-1.5">
        {p.roll.dice.map((d, i) => (
          <button key={i} type="button" onClick={() => setDie(i)} aria-pressed={die === i} className={`rounded-md ${die === i ? 'ring-2 ring-[#f6d860]' : ''}`}>
            <Die value={d} />
          </button>
        ))}
      </div>
      <p className="mt-4 text-sm text-white/60">You can change this roll with:</p>
      <div className="mt-2 flex flex-col gap-2">
        {tools.map((c) => {
          const k = CARD_BY_ID.get(c)!.effect!.kind
          if (k === 'feather')
            return (
              <div key={c} className="flex items-center gap-2">
                <select value={feather} onChange={(e) => setFeather(+e.target.value)} className="h-10 rounded-md border border-white/20 bg-transparent px-2" aria-label="Result">
                  {[0, 1, 2, 3, 4, 5, 6, 7, 8].map((n) => <option key={n} value={n} className="text-black">{n}</option>)}
                </select>
                <Button variant="outline" className="flex-1" onClick={() => act({ type: 'reroll', item: c, value: feather })}>
                  Bury {CARD_BY_ID.get(c)!.name} to set it
                </Button>
              </div>
            )
          return (
            <Button key={c} variant="outline" disabled={k === 'rabbitFoot' && die === null}
              onClick={() => act({ type: 'reroll', item: c, die: die ?? undefined })}>
              {CARD_BY_ID.get(c)!.name}: {k === 'rabbitFoot' ? (die === null ? 'tap a die first' : 'reroll that die') : CARD_BY_ID.get(c)!.rules.split('.')[0]}
            </Button>
          )
        })}
      </div>
      <Button className="mt-4 h-11 w-full" onClick={() => act({ type: 'acceptRoll' })}>Keep {total}</Button>
    </Modal>
  )
}
