/**
 * Turn engine: setup, movement, exploring, cards, trait rolls, items,
 * trading and turn order. Haunt-phase combat and monsters live in haunt.ts.
 */
import type { PlayerId } from '@/lib/engine/types'
import { CARD_BY_ID, EVENT_BY_ID, EVENTS, ITEMS, OMENS, isWeapon } from '../data/cards'
import { EXPLORER_BY_ID } from '../data/explorers'
import { ROOM_TILES, TILE_BY_ID } from '../data/tiles'
import type {
  Continuation,
  Dir,
  EventOutcome,
  ExplorerState,
  HauntedAction,
  HauntedState,
  PendingRoll,
  PlacedTile,
  Region,
  Trait,
} from '../types'
import { DX, DY, MENTAL, PHYSICAL, TRAITS, opposite } from '../types'
import {
  def,
  dirBetween,
  hasDoor,
  neighbors,
  openDoorways,
  place,
  placedByTileId,
  tileAt,
  validRotations,
} from './board'
import {
  allocate,
  alive,
  ask,
  askFirst,
  cardName,
  damage,
  gain,
  hasCard,
  heal,
  log,
  lose,
  nameOf,
  rand,
  recordRoll,
  rollDice,
  shuffle,
  track,
  value,
} from './core'
import {
  currentHaunt,
  handleHauntAction,
  isOpponent,
  monstersOn,
  startHaunt,
  startMonsterTurn,
} from './haunt'

/* ------------------------------------------------------------------ */
/*  Setup                                                              */
/* ------------------------------------------------------------------ */

export function initialState(seats: PlayerId[]): HauntedState {
  return {
    phase: 'setup',
    seats,
    scenario: null,
    picks: Object.fromEntries(seats.map((p) => [p, null])),
    explorers: {},
    order: [],
    turn: null,
    tiles: {},
    stack: [],
    decks: { event: [], item: [], omen: [] },
    omensDrawn: 0,
    prompt: null,
    queue: [],
    rolls: [],
    log: [],
    haunt: null,
    monsters: [],
    winner: null,
    winText: null,
    seq: 0,
    buried: [],
    nextPid: null,
  }
}

function beginExploring(s: HauntedState) {
  // Starting tiles: the ground floor strip, plus the two landings.
  const entrance = place(s, 'entrance', 'ground', 0, 0, 0)
  place(s, 'hallway', 'ground', 0, -1, 0)
  place(s, 'groundStairs', 'ground', 0, -2, 0)
  place(s, 'upperLanding', 'upper', 0, 0, 0)
  place(s, 'basementLanding', 'basement', 0, 0, 0)

  s.stack = shuffle(ROOM_TILES.map((t) => t.id))
  s.decks = {
    event: shuffle(EVENTS.map((e) => e.id)),
    item: shuffle(ITEMS.map((c) => c.id)),
    omen: shuffle(OMENS.map((c) => c.id)),
  }
  for (const pid of s.seats) {
    const exId = s.picks[pid]!
    const ex = EXPLORER_BY_ID.get(exId)!
    s.explorers[pid] = {
      pid,
      explorerId: exId,
      idx: Object.fromEntries(TRAITS.map((t) => [t, ex.traits[t].start])) as Record<Trait, number>,
      tile: entrance.uid,
      items: [],
      omens: [],
      dead: false,
      side: 'none',
      revealed: [],
      newThisTurn: [],
      extraTurns: 0,
    }
  }
  // Turn order goes around the table; a random player starts.
  const start = Math.floor(rand() * s.seats.length)
  s.order = [...s.seats.slice(start), ...s.seats.slice(0, start)]
  s.phase = 'explore'
  log(s, `Everyone gathers in the Entrance Hall. ${nameOf(s, s.order[0]!)} goes first.`)
  startTurn(s, s.order[0]!)
}

/* ------------------------------------------------------------------ */
/*  Turns                                                              */
/* ------------------------------------------------------------------ */

export function startTurn(s: HauntedState, pid: PlayerId, actor: 'player' | 'monsters' = 'player') {
  const ex = s.explorers[pid]!
  ex.newThisTurn = []
  s.turn = {
    pid,
    actor,
    movesLeft: actor === 'player' ? value(ex, 'speed') : 0,
    attacked: false,
    traded: false,
    looted: false,
    used: [],
    elevatorUsed: false,
    enteredElevator: false,
    ended: false,
    endFx: actor === 'monsters',
  }
  if (actor === 'monsters') {
    startMonsterTurn(s)
    return
  }
  if (s.phase === 'haunt' && ex.side === 'hero') currentHaunt(s)?.onHeroTurnStart?.(s, pid)
}

