'use client'

import { Button } from '@/components/ui/button'
import type { GameViewProps } from '@/lib/games/ui'
import { EXPLORERS } from '../data/explorers'
import { SCENARIOS } from '../data/scenarios'
import type { HauntedAction } from '../types'
import type { HauntedView } from '../rules'
import { ExplorerFigure } from './figures'

export default function Setup({ view, me, isHost, act, nameOf }: GameViewProps<HauntedView, HauntedAction>) {
  const mine = view.picks[me] ?? null
  const takenBy = new Map<string, string>()
  for (const [pid, id] of Object.entries(view.picks)) {
    if (!id) continue
    const color = EXPLORERS.find((e) => e.id === id)!.colorName
    takenBy.set(color, pid)
  }
  const waiting = view.seats.filter((p) => !view.picks[p])
  const ready = !!view.scenario && waiting.length === 0
  const hostPid = view.seats[0]

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-8 px-5 py-6">
      <section>
        <h2 className="font-display text-2xl font-bold">Choose your explorer</h2>
        <p className="text-sm text-white/60">Each color is one character board, so only one explorer per color.</p>
        <div className="mt-4 grid grid-cols-1 gap-2 sm:grid-cols-2">
          {EXPLORERS.map((e) => {
            const owner = takenBy.get(e.colorName)
            const takenByOther = owner && owner !== me
            const picked = mine === e.id
            return (
              <button
                key={e.id}
                type="button"
                disabled={!!takenByOther}
                onClick={() => act({ type: 'pickExplorer', explorerId: e.id })}
                aria-pressed={picked}
                className={`flex gap-3 rounded-lg border-2 p-3 text-left transition-colors ${
                  picked ? 'border-[#f6d860] bg-white/10' : 'border-white/10 bg-white/5 hover:border-white/30'
                } disabled:opacity-40`}
              >
                <svg width="40" height="52" viewBox="-17 -28 34 44" className="shrink-0" aria-hidden="true">
                  <ExplorerFigure explorerId={e.id} color={e.color} />
                </svg>
                <span className="flex-1">
                  <span className="flex items-baseline justify-between gap-2">
                    <span className="font-display font-bold">{e.name}</span>
                    <span className="text-xs text-white/50">age {e.age}</span>
                  </span>
                  <span className="block text-xs text-white/60">{e.blurb}</span>
                  <span className="mt-1 block text-xs tabular-nums text-white/50">
                    Speed {e.traits.speed.values[e.traits.speed.start]}, Might {e.traits.might.values[e.traits.might.start]}, Sanity{' '}
                    {e.traits.sanity.values[e.traits.sanity.start]}, Knowledge {e.traits.knowledge.values[e.traits.knowledge.start]}
                    {takenByOther && `. Taken by ${nameOf(owner!)}`}
                  </span>
                </span>
              </button>
            )
          })}
        </div>
      </section>

      <section>
        <h2 className="font-display text-2xl font-bold">Why are you here?</h2>
        <p className="text-sm text-white/60">
          The scenario decides which haunt each omen can trigger. {isHost ? 'You pick it.' : `${nameOf(hostPid!)} picks it.`}
        </p>
        <div className="mt-4 flex flex-col gap-2" role="radiogroup" aria-label="Scenario">
          {SCENARIOS.map((sc) => (
            <button
              key={sc.id}
              type="button"
              role="radio"
              aria-checked={view.scenario === sc.id}
              disabled={!isHost}
              onClick={() => act({ type: 'pickScenario', scenarioId: sc.id })}
              className={`rounded-lg border-2 p-3 text-left ${view.scenario === sc.id ? 'border-[#f6d860] bg-white/10' : 'border-white/10 bg-white/5'} disabled:cursor-default`}
            >
              <span className="font-display font-bold">{sc.name}</span>
              <span className="block text-sm text-white/60">{sc.blurb}</span>
            </button>
          ))}
        </div>
      </section>

      <section>
        <label className={`flex items-start gap-3 rounded-lg border-2 border-white/10 bg-white/5 p-3 ${isHost ? 'cursor-pointer' : ''}`}>
          <input
            type="checkbox"
            className="mt-1 size-5 accent-[#f6d860]"
            checked={view.openBooks}
            disabled={!isHost}
            onChange={(e) => act({ type: 'setOpenBooks', on: e.target.checked })}
          />
          <span>
            <span className="font-display font-bold">Teaching mode</span>
            <span className="block text-sm text-white/60">
              Everyone can read both sides&apos; haunt rules. Good for a first game. Normally each side only knows its own goal.
            </span>
          </span>
        </label>
      </section>

      <div className="sticky bottom-0 -mx-5 border-t border-white/10 bg-[#120f16]/95 px-5 py-4">
        {isHost ? (
          <Button size="lg" className="h-12 w-full" disabled={!ready} onClick={() => act({ type: 'begin' })}>
            {!view.scenario ? 'Pick a scenario' : waiting.length ? `Waiting for ${waiting.map(nameOf).join(', ')}` : 'Enter the house'}
          </Button>
        ) : (
          <p className="py-3 text-center text-white/60">
            {waiting.length ? `Waiting for ${waiting.map(nameOf).join(', ')} to choose` : 'Waiting for the host to start'}
          </p>
        )}
      </div>
    </div>
  )
}
