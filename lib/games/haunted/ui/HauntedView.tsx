'use client'

import { BookOpen, ScrollText } from 'lucide-react'
import { useEffect, useMemo, useRef, useState } from 'react'
import { Button } from '@/components/ui/button'
import type { GameViewProps } from '@/lib/games/ui'
import { CARD_BY_ID } from '../data/cards'
import { EXPLORER_BY_ID } from '../data/explorers'
import type { HauntedAction, Region } from '../types'
import type { HauntedView as View } from '../rules'
import Board from './Board'
import { describeWait, Modal, PromptPanel, promptOwner } from './Prompts'
import { CardChip, CardFace, CharacterSheet } from './Sheet'
import Setup from './Setup'
import DiceRolls from './DiceRolls'
import RoomInfo from './RoomInfo'
import { Die, REGION_STYLE } from './pieces'

type Pending = { kind: 'special'; id: string; label: string; options: string[] } | { kind: 'map'; card: string } | null

const REGION_TABS: Region[] = ['upper', 'ground', 'basement']

/** The game is always dark, whatever the site theme; shared buttons read these tokens. */
export const NIGHT = {
  '--background': '#120f16',
  '--foreground': '#f5efe6',
  '--card': '#1d1822',
  '--border': '#ffffff26',
  '--input': '#ffffff26',
  '--secondary': '#2a2430',
  '--muted': '#2a2430',
  '--muted-foreground': '#b7aec4',
  '--primary': '#f6d860',
  '--primary-foreground': '#1a1400',
  '--destructive': '#e5484d',
} as React.CSSProperties