function endTurnEffects(s: HauntedState) {
  const turn = s.turn!
  const ex = s.explorers[turn.pid]!
  if (!alive(ex)) return
  const tile = s.tiles[ex.tile]!
  const effect = tile.flipped ? undefined : def(tile).effect
  if (effect?.kind === 'furnace') {
    damage(s, ex.pid, 'physical', 1, 'The furnace room scorches you.')
  } else if (effect?.kind === 'chute') {
    const landing = placedByTileId(s, 'basementLanding')!
    ex.tile = landing.uid
    log(s, `${nameOf(s, ex.pid)} slides down the laundry chute to the Basement Landing.`)
  } else if (effect?.kind === 'collapsed') {
    traitRoll(s, ex.pid, 'speed', 'Collapsed Room: Speed roll', { kind: 'collapsed' })
  }
  // Tooth Necklace: gain 1 in a critical trait.
  if (hasCard(ex, 'necklace')) {
    const crit = TRAITS.find((t) => ex.idx[t] === 0)
    if (crit) {
      gain(s, ex, crit, 1)
      log(s, `${nameOf(s, ex.pid)}'s necklace restores 1 ${crit}.`)
    }
  }
}

function nextTurn(s: HauntedState) {
  const turn = s.turn!
  const haunt = currentHaunt(s)
  const cur = s.explorers[turn.pid]!

  // Monsters go right after the traitor's own turn.
  if (haunt && haunt.monsterTurn === 'after' && turn.actor === 'player' && cur.side === 'traitor' && s.monsters.length) {
    startTurn(s, turn.pid, 'monsters')
    return
  }
  if (turn.actor === 'player' && cur.extraTurns > 0 && alive(cur)) {
    cur.extraTurns--
    log(s, `${nameOf(s, cur.pid)} takes another turn.`)
    startTurn(s, cur.pid)
    return
  }

  let next: PlayerId | null = s.nextPid
  s.nextPid = null
  if (!next) {
    const i = s.order.indexOf(turn.pid)
    for (let k = 1; k <= s.order.length; k++) {
      const cand = s.order[(i + k) % s.order.length]!
      if (canTakeTurn(s, cand)) {
        next = cand
        break
      }
    }
  }
  if (!next) return
  const nex = s.explorers[next]!
  const instead = haunt?.monsterTurn === 'instead' && nex.side === 'traitor'
  if (instead || (nex.side === 'traitor' && !alive(nex))) startTurn(s, next, 'monsters')
  else startTurn(s, next)
}

function canTakeTurn(s: HauntedState, pid: PlayerId): boolean {
  const ex = s.explorers[pid]!
  if (!ex.dead && !ex.removed) return true
  // A dead or removed traitor still runs the monsters.
  return s.phase === 'haunt' && ex.side === 'traitor' && s.monsters.length > 0
}

/**
 * Run whatever happens automatically once nobody needs to decide anything:
 * end-of-turn effects, the next turn, and win checks.
 */
export function settle(s: HauntedState) {
  for (let guard = 0; guard < 50; guard++) {
    if (s.phase === 'over') return
    if (s.phase === 'haunt') {
      const win = currentHaunt(s)?.checkWin(s)
      if (win) {
        s.phase = 'over'
        s.winner = win.winner
        s.winText = win.text
        s.prompt = null
        s.queue = []
        log(s, win.winner === 'heroes' ? 'The heroes win!' : 'The traitor wins!')
        return
      }
    }
    if (!s.prompt && s.queue.length) {
      s.prompt = s.queue.shift()!
      continue
    }
    if (s.prompt || !s.turn) return
    const turn = s.turn
    const ex = s.explorers[turn.pid]!
    if (turn.actor === 'player' && !alive(ex)) turn.ended = true
    if (!turn.ended) return
    if (!turn.endFx) {
      turn.endFx = true
      endTurnEffects(s)
      continue
    }
    const before = s.turn
    if (turn.actor === 'player' && s.phase === 'haunt') currentHaunt(s)?.onTurnEnd?.(s, turn.pid, 'player')
    if (s.prompt) {
      // Haunt rules asked for something before the turn passes on.
      continue
    }
    if (s.turn === before) nextTurn(s)
  }
}

/* ------------------------------------------------------------------ */
/*  Trait rolls (with reroll items)                                    */
/* ------------------------------------------------------------------ */

