/**
 * Haunted House as a GameModule for the room engine. The host runs these
 * pure functions; each player gets a personal view with hidden info removed.
 */
import type { GameModule, PlayerId } from '@/lib/engine/types'
import { CARD_BY_ID } from './data/cards'
import { HAUNTS } from './haunts'
import type { Briefing } from './haunts/types'
import { def, dirBetween, hasDoor, inSight, neighbors, tileAt } from './engine/board'
import { alive, env, hasCard } from './engine/core'
import { isOpponent, monstersOn } from './engine/haunt'
import { act, initialState, settle } from './engine/play'
import type { Dir, HauntedAction, HauntedState, PlacedTile } from './types'
import { DIRS, DX, DY } from './types'

export interface HauntedOptions {
  /** Tiles you can step to right now. */
  moves: string[]
  /** Unexplored doorways you can walk through. */
  explore: Dir[]
  attack: { id: string; name: string; weapons: string[] }[]
  loot: { card: string; from: PlayerId }[]
  trade: PlayerId[]
  specials: { id: string; label: string; rules: string; reason: string | null; count?: { label: string; max: number } | null; tiles?: { label: string; options: string[] } | null }[]
  canLift: boolean
  monsters: { id: string; moves: string[]; movesLeft: number; targets: PlayerId[]; attacked: boolean }[]
}

export interface HauntedView extends Omit<HauntedState, 'decks' | 'stack' | 'log' | 'haunt' | 'queue'> {
  me: PlayerId | null
  decks: { event: number; item: number; omen: number }
  stackCount: number
  log: { id: number; text: string }[]
  haunt: (Omit<NonNullable<HauntedState['haunt']>, 'data'> & { brief: Briefing | null; data: Record<string, unknown> }) | null
  options: HauntedOptions | null
}

function optionsFor(s: HauntedState, pid: PlayerId): HauntedOptions | null {
  const turn = s.turn
  const ex = s.explorers[pid]
  if (!turn || !ex || turn.pid !== pid || s.prompt || turn.ended || (s.phase !== 'explore' && s.phase !== 'haunt')) return null
  const haunt = s.haunt ? HAUNTS[s.haunt.number] : undefined

  if (turn.actor === 'monsters') {
    const monsters = s.monsters.map((m) => {
      const from = s.tiles[m.tile]!
      const heroesHere = Object.values(s.explorers).filter((e) => alive(e) && e.side === 'hero' && e.tile === m.tile)
      const left = turn.monsterMoves?.[m.id] ?? 0
      const cost = heroesHere.length ? 2 : 1
      let moves = left >= cost ? neighbors(s, from, { monster: true }).map((t) => t.uid) : []
      if (m.kind === 'shark' && left >= cost && from.flipped === 'flooded') {
        for (const d of DIRS) {
          const n = tileAt(s, from.region, from.x + DX[d]!, from.y + DY[d]!)
          if (n?.flipped === 'flooded' && !moves.includes(n.uid)) moves.push(n.uid)
        }
      }
      moves = [...new Set(moves)]
      const attacked = !!turn.monsterAttacked?.includes(m.id)
      return { id: m.id, moves, movesLeft: left, targets: attacked ? [] : heroesHere.map((h) => h.pid), attacked }
    })
    const specials = (haunt?.specials ?? [])
      .filter((sp) => sp.side === 'traitor')
      .map((sp) => ({
        id: sp.id,
        label: sp.label,
        rules: sp.rules,
        reason: turn.used.includes(`special:${sp.id}`) ? 'Already used this turn.' : sp.check(s, pid),
        tiles: sp.tilePrompt?.(s, pid) ?? null,
      }))
    return { moves: [], explore: [], attack: [], loot: [], trade: [], specials, canLift: false, monsters }
  }

  if (!alive(ex)) return null
  const tile = s.tiles[ex.tile]!
  const block = s.phase === 'haunt' ? haunt?.blockLeave?.(s, pid) : null
  const opponentsHere =
    s.phase === 'haunt' &&
    (Object.values(s.explorers).some((o) => alive(o) && o.tile === tile.uid && isOpponent(s, pid, o.pid)) ||
      (ex.side === 'hero' && monstersOn(s, tile.uid).length > 0))
  const cost = tile.tokens.includes('obstacle') || opponentsHere ? 2 : 1
  const canMove = !block && turn.movesLeft >= cost

  const moves: string[] = []
  const explore: Dir[] = []
  if (canMove) {
    for (const n of neighbors(s, tile)) moves.push(n.uid)
    const key = hasCard(ex, 'skeletonKey')
    if (key && !ex.newThisTurn.includes(key)) {
      for (const d of DIRS) {
        const n = tileAt(s, tile.region, tile.x + DX[d]!, tile.y + DY[d]!)
        if (n && !moves.includes(n.uid)) moves.push(n.uid)
      }
    }
    const canDiscover = !(s.phase === 'haunt' && ex.side === 'traitor') && s.stack.length > 0
    for (const d of DIRS) {
      if (!hasDoor(tile, d)) continue
      if (!tileAt(s, tile.region, tile.x + DX[d]!, tile.y + DY[d]!) && canDiscover) explore.push(d)
    }
  }

  const attack: HauntedOptions['attack'] = []
  const loot: HauntedOptions['loot'] = []
  if (s.phase === 'haunt' && !turn.attacked) {
    const weapons = [...ex.items, ...ex.omens].filter(
      (c) => !ex.newThisTurn.includes(c) && ['weapon', 'dynamite'].includes(CARD_BY_ID.get(c)?.effect?.kind ?? ''),
    )
    const consider = (id: string, name: string, at: PlacedTile) => {
      const ws = weapons.filter((w) => {
        const e = CARD_BY_ID.get(w)!.effect!
        if (at.uid === tile.uid) return true
        if (e.kind === 'dynamite') return neighbors(s, tile).includes(at)
        if (e.kind !== 'weapon') return false
        return (e.range === 'adjacent' && neighbors(s, tile).includes(at)) || (e.range === 'sight' && inSight(s, tile, at))
      })
      if (at.uid === tile.uid || ws.length) attack.push({ id, name, weapons: ws })
    }
    for (const o of Object.values(s.explorers)) {
      if (o.pid !== pid && alive(o) && isOpponent(s, pid, o.pid)) consider(`p:${o.pid}`, o.pid, s.tiles[o.tile]!)
    }
    if (ex.side === 'hero') for (const m of s.monsters) consider(`m:${m.id}`, m.name, s.tiles[m.tile]!)
  }
  if (s.phase === 'haunt' && !turn.looted) {
    for (const body of Object.values(s.explorers)) {
      if (body.dead && !body.removed && body.tile === tile.uid) {
        for (const c of [...body.items, ...body.omens]) loot.push({ card: c, from: body.pid })
      }
    }
  }
  const trade = turn.traded
    ? []
    : Object.values(s.explorers)
        .filter((o) => o.pid !== pid && alive(o) && o.tile === tile.uid && !isOpponent(s, pid, o.pid))
        .map((o) => o.pid)
  const specials = (haunt?.specials ?? [])
    .filter((sp) => sp.side === ex.side && !(sp.side === 'traitor' && haunt?.monsterTurn === 'instead'))
    .map((sp) => ({
      id: sp.id,
      label: sp.label,
      rules: sp.rules,
      reason: turn.used.includes(`special:${sp.id}`) ? 'Already used this turn.' : sp.check(s, pid),
      count: sp.countPrompt?.(s, pid) ?? null,
      tiles: sp.tilePrompt?.(s, pid) ?? null,
    }))
  const canLift = turn.enteredElevator && !turn.elevatorUsed && def(tile).effect?.kind === 'elevator' && !tile.flipped
  return { moves, explore, attack, loot, trade, specials, canLift, monsters: [] }
}