export default function HauntedView(props: GameViewProps<View, HauntedAction>) {
  const { view, me, act, nameOf, isHost, playAgain, backToLobby } = props
  const explorerName = (pid: string) => {
    const ex = view.explorers[pid]
    return ex ? EXPLORER_BY_ID.get(ex.explorerId)!.name : nameOf(pid)
  }
  const who = (pid: string) => `${nameOf(pid)} (${explorerName(pid)})`

  const myEx = view.explorers[me]
  const myTile = myEx ? view.tiles[myEx.tile] : undefined
  const o = view.options
  const turn = view.turn
  const myTurn = turn?.pid === me && !view.prompt
  const monsterTurn = myTurn && turn?.actor === 'monsters'

  const [selectedMonster, setSelectedMonster] = useState<string | null>(null)
  const [pending, setPending] = useState<Pending>(null)
  const [showBrief, setShowBrief] = useState(false)
  const [showLog, setShowLog] = useState(false)
  const [card, setCard] = useState<string | null>(null)
  const [trading, setTrading] = useState(false)
  const [inspect, setInspect] = useState<string | null>(null)

  // Remember which monster moved last, so the camera can follow monster turns.
  const prevMonsterTiles = useRef<Record<string, string>>({})
  const [lastMonster, setLastMonster] = useState<string | null>(null)
  useEffect(() => {
    const moved = view.monsters.find((m) => prevMonsterTiles.current[m.id] && prevMonsterTiles.current[m.id] !== m.tile)
    prevMonsterTiles.current = Object.fromEntries(view.monsters.map((m) => [m.id, m.tile]))
    // Tracks game-state changes between renders.
     
    if (moved) setLastMonster(moved.id)
  }, [view.monsters])

  // The piece currently acting: whoever's turn it is, or the monster that just moved.
  const actingMonster = turn?.actor === 'monsters' ? (selectedMonster ?? lastMonster ?? view.monsters[0]?.id ?? null) : null
  const active = !turn || view.phase === 'over' ? null : actingMonster ? `m:${actingMonster}` : `p:${turn.pid}`
  const activeTile = actingMonster
    ? view.monsters.find((m) => m.id === actingMonster)?.tile
    : turn && !view.explorers[turn.pid]?.removed
      ? view.explorers[turn.pid]?.tile
      : undefined

  // The camera follows the acting piece; on your own turn, your explorer.
  const followTile = myTurn && !monsterTurn ? myEx?.tile : (activeTile ?? myEx?.tile)
  const followRegion = followTile ? view.tiles[followTile]?.region : undefined
  const [region, setRegion] = useState<Region>('ground')
  // Tapping a floor tab pins that floor until the turn changes.
  const [pinnedFor, setPinnedFor] = useState<string | null>(null)
  const turnKeyNow = `${turn?.pid}:${turn?.actor}`
  useEffect(() => {
    // Board follows the action between floors (external game state).
     
    if (followRegion && pinnedFor !== turnKeyNow) setRegion(followRegion)
  }, [followRegion, pinnedFor, turnKeyNow])
  const choosePrompt = view.prompt?.kind === 'chooseTile' && view.prompt.pid === me ? view.prompt : null
  useEffect(() => {
    const first = choosePrompt?.options[0]
     
    if (first && view.tiles[first]) setRegion(view.tiles[first]!.region)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [choosePrompt?.label])

  // Reset local selections when the turn changes.
  const turnKey = `${turn?.pid}:${turn?.actor}`
  useEffect(() => {
     
    setSelectedMonster(null)
    setPending(null)
  }, [turnKey])

  const highlight = useMemo(() => {
    const h: Record<string, 'move' | 'choose' | 'target'> = {}
    if (choosePrompt) for (const t of choosePrompt.options) h[t] = 'choose'
    else if (pending?.kind === 'special') for (const t of pending.options) h[t] = 'choose'
    else if (pending?.kind === 'map') for (const t of Object.keys(view.tiles)) h[t] = 'choose'
    else if (monsterTurn && selectedMonster) for (const t of o?.monsters.find((m) => m.id === selectedMonster)?.moves ?? []) h[t] = 'move'
    else if (myTurn && o) for (const t of o.moves) h[t] = 'move'
    return h
  }, [choosePrompt, pending, monsterTurn, selectedMonster, myTurn, o, view.tiles])

  if (view.phase === 'setup') return <div style={NIGHT} className="min-h-full bg-[#120f16] text-[#f5efe6]"><Setup {...props} /></div>

  function onTile(uid: string) {
    if (choosePrompt) return choosePrompt.options.includes(uid) && act({ type: 'chooseTile', tile: uid })
    if (pending?.kind === 'special') {
      if (!pending.options.includes(uid)) return
      act({ type: 'special', id: pending.id, tile: uid })
      return setPending(null)
    }
    if (pending?.kind === 'map') {
      act({ type: 'useItem', card: pending.card, tile: uid })
      return setPending(null)
    }
    if (monsterTurn && selectedMonster && highlight[uid]) return act({ type: 'monsterMove', monster: selectedMonster, tile: uid })
    if (myTurn && highlight[uid] === 'move') return act({ type: 'moveTo', tile: uid })
    // Not an action: show what's in the room.
    setInspect(uid)
  }

  const prompt = view.prompt
  const owner = prompt ? promptOwner(view, prompt) : null
  const promptIsMine = prompt && owner === me && prompt.kind !== 'chooseTile' && prompt.kind !== 'haunt'
  const lastRolls = view.rolls.slice(-3).reverse()
  const brief = view.haunt?.brief
  const traitorPid = view.haunt?.traitor

  const status = (() => {
    if (view.phase === 'over') return null
    if (prompt && prompt.kind === 'haunt') return 'The haunt has begun.'
    if (prompt && owner !== me) return `Waiting for ${owner ? nameOf(owner) : 'someone'}: ${describeWait(prompt)}.`
    if (choosePrompt) return choosePrompt.label + '. Tap a highlighted room.'
    if (pending?.kind === 'special') return 'Tap a highlighted room.'
    if (pending?.kind === 'map') return 'Tap any room to go there.'
    if (!turn) return null
    if (turn.pid !== me) return turn.actor === 'monsters' ? `${nameOf(turn.pid)} is moving the monsters.` : `${who(turn.pid)} is taking their turn.`
    if (monsterTurn) return 'Your monsters\' turn. Tap a monster, then a highlighted room to move it.'
    return `Your turn. ${turn.movesLeft} move${turn.movesLeft === 1 ? '' : 's'} left.`
  })()

  return (
    <div style={NIGHT} className="flex h-[calc(100dvh-var(--shell-head,3.25rem))] flex-col bg-[#120f16] text-[#f5efe6]">
      {/* Floor tabs */}
      <div className="flex items-center gap-1 border-b border-white/10 px-2 py-1.5">
        {REGION_TABS.map((r) => {
          const here = Object.values(view.explorers).filter((e) => !e.removed && view.tiles[e.tile]?.region === r).length
          return (
            <button key={r} type="button" onClick={() => { setRegion(r); setPinnedFor(turnKeyNow) }} aria-pressed={region === r}
              className={`rounded-md px-3 py-1.5 text-sm ${region === r ? 'bg-white/15 font-semibold' : 'text-white/60'}`}>
              {REGION_STYLE[r].label}
              {here > 0 && <span className="ml-1 text-xs text-white/50">{here}</span>}
            </button>
          )
        })}
        <span className="flex-1" />
        {view.haunt && (
          <button type="button" onClick={() => setShowBrief(true)} className="flex items-center gap-1 rounded-md px-2 py-1.5 text-sm text-[#f6d860]">
            <BookOpen className="size-4" /> Haunt
          </button>
        )}
        <button type="button" onClick={() => setShowLog(true)} className="flex items-center gap-1 rounded-md px-2 py-1.5 text-sm text-white/60" aria-label="Game log">
          <ScrollText className="size-4" />
        </button>
      </div>

      {status && (
        <p className={`px-4 py-2 text-sm ${myTurn || choosePrompt ? 'bg-[#f6d860] text-black' : 'bg-white/5 text-white/80'}`} role="status">
          {status}
        </p>
      )}

      <div className="relative min-h-0 flex-1">
        <DiceRolls rolls={view.rolls} />
        <Board
          view={view}
          region={region}
          highlight={highlight}
          explore={myTurn && !monsterTurn && o && myTile ? { from: myTile.uid, dirs: o.explore } : null}
          selectedMonster={selectedMonster}
          onTile={onTile}
          onExplore={(dir) => act({ type: 'move', dir })}
          onMonster={(id) => {
            if (monsterTurn) return setSelectedMonster(id)
            const tile = view.monsters.find((m) => m.id === id)?.tile
            if (tile) onTile(tile)
          }}
          focus={choosePrompt?.options[0] ?? (pending?.kind === 'special' ? pending.options[0] : undefined) ?? followTile ?? null}
          active={active}
        />
      </div>

      {/* Bottom panel */}
      <div className="max-h-[42dvh] overflow-y-auto border-t border-white/10 px-3 pb-4 pt-3">
        {lastRolls.length > 0 && (
          <div className="mb-3 flex flex-col gap-1">
            {lastRolls.slice(0, 1).map((r) => (
              <div key={r.id} className="flex flex-wrap items-center gap-1.5 text-sm">
                <span className="text-white/60">{r.by}, {r.label}:</span>
                {r.dice.map((d, i) => <Die key={i} value={d} size={22} />)}
                {r.bonus ? <span className="text-white/60">+{r.bonus}</span> : null}
                <strong className="ml-1 tabular-nums">= {r.total}</strong>
              </div>
            ))}
          </div>
        )}

        {myTurn && !monsterTurn && o && (
          <div className="mb-3 flex flex-wrap gap-2">
            {o.canLift && <Button size="sm" variant="outline" onClick={() => act({ type: 'special', id: 'lift' })}>Ride the lift</Button>}
            {o.specials.map((sp) => (
              <Button key={sp.id} size="sm" variant="outline" disabled={!!sp.reason} title={sp.reason ?? sp.rules}
                onClick={() => {
                  if (sp.tiles) return setPending({ kind: 'special', id: sp.id, label: sp.label, options: sp.tiles.options })
                  if (sp.count) {
                    const n = window.prompt(`${sp.count.label} (0-${sp.count.max})`, String(sp.count.max))
                    if (n === null) return
                    return act({ type: 'special', id: sp.id, count: Math.max(0, Math.min(sp.count.max, Number(n) || 0)) })
                  }
                  act({ type: 'special', id: sp.id })
                }}>
                {sp.label}
              </Button>
            ))}
            {o.attack.map((t) => {
              const name = t.id.startsWith('m:') ? t.name : explorerName(t.id.slice(2))
              const targetTile = t.id.startsWith('m:')
                ? view.monsters.find((m) => `m:${m.id}` === t.id)?.tile
                : view.explorers[t.id.slice(2)]?.tile
              return (
                <span key={t.id} className="flex gap-1">
                  {targetTile === myEx?.tile && (
                    <Button size="sm" variant="destructive" onClick={() => act({ type: 'attack', target: t.id, weapon: null })}>Attack {name}</Button>
                  )}
                  {t.weapons.map((w) => (
                    <Button key={w} size="sm" variant="destructive" onClick={() => act({ type: 'attack', target: t.id, weapon: w })}>
                      {CARD_BY_ID.get(w)!.name} → {name}
                    </Button>
                  ))}
                </span>
              )
            })}
            {o.loot.map((l) => (
              <Button key={l.card} size="sm" variant="outline" onClick={() => act({ type: 'loot', card: l.card })}>
                Take {CARD_BY_ID.get(l.card)?.name ?? 'card'}
              </Button>
            ))}
            {o.trade.length > 0 && <Button size="sm" variant="outline" onClick={() => setTrading(true)}>Trade</Button>}
            {pending && <Button size="sm" variant="ghost" onClick={() => setPending(null)}>Cancel</Button>}
            <Button size="sm" className="ml-auto" onClick={() => act({ type: 'endTurn' })}>End turn</Button>
          </div>
        )}

        {monsterTurn && o && (
          <div className="mb-3 flex flex-col gap-2">
            <div className="flex flex-wrap gap-2">
              {o.monsters.map((m) => {
                const mon = view.monsters.find((x) => x.id === m.id)!
                return (
                  <Button key={m.id} size="sm" variant={selectedMonster === m.id ? 'default' : 'outline'} onClick={() => {
                    setSelectedMonster(m.id)
                    setRegion(view.tiles[mon.tile]!.region)
                  }}>
                    {mon.name}: {m.movesLeft} move{m.movesLeft === 1 ? '' : 's'}{mon.stunned ? ' (stunned)' : ''}
                  </Button>
                )
              })}
            </div>
            <div className="flex flex-wrap gap-2">
              {o.monsters.filter((m) => m.id === selectedMonster).flatMap((m) =>
                m.targets.map((t) => (
                  <Button key={t} size="sm" variant="destructive" onClick={() => act({ type: 'monsterAttack', monster: m.id, target: `p:${t}` })}>
                    Attack {explorerName(t)}
                  </Button>
                )),
              )}
              {o.specials.map((sp) => (
                <Button key={sp.id} size="sm" variant="outline" disabled={!!sp.reason} title={sp.reason ?? sp.rules}
                  onClick={() => sp.tiles ? setPending({ kind: 'special', id: sp.id, label: sp.label, options: sp.tiles.options }) : act({ type: 'special', id: sp.id })}>
                  {sp.label}
                </Button>
              ))}
              {pending && <Button size="sm" variant="ghost" onClick={() => setPending(null)}>Cancel</Button>}
              <Button size="sm" className="ml-auto" onClick={() => act({ type: 'endMonsterTurn' })}>End monsters&apos; turn</Button>
            </div>
          </div>
        )}

        {myEx && !myEx.removed && (
          <>
            <CharacterSheet ex={myEx} />
            <div className="mt-2 flex flex-wrap gap-1.5">
              {[...myEx.items, ...myEx.omens].map((c) => (
                <CardChip key={c} id={c} onClick={() => setCard(c)} />
              ))}
              {myEx.items.length + myEx.omens.length === 0 && <span className="text-xs text-white/50">No cards yet.</span>}
            </div>
          </>
        )}
        {myEx?.removed && <p className="text-sm text-white/60">Your explorer is gone. You play the monsters.</p>}

        <details className="mt-3">
          <summary className="cursor-pointer text-sm text-white/60">Everyone</summary>
          <div className="mt-2 flex flex-col gap-2">
            {view.order.filter((p) => p !== me).map((pid) => {
              const ex = view.explorers[pid]!
              return (
                <div key={pid}>
                  <p className="mb-1 text-sm">
                    {who(pid)}
                    {pid === traitorPid && <span className="ml-1 text-red-300">traitor</span>}
                    {ex.removed && <span className="ml-1 text-white/50">gone</span>}
                  </p>
                  {!ex.removed && <CharacterSheet ex={ex} compact />}
                  <div className="mt-1 flex flex-wrap gap-1">
                    {[...ex.items, ...ex.omens].map((c, i) => <CardChip key={`${c}${i}`} id={c} onClick={c === 'hidden' ? undefined : () => setCard(c)} />)}
                  </div>
                </div>
              )
            })}
            {view.monsters.map((m) => (
              <p key={m.id} className="text-sm text-white/70">
                {m.name}: Might {m.might}, Speed {m.speed}{m.stunned ? ', stunned' : ''}
              </p>
            ))}
            <p className="text-xs text-white/50">
              Rooms left: {view.stackCount}. Omens found: {view.omensDrawn}. Decks: {view.decks.item} items, {view.decks.omen} omens.
            </p>
          </div>
        </details>
      </div>

      {/* Prompts for me */}
      {promptIsMine && <PromptPanel view={view} act={act} nameOf={nameOf} />}

      {/* Haunt reveal / briefing */}
      {(prompt?.kind === 'haunt' || showBrief) && view.haunt && brief && (
        <Modal title="The haunt">
          <p className="text-sm uppercase tracking-wide text-[#e76f6f]">Haunt {view.haunt.number}</p>
          <h2 className="font-display text-3xl font-extrabold">{view.haunt.title}</h2>
          <p className="mt-2 text-sm">
            {myEx?.side === 'traitor' ? 'You are the traitor.' : `${traitorPid ? who(traitorPid) : 'Someone'} is the traitor. You are a hero.`}
          </p>
          {view.haunt.substitute && (
            <p className="mt-1 text-xs text-white/50">The chart pointed to haunt {view.haunt.chartNumber}, which isn&apos;t built yet, so this one is played instead.</p>
          )}
          <p className="mt-3 italic text-white/80">{brief.intro}</p>
          <p className="mt-3 font-semibold text-[#f6d860]">{brief.goal}</p>
          <ul className="mt-2 list-disc space-y-1 pl-5 text-sm text-white/85">
            {brief.rules.map((r) => <li key={r}>{r}</li>)}
          </ul>
          {view.haunt.shared.length > 0 && (
            <>
              <h3 className="mt-5 font-display text-lg font-bold">What everyone can see</h3>
              <ul className="mt-1 list-disc space-y-1 pl-5 text-sm text-white/85">
                {view.haunt.shared.map((r) => <li key={r}>{r}</li>)}
              </ul>
            </>
          )}
          {view.haunt.otherBrief ? (
            <div className="mt-5 rounded-lg border border-white/15 p-3">
              <h3 className="font-display text-lg font-bold">{myEx?.side === 'traitor' ? "The heroes' rules" : "The traitor's rules"}</h3>
              <p className="text-xs text-white/50">Shown because teaching mode is on.</p>
              <p className="mt-2 font-semibold text-[#f6d860]">{view.haunt.otherBrief.goal}</p>
              <ul className="mt-1 list-disc space-y-1 pl-5 text-sm text-white/85">
                {view.haunt.otherBrief.rules.map((r) => <li key={r}>{r}</li>)}
              </ul>
            </div>
          ) : (
            <p className="mt-3 text-xs text-white/50">
              Keep your goal to yourself: the other side has different instructions. Watching what they do is part of the game.
            </p>
          )}
          {prompt?.kind === 'haunt' ? (
            owner === me || isHost ? (
              <Button className="mt-4 h-11 w-full" onClick={() => act({ type: 'continue' })}>Begin the haunt</Button>
            ) : (
              <p className="mt-4 text-center text-sm text-white/60">Waiting for {owner ? nameOf(owner) : 'the revealer'} to begin.</p>
            )
          ) : (
            <Button className="mt-4 h-11 w-full" variant="outline" onClick={() => setShowBrief(false)}>Close</Button>
          )}
        </Modal>
      )}

      {card && (
        <Modal title="Card">
          <CardFace id={card} />
          {myTurn && myEx && (myEx.items.includes(card) || myEx.omens.includes(card)) && ['mirror', 'medicine', 'firstAid', 'stopwatch', 'map'].includes(CARD_BY_ID.get(card)?.effect?.kind ?? '') && (
            <Button className="mt-3 w-full" onClick={() => {
              if (CARD_BY_ID.get(card)?.effect?.kind === 'map') setPending({ kind: 'map', card })
              else act({ type: 'useItem', card })
              setCard(null)
            }}>
              Use it
            </Button>
          )}
          <Button variant="outline" className="mt-2 w-full" onClick={() => setCard(null)}>Close</Button>
        </Modal>
      )}

      {trading && myEx && o && (
        <TradeModal view={view} me={me} partners={o.trade} name={explorerName} onClose={() => setTrading(false)}
          onOffer={(to, give, take) => { act({ type: 'offerTrade', to, give, take }); setTrading(false) }} />
      )}

      {inspect && view.tiles[inspect] && (
        <RoomInfo view={view} uid={inspect} name={who} onClose={() => setInspect(null)}
          onMove={myTurn && highlight[inspect] === 'move' ? () => { act({ type: 'moveTo', tile: inspect }); setInspect(null) } : undefined} />
      )}

      {showLog && (
        <Modal title="Game log">
          <h2 className="font-display text-xl font-bold">What happened</h2>
          <ol className="mt-3 flex flex-col-reverse gap-1.5 text-sm text-white/85">
            {view.log.map((l) => <li key={l.id}>{l.text}</li>)}
          </ol>
          <Button variant="outline" className="mt-4 w-full" onClick={() => setShowLog(false)}>Close</Button>
        </Modal>
      )}

      {view.phase === 'over' && (
        <Modal title="Game over">
          <p className="font-display text-4xl font-extrabold">{view.winner === 'heroes' ? 'The heroes win' : 'The traitor wins'}</p>
          <p className="mt-2 italic text-white/80">{view.winText}</p>
          {isHost ? (
            <div className="mt-5 flex flex-col gap-2">
              <Button className="h-11" onClick={playAgain}>Play again</Button>
              <Button className="h-11" variant="outline" onClick={backToLobby}>Back to lobby</Button>
            </div>
          ) : (
            <p className="mt-4 text-sm text-white/60">Waiting for the host.</p>
          )}
        </Modal>
      )}
    </div>
  )
}

function TradeModal({ view, me, partners, name, onClose, onOffer }: {
  view: View; me: string; partners: string[]; name: (p: string) => string
  onClose: () => void; onOffer: (to: string, give: string[], take: string[]) => void
}) {
  const [to, setTo] = useState(partners[0]!)
  const [give, setGive] = useState<string[]>([])
  const [take, setTake] = useState<string[]>([])
  const mine = [...view.explorers[me]!.items, ...view.explorers[me]!.omens]
  const theirs = [...view.explorers[to]!.items, ...view.explorers[to]!.omens].filter((c) => c !== 'hidden')
  const toggle = (list: string[], set: (x: string[]) => void, c: string) => set(list.includes(c) ? list.filter((x) => x !== c) : [...list, c])
  return (
    <Modal title="Trade">
      <h2 className="font-display text-xl font-bold">Trade</h2>
      <div className="mt-3 flex flex-wrap gap-2">
        {partners.map((p) => (
          <Button key={p} size="sm" variant={p === to ? 'default' : 'outline'} onClick={() => { setTo(p); setTake([]) }}>{name(p)}</Button>
        ))}
      </div>
      <p className="mt-4 text-sm text-white/60">You give</p>
      <div className="mt-1 flex flex-wrap gap-1">{mine.map((c) => <CardChip key={c} id={c} active={give.includes(c)} onClick={() => toggle(give, setGive, c)} />)}</div>
      <p className="mt-3 text-sm text-white/60">You ask for</p>
      <div className="mt-1 flex flex-wrap gap-1">{theirs.map((c) => <CardChip key={c} id={c} active={take.includes(c)} onClick={() => toggle(take, setTake, c)} />)}</div>
      <div className="mt-5 grid grid-cols-2 gap-2">
        <Button variant="outline" onClick={onClose}>Cancel</Button>
        <Button disabled={!give.length && !take.length} onClick={() => onOffer(to, give, take)}>Offer trade</Button>
      </div>
    </Modal>
  )
}