export function traitDice(s: HauntedState, ex: ExplorerState, t: Trait, opts: { event?: boolean } = {}): number {
  let n = value(ex, t)
  if (t === 'knowledge' && hasCard(ex, 'camera')) n = Math.max(n, value(ex, 'sanity'))
  if (opts.event && hasCard(ex, 'flashlight')) n += 2
  return n
}

/** Reroll tools this explorer could use on a roll right now. */
function rerollTools(s: HauntedState, ex: ExplorerState): string[] {
  const used = s.turn?.pid === ex.pid ? s.turn.used : []
  return [...ex.items, ...ex.omens].filter((c) => {
    const k = CARD_BY_ID.get(c)?.effect?.kind
    if (!k || ex.newThisTurn.includes(c)) return false
    if (k === 'feather') return true
    if (k === 'doll' || k === 'coin' || k === 'rabbitFoot' || k === 'idol') return !used.includes(c)
    return false
  })
}

export function traitRoll(
  s: HauntedState,
  pid: PlayerId,
  t: Trait,
  label: string,
  then: Continuation,
  opts: { event?: boolean; extraDice?: number; bonus?: number } = {},
) {
  const ex = s.explorers[pid]!
  const dice = rollDice(traitDice(s, ex, t, opts) + (opts.extraDice ?? 0))
  const roll: PendingRoll = { label, dice, bonus: opts.bonus ?? 0, trait: t, rerolled: [], then }
  if (rerollTools(s, ex).length) {
    recordRoll(s, nameOf(s, pid), label, dice, roll.bonus)
    askFirst(s, { kind: 'reroll', pid, roll })
    return
  }
  const total = recordRoll(s, nameOf(s, pid), label, dice, roll.bonus)
  resolveRoll(s, pid, total, then)
}

function applyRerollTool(s: HauntedState, pid: PlayerId, card: string, die?: number, chosen?: number): string | null {
  const p = s.prompt
  if (p?.kind !== 'reroll' || p.pid !== pid) return 'Nothing to reroll.'
  const ex = s.explorers[pid]!
  if (!rerollTools(s, ex).includes(card) || p.roll.rerolled.includes(card)) return "You can't use that now."
  const kind = CARD_BY_ID.get(card)!.effect!.kind
  const roll = p.roll
  if (kind === 'feather') {
    const v = chosen ?? -1
    if (!Number.isInteger(v) || v < 0 || v > 8) return 'Pick a result from 0 to 8.'
    bury(s, ex, card)
    s.prompt = null
    log(s, `${nameOf(s, pid)} buries the ${cardName(card)} and sets the result to ${v}.`)
    const total = recordRoll(s, nameOf(s, pid), `${roll.label} (feather)`, [], v + roll.bonus)
    resolveRoll(s, pid, total, roll.then)
    return null
  }
  s.turn?.used.push(card)
  roll.rerolled.push(card)
  if (kind === 'doll') {
    roll.dice = rollDice(roll.dice.length)
    lose(s, ex, 'sanity', 1)
  } else if (kind === 'coin') {
    let blanks = 0
    roll.dice = roll.dice.map((d) => {
      if (d !== 0) return d
      const r = rollDice(1)[0]!
      if (r === 0) blanks++
      return r
    })
    if (blanks) damage(s, pid, 'mental', blanks, 'The coin takes its toll.')
  } else if (kind === 'rabbitFoot') {
    const i = die ?? -1
    if (i < 0 || i >= roll.dice.length) return 'Pick a die to reroll.'
    roll.dice[i] = rollDice(1)[0]!
  } else if (kind === 'idol') {
    roll.dice = [...roll.dice, ...rollDice(2)]
    damage(s, pid, 'mental', 1, 'The idol drinks from your mind.')
  }
  recordRoll(s, nameOf(s, pid), `${roll.label} (${cardName(card)})`, roll.dice, roll.bonus)
  if (!rerollTools(s, ex).some((c) => !roll.rerolled.includes(c))) return acceptRoll(s, pid)
  return null
}

function acceptRoll(s: HauntedState, pid: PlayerId): string | null {
  const p = s.prompt
  if (p?.kind !== 'reroll' || p.pid !== pid) return 'Nothing to accept.'
  s.prompt = null
  const total = p.roll.dice.reduce((a, b) => a + b, 0) + p.roll.bonus
  resolveRoll(s, pid, total, p.roll.then)
  return null
}