function viewFor(s: HauntedState, me: PlayerId | null): HauntedView {
  const myEx = me ? s.explorers[me] : undefined
  const iAmTraitor = myEx?.side === 'traitor'
  // Haunt 30: heroes' omens are hidden from the traitor unless revealed.
  const hideOmens = s.phase === 'haunt' && s.haunt?.number === 30 && iAmTraitor
  const explorers = Object.fromEntries(
    Object.entries(s.explorers).map(([pid, ex]) => {
      if (!hideOmens || ex.side !== 'hero') return [pid, ex]
      return [pid, { ...ex, omens: ex.omens.map((c) => (ex.revealed.includes(c) ? c : 'hidden')) }]
    }),
  )
  const hauntDef = s.haunt ? HAUNTS[s.haunt.number] : undefined
  const brief = hauntDef && myEx ? (myEx.side === 'traitor' ? hauntDef.traitor : hauntDef.hero) : null
  const { decks, stack, log, haunt, queue: _queue, ...rest } = s
  void _queue
  return {
    ...rest,
    explorers,
    me,
    decks: { event: decks.event.length, item: decks.item.length, omen: decks.omen.length },
    stackCount: stack.length,
    log: log.filter((l) => !l.to || (me && l.to.includes(me))).map(({ id, text }) => ({ id, text })),
    haunt: haunt ? { ...haunt, brief } : null,
    options: me ? optionsFor(s, me) : null,
  }
}

export const hauntedHouse: GameModule<HauntedState, HauntedAction, HauntedView> = {
  id: 'haunted',
  name: 'Haunted House',
  description:
    'Explore a creaking old house room by room, gathering items and omens. Then the haunt begins: one of you turns traitor, and each side races to its own goal.',
  minPlayers: 3,
  maxPlayers: 6,

  setup(players) {
    return initialState(players)
  },

  action(state, pid, action, ctx) {
    env.ctx = ctx
    const s = structuredClone(state)
    const err = act(s, pid, action)
    if (err) return { error: err }
    settle(s)
    return { state: s }
  },

  view(state, pid) {
    return viewFor(state, pid)
  },

  playerLeft(state, pid, ctx) {
    env.ctx = ctx
    const s = structuredClone(state)
    if (s.phase === 'setup') {
      s.seats = s.seats.filter((p) => p !== pid)
      delete s.picks[pid]
      return s
    }
    const ex = s.explorers[pid]
    if (!ex) return s
    if (ex.side === 'traitor' && s.phase === 'haunt') {
      s.phase = 'over'
      s.winner = 'heroes'
      s.winText = 'The traitor fled the house.'
      return s
    }
    ex.removed = true
    ex.dead = true
    s.order = s.order.filter((p) => p !== pid)
    if (s.prompt && 'pid' in s.prompt && s.prompt.pid === pid) s.prompt = null
    s.queue = s.queue.filter((p) => !('pid' in p) || p.pid !== pid)
    if (s.turn?.pid === pid) {
      s.turn.ended = true
      s.turn.endFx = true
    }
    settle(s)
    return s
  },

  isOver(state) {
    return state.phase === 'over'
  },
}

export { dirBetween }
