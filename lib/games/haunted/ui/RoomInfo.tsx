'use client'

import { Button } from '@/components/ui/button'
import { CARD_BY_ID } from '../data/cards'
import { EXPLORER_BY_ID } from '../data/explorers'
import { TILE_BY_ID } from '../data/tiles'
import type { HauntedView } from '../rules'
import type { CardKind } from '../types'
import { ExplorerFigure, MonsterFigure } from './figures'
import { Modal } from './Prompts'
import { INK as SYMBOL_INK, REGION_STYLE } from './pieces'

const SYMBOL_TEXT: Record<CardKind, string> = {
  event: 'Event symbol: whoever discovers this room draws an event card.',
  item: 'Item symbol: whoever discovers this room draws an item card.',
  omen: 'Omen symbol: whoever discovers this room draws an omen card, then makes a haunt roll.',
}

/** Everything about one room: what it does, its current state, and who's in it. */
export default function RoomInfo({ view, uid, name, onClose, onMove }: {
  view: HauntedView; uid: string; name: (pid: string) => string; onClose: () => void; onMove?: () => void
}) {
  const t = view.tiles[uid]!
  const def = TILE_BY_ID.get(t.tileId)!
  const haunt = view.haunt?.number
  const lines: { text: string; color?: string }[] = []

  if (t.flipped === 'flooded') lines.push({ text: 'Flooded. The room is face down: it has doors on every side, and no symbols or room effects.', color: '#7cb9e8' })
  if (t.flipped === 'burning') lines.push({ text: 'Burning. The room is face down: it has doors on every side, and no symbols or room effects.', color: '#f4a261' })
  if (t.flipped === 'burning' || t.tokens.includes('fire')) {
    if (t.tokens.includes('fire')) lines.push({ text: 'On fire (fire token on a landing).', color: '#f4a261' })
    if (haunt === 44) lines.push({ text: 'Heroes take 1 General damage when they enter. The traitor and Mannequins are unharmed.', color: '#f4a261' })
  }
  if (t.tokens.includes('obstacle')) lines.push({ text: 'Obstacle: leaving this room costs 2 movement.' })
  if (t.tokens.includes('altar')) lines.push({ text: 'The altar. Heroes perform the ceremony here, and once the traitor enters they can’t leave.', color: '#f1e3c8' })
  if (!t.flipped) {
    if (def.rules) lines.push({ text: def.rules })
    for (const sym of new Set(def.symbols)) {
      const n = def.symbols.filter((x) => x === sym).length
      lines.push({ text: n > 1 ? `${SYMBOL_TEXT[sym].replace('an item card', `${n} item cards`)}` : SYMBOL_TEXT[sym], color: SYMBOL_INK[sym] })
    }
    if (!def.rules && !def.symbols.length) lines.push({ text: 'Nothing special happens here.' })
  }
  const people = Object.values(view.explorers).filter((e) => e.tile === uid && !e.removed)
  const monsters = view.monsters.filter((m) => m.tile === uid)
  const sides = new Set([...people.filter((e) => !e.dead).map((e) => e.side), ...(monsters.length ? ['traitor'] : [])])
  if (view.phase === 'haunt' && sides.has('hero') && sides.has('traitor')) {
    lines.push({ text: 'Opponents are in this room, so leaving it costs 2 movement.' })
  }

  return (
    <Modal title={def.name}>
      <p className="text-sm text-white/60">{REGION_STYLE[t.region].label} floor{def.landing ? ', landing' : ''}</p>
      <h2 className="font-display text-2xl font-bold">{t.flipped ? `${def.name} (${t.flipped})` : def.name}</h2>
      <ul className="mt-3 flex flex-col gap-2 text-sm">
        {lines.map((l) => (
          <li key={l.text} className="rounded-md bg-white/5 px-3 py-2" style={l.color ? { borderLeft: `3px solid ${l.color}` } : undefined}>
            {l.text}
          </li>
        ))}
      </ul>

      {(people.length > 0 || monsters.length > 0) && (
        <>
          <h3 className="mt-4 font-display text-lg font-bold">Here now</h3>
          <ul className="mt-2 flex flex-col gap-2">
            {people.map((e) => {
              const d = EXPLORER_BY_ID.get(e.explorerId)!
              const items = [...e.items, ...e.omens]
              return (
                <li key={e.pid} className="flex items-center gap-3">
                  <svg width="34" height="44" viewBox="-17 -28 34 44" aria-hidden="true"><ExplorerFigure explorerId={d.id} color={d.color} dead={e.dead} /></svg>
                  <span className="text-sm">
                    <span className="font-medium">{name(e.pid)}</span>
                    {e.side === 'traitor' && <span className="ml-1 text-red-300">traitor</span>}
                    {e.dead && <span className="ml-1 text-white/50">dead{items.length ? ': their cards can be looted' : ''}</span>}
                    {items.length > 0 && !e.dead && (
                      <span className="block text-xs text-white/50">
                        Carrying {items.map((c) => (c === 'hidden' ? 'a hidden omen' : CARD_BY_ID.get(c)?.name)).join(', ')}
                      </span>
                    )}
                  </span>
                </li>
              )
            })}
            {monsters.map((m) => (
              <li key={m.id} className="flex items-center gap-3">
                <svg width="34" height="44" viewBox="-17 -28 34 44" aria-hidden="true"><MonsterFigure kind={m.kind} stunned={m.stunned} /></svg>
                <span className="text-sm">
                  <span className="font-medium">{m.name}</span>
                  <span className="block text-xs text-white/60">
                    Might {m.might}, Speed {m.speed}, Sanity {m.sanity}, Knowledge {m.knowledge}.
                    {m.canStun ? ' Beating it in a fight stuns it for a turn.' : " Can't be stunned."}
                    {m.stunned ? ' Stunned right now.' : ''}
                  </span>
                </span>
              </li>
            ))}
          </ul>
        </>
      )}

      <div className="mt-5 flex gap-2">
        {onMove && <Button className="h-11 flex-1" onClick={onMove}>Move here</Button>}
        <Button variant="outline" className="h-11 flex-1" onClick={onClose}>Close</Button>
      </div>
    </Modal>
  )
}