function resolveRoll(s: HauntedState, pid: PlayerId, total: number, then: Continuation) {
  const ex = s.explorers[pid]!
  switch (then.kind) {
    case 'eventResult':
      applyEvent(s, pid, then.cardId, total)
      return
    case 'collapsed':
      if (total >= 5) {
        log(s, `${nameOf(s, pid)} keeps their footing.`)
      } else {
        const landing = placedByTileId(s, 'basementLanding')!
        ex.tile = landing.uid
        log(s, `The floor gives way. ${nameOf(s, pid)} falls to the Basement Landing.`)
        const dmg = recordRoll(s, nameOf(s, pid), 'Fall damage', rollDice(1))
        damage(s, pid, 'physical', dmg, 'You fell through the floor.')
      }
      return
    case 'special':
      currentHaunt(s)?.specials.find((x) => x.id === then.id)?.resolve?.(s, pid, total, then.data)
      return
    default:
      return
  }
}

/* ------------------------------------------------------------------ */
/*  Cards                                                              */
/* ------------------------------------------------------------------ */

function drawCard(s: HauntedState, pid: PlayerId, kind: 'event' | 'item' | 'omen') {
  const ex = s.explorers[pid]!
  if (kind === 'event') {
    const id = s.decks.event.shift()
    if (!id) return
    s.decks.event.push(id) // events are buried after resolving
    ask(s, { kind: 'event', pid, cardId: id, stage: 'read' })
    return
  }
  const deck = s.decks[kind]
  const id = deck.shift()
  if (!id) {
    log(s, `The ${kind} deck is empty.`)
    return
  }
  if (kind === 'item') ex.items.push(id)
  else ex.omens.push(id)
  ex.newThisTurn.push(id)
  ask(s, { kind: 'card', pid, cardId: id })
}

/** The player has read a drawn item/omen: apply its effects. */
function takeCard(s: HauntedState, pid: PlayerId, cardId: string) {
  const ex = s.explorers[pid]!
  const card = CARD_BY_ID.get(cardId)!
  log(s, `${nameOf(s, pid)} finds the ${card.name}.`)
  for (const [t, n] of Object.entries(card.onDraw ?? {}) as [Trait, number][]) gain(s, ex, t, n)
  if (card.kind === 'omen' && s.phase === 'explore') {
    s.omensDrawn++
    const dice = rollDice(s.omensDrawn)
    const total = recordRoll(s, nameOf(s, pid), `Haunt roll (${s.omensDrawn} ${s.omensDrawn === 1 ? 'die' : 'dice'})`, dice)
    if (total >= 5 || s.decks.omen.length === 0) {
      startHaunt(s, pid, cardId)
    } else {
      log(s, `Haunt roll: ${total}. The house stays quiet... for now.`)
    }
  }
}

function applyEvent(s: HauntedState, pid: PlayerId, cardId: string, total: number) {
  const ev = EVENT_BY_ID.get(cardId)!
  const row = ev.outcomes.find((o) => total >= o.min) ?? ev.outcomes[ev.outcomes.length - 1]!
  log(s, `${ev.name}: ${row.text}`)
  applyOutcome(s, pid, row.outcome)
}

function applyOutcome(s: HauntedState, pid: PlayerId, o: EventOutcome) {
  const ex = s.explorers[pid]!
  switch (o.kind) {
    case 'nothing':
      return
    case 'gain':
      if (o.trait === 'physical' || o.trait === 'mental' || o.trait === 'any') {
        const traits = o.trait === 'physical' ? PHYSICAL : o.trait === 'mental' ? MENTAL : TRAITS
        ask(s, { kind: 'gainChoice', pid, traits, amount: o.amount, reason: 'Choose a trait to gain' })
      } else gain(s, ex, o.trait, o.amount)
      return
    case 'lose':
      lose(s, ex, o.trait, o.amount)
      return
    case 'damage': {
      const n = o.dice ? recordRoll(s, nameOf(s, pid), 'Damage', rollDice(o.amount)) : o.amount
      if (n > 0) damage(s, pid, o.type, n, 'Event damage')
      return
    }
    case 'drawItem':
      drawCard(s, pid, 'item')
      return
    case 'teleport': {
      const map = { basementLanding: 'basementLanding', entrance: 'entrance', upperLanding: 'upperLanding' } as const
      ex.tile = placedByTileId(s, map[o.to])!.uid
      return
    }
    case 'heal':
      heal(ex, o.traits)
      return
    case 'multi':
      for (const x of o.outcomes) applyOutcome(s, pid, x)
      return
  }
}

export function bury(s: HauntedState, ex: ExplorerState, card: string) {
  ex.items = ex.items.filter((c) => c !== card)
  ex.omens = ex.omens.filter((c) => c !== card)
  s.buried.push(card)
}

/* ------------------------------------------------------------------ */
/*  Movement and exploring                                             */
/* ------------------------------------------------------------------ */

function leaveCost(s: HauntedState, ex: ExplorerState): number {
  const tile = s.tiles[ex.tile]!
  let cost = 1
  if (tile.tokens.includes('obstacle')) cost = 2
  if (s.phase === 'haunt') {
    const opponents =
      Object.values(s.explorers).some((o) => alive(o) && o.tile === tile.uid && isOpponent(s, ex.pid, o.pid)) ||
      (ex.side === 'hero' && monstersOn(s, tile.uid).length > 0)
    if (opponents) cost = 2
  }
  return cost
}

function canAct(s: HauntedState, pid: PlayerId): string | null {
  if (s.phase !== 'explore' && s.phase !== 'haunt') return 'The game is not in play.'
  if (s.prompt) return 'Finish the current step first.'
  if (s.turn?.pid !== pid || s.turn.actor !== 'player') return "It's not your turn."
  if (s.turn.ended) return 'Your turn is ending.'
  if (!alive(s.explorers[pid])) return 'Your explorer is out of the game.'
  return null
}

/** Move an explorer onto a tile (after paying), and run entry effects. */
export function enter(s: HauntedState, ex: ExplorerState, tile: PlacedTile) {
  ex.tile = tile.uid
  if (s.turn?.pid === ex.pid && def(tile).effect?.kind === 'elevator' && !tile.flipped) s.turn.enteredElevator = true
  if (s.phase === 'haunt') currentHaunt(s)?.onEnter?.(s, ex.pid, tile)
}

function moveTo(s: HauntedState, pid: PlayerId, uid: string): string | null {
  const err = canAct(s, pid)
  if (err) return err
  const ex = s.explorers[pid]!
  const from = s.tiles[ex.tile]!
  const to = s.tiles[uid]
  if (!to) return 'No such tile.'
  const block = s.phase === 'haunt' ? currentHaunt(s)?.blockLeave?.(s, pid) : null
  if (block) return block
  const turn = s.turn!
  const cost = leaveCost(s, ex)
  if (turn.movesLeft < cost) return 'Not enough movement left.'

  if (neighbors(s, from).includes(to)) {
    turn.movesLeft -= cost
    enter(s, ex, to)
    return null
  }
  // Bone Key: walk through a wall into a placed neighbor.
  const key = hasCard(ex, 'skeletonKey')
  if (key && dirBetween(from, to) !== null && !ex.newThisTurn.includes(key)) {
    turn.movesLeft -= cost
    const r = recordRoll(s, nameOf(s, pid), 'Bone Key', rollDice(1))
    if (r === 0) {
      bury(s, ex, key)
      log(s, `The Bone Key crumbles to dust.`)
    }
    enter(s, ex, to)
    return null
  }
  return "You can't get there from here."
}

/** Move through an unexplored doorway: draw a room for this region. */
function explore(s: HauntedState, pid: PlayerId, dir: Dir): string | null {
  const err = canAct(s, pid)
  if (err) return err
  const ex = s.explorers[pid]!
  const from = s.tiles[ex.tile]!
  if (!hasDoor(from, dir)) return 'There is no door that way.'
  const x = from.x + DX[dir]!
  const y = from.y + DY[dir]!
  const existing = tileAt(s, from.region, x, y)
  if (existing) return moveTo(s, pid, existing.uid)
  if (s.phase === 'haunt' && ex.side === 'traitor') return "Traitors can't discover new rooms."
  const block = s.phase === 'haunt' ? currentHaunt(s)?.blockLeave?.(s, pid) : null
  if (block) return block
  const cost = leaveCost(s, ex)
  if (s.turn!.movesLeft < cost) return 'Not enough movement left.'

  // Draw until a tile fits this region and can be placed; bury the rest.
  const tried: string[] = []
  let found: { id: string; options: number[] } | null = null
  while (s.stack.length && tried.length < s.stack.length + tried.length) {
    const id = s.stack.shift()!
    const t = TILE_BY_ID.get(id)!
    const options = t.regions.includes(from.region) ? validRotations(s, id, from.region, x, y, opposite(dir)) : []
    if (options.length) {
      found = { id, options }
      break
    }
    tried.push(id)
    if (tried.length > 60) break
  }
  s.stack.push(...tried)
  if (!found) return 'No room in the stack fits there.'
  s.turn!.movesLeft -= cost
  ask(s, { kind: 'place', pid, tileId: found.id, at: { region: from.region, x, y }, from: from.uid, options: found.options, viaDir: dir })
  return null
}

function placeTile(s: HauntedState, pid: PlayerId, rot: number): string | null {
  const p = s.prompt
  if (p?.kind !== 'place' || p.pid !== pid) return 'Nothing to place.'
  if (!p.options.includes(rot)) return 'That rotation does not connect.'
  s.prompt = null
  const ex = s.explorers[pid]!
  const tile = place(s, p.tileId, p.at.region, p.at.x, p.at.y, rot)
  log(s, `${nameOf(s, pid)} discovers the ${def(tile).name}.`)
  enter(s, ex, tile)
  discoverEffects(s, pid, tile)
  if (s.phase === 'haunt') currentHaunt(s)?.onDiscover?.(s, tile)
  // Discovering a room ends your turn (after resolving it).
  s.turn!.ended = true
  return null
}

function discoverEffects(s: HauntedState, pid: PlayerId, tile: PlacedTile) {
  const ex = s.explorers[pid]!
  const d = def(tile)
  const eff = d.effect
  if (eff?.kind === 'gainOnDiscover') gain(s, ex, eff.trait, eff.amount)
  if (eff?.kind === 'obstacle') tile.tokens.push('obstacle')
  if (eff?.kind === 'armory') {
    const skipped: string[] = []
    let weapon: string | null = null
    while (s.decks.item.length) {
      const c = s.decks.item.shift()!
      if (isWeapon(c)) {
        weapon = c
        break
      }
      skipped.push(c)
    }
    s.buried.push(...skipped)
    if (weapon) {
      ex.items.push(weapon)
      ex.newThisTurn.push(weapon)
      ask(s, { kind: 'card', pid, cardId: weapon })
    }
  }
  if (eff?.kind === 'panicRoom') placeSecretStairs(s)
  if (s.phase !== 'haunt' || !(ex.side === 'traitor')) {
    for (const sym of d.symbols) drawCard(s, pid, sym)
  }
}

/** Put the Secret Staircase into the basement if it isn't in the house yet. */
export function placeSecretStairs(s: HauntedState) {
  if (placedByTileId(s, 'secretStairs')) return
  const i = s.stack.indexOf('secretStairs')
  if (i >= 0) s.stack.splice(i, 1)
  for (const spot of shuffle(openDoorways(s, 'basement'))) {
    const rots = validRotations(s, 'secretStairs', 'basement', spot.x, spot.y, opposite(spot.dir))
    if (rots.length) {
      place(s, 'secretStairs', 'basement', spot.x, spot.y, rots[0]!)
      log(s, 'A hidden staircase is revealed in the basement.')
      break
    }
  }
  s.stack = shuffle(s.stack)
}

/* ------------------------------------------------------------------ */
/*  Lift                                                               */
/* ------------------------------------------------------------------ */

function rideLift(s: HauntedState, pid: PlayerId): string | null {
  const err = canAct(s, pid)
  if (err) return err
  const ex = s.explorers[pid]!
  const tile = s.tiles[ex.tile]!
  if (def(tile).effect?.kind !== 'elevator' || tile.flipped) return 'You are not in the lift.'
  if (!s.turn!.enteredElevator || s.turn!.elevatorUsed) return 'The lift only moves once, when you step in.'
  s.turn!.elevatorUsed = true
  const roll = recordRoll(s, nameOf(s, pid), 'Wandering Lift', rollDice(2))
  if (roll >= 4) {
    ask(s, { kind: 'elevator', pid, roll })
    return null
  }
  moveLift(s, tile, roll === 3 ? 'upper' : roll === 2 ? 'ground' : 'basement')
  return null
}

function moveLift(s: HauntedState, tile: PlacedTile, region: Region) {
  for (const spot of shuffle(openDoorways(s, region))) {
    if (spot.from.uid === tile.uid) continue
    const rots = validRotations(s, tile.tileId, region, spot.x, spot.y, opposite(spot.dir))
    if (!rots.length) continue
    const moved = place(s, tile.tileId, region, spot.x, spot.y, rots[0]!)
    for (const ex of Object.values(s.explorers)) if (ex.tile === tile.uid) ex.tile = moved.uid
    for (const m of s.monsters) if (m.tile === tile.uid) m.tile = moved.uid
    delete s.tiles[tile.uid]
    log(s, `The lift rattles off to the ${region === 'ground' ? 'ground floor' : region === 'upper' ? 'upper floor' : 'basement'}.`)
    return
  }
  log(s, 'The lift shudders but goes nowhere.')
}

/* ------------------------------------------------------------------ */
/*  Items                                                              */
/* ------------------------------------------------------------------ */

function playItem(s: HauntedState, pid: PlayerId, card: string, target?: string, tileUid?: string): string | null {
  const err = canAct(s, pid)
  if (err) return err
  const ex = s.explorers[pid]!
  if (!ex.items.includes(card) && !ex.omens.includes(card)) return "You don't have that."
  if (ex.newThisTurn.includes(card)) return "You can't use a card on the turn you got it."
  if (s.turn!.used.includes(card)) return 'Already used this turn.'
  const kind = CARD_BY_ID.get(card)?.effect?.kind
  switch (kind) {
    case 'firstAid': {
      const who = target ? s.explorers[target] : ex
      if (!alive(who) || who.tile !== ex.tile) return 'They need to be on your tile.'
      heal(who, TRAITS.filter((t) => who.idx[t] === 0))
      bury(s, ex, card)
      log(s, `${nameOf(s, pid)} uses the First Aid Kit on ${who === ex ? 'themselves' : nameOf(s, who.pid)}.`)
      return null
    }
    case 'map': {
      const to = tileUid ? s.tiles[tileUid] : null
      if (!to) return 'Pick a tile.'
      bury(s, ex, card)
      enter(s, ex, to)
      log(s, `${nameOf(s, pid)} follows the map to the ${def(to).name}.`)
      return null
    }
    case 'mirror':
      heal(ex, ['knowledge', 'sanity'])
      bury(s, ex, card)
      log(s, `${nameOf(s, pid)} gazes into the mirror and steadies.`)
      return null
    case 'medicine':
      heal(ex, ['might', 'speed'])
      bury(s, ex, card)
      log(s, `${nameOf(s, pid)} drinks the tonic.`)
      return null
    case 'stopwatch':
      if (s.phase !== 'haunt') return 'Only after the haunt has started.'
      ex.extraTurns++
      bury(s, ex, card)
      log(s, `${nameOf(s, pid)} winds the watch backward.`)
      return null
    default:
      return "That card isn't used like that."
  }
}

/* ------------------------------------------------------------------ */
/*  Trading                                                            */
/* ------------------------------------------------------------------ */

function offerTrade(s: HauntedState, pid: PlayerId, to: PlayerId, give: string[], take: string[]): string | null {
  const err = canAct(s, pid)
  if (err) return err
  if (s.turn!.traded) return 'You already traded this turn.'
  const a = s.explorers[pid]!
  const b = s.explorers[to]
  if (!alive(b) || b.tile !== a.tile || to === pid) return 'Trade with someone on your tile.'
  if (s.phase === 'haunt' && isOpponent(s, pid, to)) return "You can't trade with the other side."
  if (!give.length && !take.length) return 'Choose something to trade.'
  const mine = [...a.items, ...a.omens]
  const theirs = [...b.items, ...b.omens]
  if (!give.every((c) => mine.includes(c)) || !take.every((c) => theirs.includes(c))) return 'Those cards are not available.'
  if (give.some((c) => s.turn!.used.includes(c))) return "You can't trade a card you used this turn."
  ask(s, { kind: 'trade', from: pid, to, give, take })
  return null
}

function answerTrade(s: HauntedState, pid: PlayerId, accept: boolean): string | null {
  const p = s.prompt
  if (p?.kind !== 'trade' || p.to !== pid) return 'No trade to answer.'
  s.prompt = null
  if (!accept) {
    log(s, `${nameOf(s, pid)} turns down the trade.`)
    return null
  }
  const a = s.explorers[p.from]!
  const b = s.explorers[p.to]!
  const move = (from: ExplorerState, toEx: ExplorerState, c: string) => {
    const omen = from.omens.includes(c)
    from.items = from.items.filter((x) => x !== c)
    from.omens = from.omens.filter((x) => x !== c)
    if (omen) toEx.omens.push(c)
    else toEx.items.push(c)
  }
  p.give.forEach((c) => move(a, b, c))
  p.take.forEach((c) => move(b, a, c))
  s.turn!.traded = true
  log(s, `${nameOf(s, p.from)} and ${nameOf(s, p.to)} trade.`)
  return null
}

/* ------------------------------------------------------------------ */
/*  Prompt answers                                                     */
/* ------------------------------------------------------------------ */

function answer(s: HauntedState, pid: PlayerId, a: HauntedAction): string | null {
  const p = s.prompt!
  switch (a.type) {
    case 'place':
      return placeTile(s, pid, a.rot)
    case 'allocate': {
      if (p.kind !== 'damage' || p.pid !== pid) return 'Nothing to allocate.'
      const err = allocate(s, s.explorers[pid]!, p.type, p.amount, a.split)
      if (err) return err
      s.prompt = null
      return null
    }
    case 'gainPick': {
      if (p.kind !== 'gainChoice' || p.pid !== pid) return 'Nothing to choose.'
      if (!p.traits.includes(a.trait)) return 'Pick one of the listed traits.'
      gain(s, s.explorers[pid]!, a.trait, p.amount)
      s.prompt = null
      return null
    }
    case 'rollEvent': {
      if (p.kind !== 'event' || p.pid !== pid) return 'No event to roll for.'
      const ev = EVENT_BY_ID.get(p.cardId)!
      s.prompt = null
      if (!ev.roll) applyEvent(s, pid, ev.id, 0)
      else traitRoll(s, pid, ev.roll, `${ev.name}: ${ev.roll} roll`, { kind: 'eventResult', cardId: ev.id }, { event: true })
      return null
    }
    case 'continue': {
      if (p.kind === 'card' && p.pid === pid) {
        s.prompt = null
        takeCard(s, pid, p.cardId)
        return null
      }
      if (p.kind === 'event' && p.pid === pid) return answer(s, pid, { type: 'rollEvent' })
      return handleHauntAction(s, pid, a)
    }
    case 'reroll':
      return applyRerollTool(s, pid, a.item, a.die, a.value)
    case 'acceptRoll':
      return acceptRoll(s, pid)
    case 'answerTrade':
      return answerTrade(s, pid, a.accept)
    case 'elevatorRegion': {
      if (p.kind !== 'elevator' || p.pid !== pid) return 'Not riding the lift.'
      s.prompt = null
      moveLift(s, s.tiles[s.explorers[pid]!.tile]!, a.region)
      return null
    }
    default:
      return handleHauntAction(s, pid, a)
  }
}

/* ------------------------------------------------------------------ */
/*  Dispatch                                                           */
/* ------------------------------------------------------------------ */

export function act(s: HauntedState, pid: PlayerId, a: HauntedAction): string | null {
  if (s.phase === 'over') return 'The game is over.'
  if (s.phase === 'setup') return setupAction(s, pid, a)
  if (!s.explorers[pid]) return "You're watching this game."

  if (s.prompt) return answer(s, pid, a)

  switch (a.type) {
    case 'move':
      return explore(s, pid, a.dir)
    case 'moveTo':
      return moveTo(s, pid, a.tile)
    case 'endTurn': {
      const err = canAct(s, pid)
      if (err) return err
      s.turn!.ended = true
      return null
    }
    case 'useItem':
      return playItem(s, pid, a.card, a.target, a.tile)
    case 'offerTrade':
      return offerTrade(s, pid, a.to, a.give, a.take)
    case 'special':
      if (a.id === 'lift') return rideLift(s, pid)
      return handleHauntAction(s, pid, a)
    default:
      return handleHauntAction(s, pid, a)
  }
}

function setupAction(s: HauntedState, pid: PlayerId, a: HauntedAction): string | null {
  if (!s.seats.includes(pid)) return "You're watching this game."
  if (a.type === 'pickExplorer') {
    const ex = EXPLORER_BY_ID.get(a.explorerId)
    if (!ex) return 'Unknown explorer.'
    const takenColors = Object.entries(s.picks)
      .filter(([p, id]) => p !== pid && id)
      .map(([, id]) => EXPLORER_BY_ID.get(id!)!.colorName)
    if (takenColors.includes(ex.colorName)) return `Someone already plays the ${ex.colorName.toLowerCase()} board.`
    s.picks[pid] = a.explorerId
    return null
  }
  if (a.type === 'pickScenario') {
    if (pid !== s.seats[0]) return 'The host picks the scenario.'
    s.scenario = a.scenarioId
    return null
  }
  if (a.type === 'begin') {
    if (pid !== s.seats[0]) return 'The host starts the game.'
    if (!s.scenario) return 'Pick a scenario first.'
    if (s.seats.some((p) => !s.picks[p])) return 'Everyone needs an explorer.'
    beginExploring(s)
    return null
  }
  return 'Pick explorers first.'
}

export { track }
