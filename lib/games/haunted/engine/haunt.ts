/**
 * Haunt phase: starting the haunt, choosing the traitor, combat, monsters,
 * looting, and routing haunt-specific actions.
 */
import type { PlayerId } from '@/lib/engine/types'
import { CARD_BY_ID, omenOf } from '../data/cards'
import { EXPLORER_BY_ID } from '../data/explorers'
import { SCENARIO_BY_ID, type TraitorRule } from '../data/scenarios'
import { HAUNTS, IMPLEMENTED, SUBSTITUTES } from '../haunts'
import type { HauntDef } from '../haunts/types'
import type { HauntedAction, HauntedState, ItemEffect, MonsterState, PlacedTile } from '../types'
import { distances, gridAdjacent, inSight, neighbors } from './board'
import { alive, ask, cardName, damage, log, lose, nameOf, rand, recordRoll, rollDice, value } from './core'
import { bury, settle, traitDice } from './play'

export function currentHaunt(s: HauntedState): HauntDef | undefined {
  return s.haunt ? HAUNTS[s.haunt.number] : undefined
}

export function isOpponent(s: HauntedState, a: PlayerId, b: PlayerId): boolean {
  const x = s.explorers[a]?.side
  const y = s.explorers[b]?.side
  return s.phase === 'haunt' && !!x && !!y && x !== y && x !== 'none' && y !== 'none'
}

export function monstersOn(s: HauntedState, tile: string): MonsterState[] {
  return s.monsters.filter((m) => m.tile === tile)
}

export function traitorPid(s: HauntedState): PlayerId | null {
  return s.haunt?.traitor ?? null
}

/* ------------------------------------------------------------------ */
/*  Starting the haunt                                                 */
/* ------------------------------------------------------------------ */

export function chooseTraitor(s: HauntedState, rule: TraitorRule, revealer: PlayerId): PlayerId {
  const order = s.order
  const i = order.indexOf(revealer)
  // Players in turn order starting with the revealer (ties go to whoever is closest).
  const fromRevealer = [...order.slice(i), ...order.slice(0, i)].filter((p) => alive(s.explorers[p]))
  if (rule === 'revealer') return revealer
  if (rule === 'leftOfRevealer') return fromRevealer[1] ?? revealer
  if (rule === 'oldest') {
    return fromRevealer.reduce((best, p) =>
      EXPLORER_BY_ID.get(s.explorers[p]!.explorerId)!.age > EXPLORER_BY_ID.get(s.explorers[best]!.explorerId)!.age ? p : best,
    )
  }
  if (rule === 'mostOmens') {
    return fromRevealer.reduce((best, p) => (s.explorers[p]!.omens.length > s.explorers[best]!.omens.length ? p : best))
  }
  if (typeof rule === 'object') {
    const trait = 'highest' in rule ? rule.highest : rule.lowest
    const pool = rule.excludeRevealer ? fromRevealer.slice(1) : fromRevealer
    const sign = 'highest' in rule ? 1 : -1
    return pool.reduce((best, p) =>
      sign * (value(s.explorers[p]!, trait) - value(s.explorers[best]!, trait)) > 0 ? p : best,
    )
  }
  return revealer
}

export function startHaunt(s: HauntedState, revealer: PlayerId, omenCard: string) {
  const scenario = SCENARIO_BY_ID.get(s.scenario ?? '')!
  const omen = omenOf(omenCard)!
  const entry = scenario.chart[omen]
  let number = entry.haunt
  let substitute = false
  if (!IMPLEMENTED.includes(number)) {
    substitute = true
    number = SUBSTITUTES[Math.floor(rand() * SUBSTITUTES.length)]!
  }
  const haunt = HAUNTS[number]!
  const rule = substitute ? haunt.traitorRule : entry.traitor
  const traitor = chooseTraitor(s, rule, revealer)

  s.phase = 'haunt'
  s.haunt = { number, title: haunt.title, traitor, revealer, substitute, chartNumber: entry.haunt, data: {} }
  for (const ex of Object.values(s.explorers)) ex.side = ex.pid === traitor ? 'traitor' : 'hero'
  log(s, `The haunt begins: ${haunt.title}. ${nameOf(s, traitor)} has betrayed the group!`)
  if (substitute) log(s, `(Haunt ${entry.haunt} isn't built yet, so haunt ${number} is played instead.)`)

  // The revealer's turn ends; play resumes to the traitor's left.
  s.queue = []
  s.prompt = null
  s.turn!.ended = true
  s.turn!.endFx = true
  const ti = s.order.indexOf(traitor)
  s.nextPid = s.order[(ti + 1) % s.order.length]!
  haunt.setup(s)
  // Everyone reads their briefing before any setup choices or play.
  const pending = s.prompt ? [s.prompt] : []
  s.prompt = { kind: 'haunt', stage: 'reveal' }
  s.queue = [...pending, ...s.queue]
}

/* ------------------------------------------------------------------ */
/*  Combat                                                             */
/* ------------------------------------------------------------------ */

type Ref = { kind: 'explorer'; pid: PlayerId } | { kind: 'monster'; m: MonsterState }

function parseRef(s: HauntedState, id: string): Ref | null {
  if (id.startsWith('m:')) {
    const m = s.monsters.find((x) => x.id === id.slice(2))
    return m ? { kind: 'monster', m } : null
  }
  const pid = id.startsWith('p:') ? id.slice(2) : id
  return s.explorers[pid] ? { kind: 'explorer', pid } : null
}

function refTile(s: HauntedState, r: Ref): string {
  return r.kind === 'monster' ? r.m.tile : s.explorers[r.pid]!.tile
}

function refName(s: HauntedState, r: Ref): string {
  return r.kind === 'monster' ? r.m.name : nameOf(s, r.pid)
}

function sideOf(s: HauntedState, r: Ref): 'hero' | 'traitor' {
  return r.kind === 'monster' ? 'traitor' : (s.explorers[r.pid]!.side as 'hero' | 'traitor')
}

/** Roll for one side of an attack. */
function combatDice(s: HauntedState, r: Ref, trait: 'might' | 'speed', defending: boolean, extra = 0): number[] {
  if (r.kind === 'monster') return rollDice(Math.max(1, (trait === 'might' ? r.m.might : r.m.speed) + extra))
  const ex = s.explorers[r.pid]!
  let n = traitDice(s, ex, trait) + extra
  if (defending && ex.items.some((c) => CARD_BY_ID.get(c)?.effect?.kind === 'jacket')) n += 1
  return rollDice(n)
}

function resolveAttack(
  s: HauntedState,
  attacker: Ref,
  defender: Ref,
  weapon: string | null,
): void {
  const w = weapon ? (CARD_BY_ID.get(weapon)?.effect as Extract<ItemEffect, { kind: 'weapon' }> | undefined) : undefined
  const trait = w?.trait ?? 'might'
  const aDice = combatDice(s, attacker, trait, false, w?.extraDice ?? 0)
  const dDice = combatDice(s, defender, trait, true)
  const aTotal = recordRoll(s, refName(s, attacker), `Attack (${trait}${weapon ? `, ${cardName(weapon)}` : ''})`, aDice, w?.addResult ?? 0)
  const dTotal = recordRoll(s, refName(s, defender), `Defend (${trait})`, dDice)
  if (attacker.kind === 'explorer' && w?.speedCost) {
    lose(s, s.explorers[attacker.pid]!, 'speed', w.speedCost)
  }
  if (attacker.kind === 'explorer' && defender.kind === 'explorer' && s.explorers[attacker.pid]!.side === 'traitor') {
    currentHaunt(s)?.onTraitorAttack?.(s, defender.pid)
  }
  const margin = aTotal - dTotal
  log(s, `${refName(s, attacker)} attacks ${refName(s, defender)}: ${aTotal} vs ${dTotal}.`)
  if (margin === 0) {
    log(s, 'Neither side gives ground.')
    return
  }
  const winner = margin > 0 ? attacker : defender
  const loser = margin > 0 ? defender : attacker
  const amount = Math.abs(margin)
  if (margin < 0 && w?.noDamageIfLose) {
    log(s, `${refName(s, attacker)} misses but stays out of reach.`)
    return
  }
  // An explorer who wins an attack against another explorer by 2+ may steal instead.
  if (margin >= 2 && winner.kind === 'explorer' && loser.kind === 'explorer' && winner === attacker) {
    const victim = s.explorers[loser.pid]!
    if (victim.items.length + victim.omens.length > 0) {
      ask(s, { kind: 'attackResult', pid: winner.pid, target: loser.pid, margin: amount, canSteal: true })
      return
    }
  }
  hurt(s, loser, amount, `${refName(s, winner)} wins the fight.`)
}

function hurt(s: HauntedState, r: Ref, amount: number, reason: string) {
  if (r.kind === 'monster') {
    if (r.m.canStun) {
      r.m.stunned = true
      log(s, `${r.m.name} is stunned.`)
    } else {
      log(s, `${r.m.name} shrugs it off.`)
    }
    return
  }
  damage(s, r.pid, 'physical', amount, reason, { fromAttack: true })
}

function attackAction(s: HauntedState, pid: PlayerId, targetId: string, weapon: string | null): string | null {
  const err = playerCanAct(s, pid)
  if (err) return err
  if (s.phase !== 'haunt') return 'There is no fighting before the haunt.'
  if (s.turn!.attacked) return 'You already attacked this turn.'
  const ex = s.explorers[pid]!
  const target = parseRef(s, targetId)
  if (!target) return 'No such target.'
  const me: Ref = { kind: 'explorer', pid }
  if (sideOf(s, target) === ex.side) return "That's your teammate."
  if (target.kind === 'explorer' && !alive(s.explorers[target.pid])) return 'They are already dead.'

  if (weapon) {
    if (!ex.items.includes(weapon) && !ex.omens.includes(weapon)) return "You don't have that weapon."
    if (ex.newThisTurn.includes(weapon)) return "You can't attack with a weapon you got this turn."
  }
  const eff = weapon ? CARD_BY_ID.get(weapon)?.effect : undefined
  if (eff?.kind === 'dynamite') return dynamite(s, pid, weapon!, refTile(s, target))
  if (weapon && eff?.kind !== 'weapon') return "That isn't a weapon."

  const myTile = s.tiles[ex.tile]!
  const theirTile = s.tiles[refTile(s, target)]!
  const range = eff?.kind === 'weapon' ? eff.range : undefined
  const ok =
    myTile.uid === theirTile.uid ||
    (range === 'adjacent' && neighbors(s, myTile).includes(theirTile)) ||
    (range === 'sight' && inSight(s, myTile, theirTile))
  if (!ok) return 'Out of reach.'
  s.turn!.attacked = true
  if (weapon) s.turn!.used.push(weapon)
  resolveAttack(s, me, target, weapon)
  return null
}

function dynamite(s: HauntedState, pid: PlayerId, card: string, tileUid: string): string | null {
  const ex = s.explorers[pid]!
  const mine = s.tiles[ex.tile]!
  const tile = s.tiles[tileUid]!
  if (tile.uid !== mine.uid && !neighbors(s, mine).includes(tile)) return 'Throw it at your tile or an adjacent one.'
  s.turn!.attacked = true
  bury(s, ex, card)
  log(s, `${nameOf(s, pid)} lights the dynamite!`)
  for (const other of Object.values(s.explorers)) {
    if (!alive(other) || other.tile !== tile.uid) continue
    const total = recordRoll(s, nameOf(s, other.pid), 'Dynamite: Speed roll', rollDice(traitDice(s, other, 'speed')))
    if (total <= 3) damage(s, other.pid, 'physical', 4, 'Caught in the blast.')
  }
  for (const m of monstersOn(s, tile.uid)) {
    const total = recordRoll(s, m.name, 'Dynamite: Speed roll', rollDice(m.speed))
    if (total <= 3) hurt(s, { kind: 'monster', m }, 4, 'Caught in the blast.')
  }
  return null
}

function stealOrDamage(s: HauntedState, pid: PlayerId, card: string | null): string | null {
  const p = s.prompt
  if (p?.kind !== 'attackResult' || p.pid !== pid) return 'Nothing to decide.'
  const victim = s.explorers[p.target]!
  s.prompt = null
  if (card) {
    if (!victim.items.includes(card) && !victim.omens.includes(card)) return 'They do not have that.'
    const omen = victim.omens.includes(card)
    victim.items = victim.items.filter((c) => c !== card)
    victim.omens = victim.omens.filter((c) => c !== card)
    const me = s.explorers[pid]!
    if (omen) me.omens.push(card)
    else me.items.push(card)
    me.newThisTurn.push(card)
    log(s, `${nameOf(s, pid)} steals the ${cardName(card)} from ${nameOf(s, victim.pid)}.`)
    return null
  }
  damage(s, victim.pid, 'physical', p.margin, `${nameOf(s, pid)} wins the fight.`, { fromAttack: true })
  return null
}

function loot(s: HauntedState, pid: PlayerId, card: string): string | null {
  const err = playerCanAct(s, pid)
  if (err) return err
  if (s.turn!.looted) return 'You already looted this turn.'
  const me = s.explorers[pid]!
  const body = Object.values(s.explorers).find(
    (e) => e.dead && !e.removed && e.tile === me.tile && (e.items.includes(card) || e.omens.includes(card)),
  )
  if (!body) return 'There is nothing like that here.'
  const omen = body.omens.includes(card)
  body.items = body.items.filter((c) => c !== card)
  body.omens = body.omens.filter((c) => c !== card)
  if (omen) me.omens.push(card)
  else me.items.push(card)
  me.newThisTurn.push(card)
  s.turn!.looted = true
  log(s, `${nameOf(s, pid)} takes the ${cardName(card)} from ${nameOf(s, body.pid)}'s body.`)
  return null
}

/* ------------------------------------------------------------------ */
/*  Monsters                                                           */
/* ------------------------------------------------------------------ */

export function startMonsterTurn(s: HauntedState) {
  const turn = s.turn!
  turn.monsterMoves = {}
  turn.monsterAttacked = []
  const rolled = new Map<string, number>()
  for (const m of s.monsters) {
    if (m.stunned) {
      m.stunned = false
      turn.monsterMoves[m.id] = 0
      turn.monsterAttacked.push(m.id)
      log(s, `${m.name} recovers from being stunned.`)
      continue
    }
    // Mannequins that start in a hero's sight only roll 2 dice.
    const watched =
      m.kind === 'mannequin' &&
      Object.values(s.explorers).some((e) => alive(e) && e.side === 'hero' && inSight(s, s.tiles[e.tile]!, s.tiles[m.tile]!))
    const key = watched ? `${m.kind}:watched` : m.kind
    if (!rolled.has(key)) {
      const dice = watched ? 2 : m.speed
      const total = recordRoll(s, m.name, 'movement', rollDice(dice))
      rolled.set(key, Math.max(1, total))
    }
    turn.monsterMoves[m.id] = rolled.get(key)!
  }
}

function monsterMove(s: HauntedState, pid: PlayerId, id: string, tileUid: string): string | null {
  const err = monsterTurnCheck(s, pid)
  if (err) return err
  const m = s.monsters.find((x) => x.id === id)
  if (!m) return 'No such monster.'
  const from = s.tiles[m.tile]!
  const to = s.tiles[tileUid]
  if (!to) return 'No such tile.'
  const left = s.turn!.monsterMoves![m.id] ?? 0
  const heroesHere = Object.values(s.explorers).some((e) => alive(e) && e.side === 'hero' && e.tile === from.uid)
  const cost = heroesHere ? 2 : 1
  if (!neighbors(s, from, { monster: true }).includes(to)) {
    // The ghost shark swims through any flooded water.
    if (!(m.kind === 'shark' && to.flipped === 'flooded' && from.flipped === 'flooded' && gridAdjacent(s, from).includes(to))) {
      return "It can't get there in one move."
    }
  }
  if (left < cost) return 'No movement left for that monster.'
  s.turn!.monsterMoves![m.id] = left - cost
  m.tile = to.uid
  return null
}

function monsterAttack(s: HauntedState, pid: PlayerId, id: string, target: string): string | null {
  const err = monsterTurnCheck(s, pid)
  if (err) return err
  const m = s.monsters.find((x) => x.id === id)
  if (!m) return 'No such monster.'
  if (s.turn!.monsterAttacked!.includes(m.id)) return 'That monster already attacked.'
  const t = parseRef(s, target)
  if (!t || t.kind !== 'explorer') return 'Monsters attack heroes.'
  const ex = s.explorers[t.pid]!
  if (!alive(ex) || ex.side !== 'hero') return 'Pick a living hero.'
  if (ex.tile !== m.tile) return 'The hero must be on the same tile.'
  s.turn!.monsterAttacked!.push(m.id)
  s.turn!.monsterMoves![m.id] = 0
  resolveAttack(s, { kind: 'monster', m }, t, null)
  return null
}

function monsterTurnCheck(s: HauntedState, pid: PlayerId): string | null {
  if (s.prompt) return 'Finish the current step first.'
  if (s.turn?.pid !== pid || s.turn.actor !== 'monsters') return "It isn't the monsters' turn."
  return null
}

function endMonsterTurn(s: HauntedState, pid: PlayerId): string | null {
  const err = monsterTurnCheck(s, pid)
  if (err) return err
  s.turn!.ended = true
  currentHaunt(s)?.onMonsterTurnEnd?.(s)
  return null
}

/* ------------------------------------------------------------------ */
/*  Routing                                                            */
/* ------------------------------------------------------------------ */

function playerCanAct(s: HauntedState, pid: PlayerId): string | null {
  if (s.prompt) return 'Finish the current step first.'
  if (s.turn?.pid !== pid || s.turn.actor !== 'player') return "It's not your turn."
  if (s.turn.ended) return 'Your turn is ending.'
  if (!alive(s.explorers[pid])) return 'Your explorer is out of the game.'
  return null
}

export function handleHauntAction(s: HauntedState, pid: PlayerId, a: HauntedAction): string | null {
  const p = s.prompt
  if (p) {
    if (a.type === 'continue' && p.kind === 'haunt') {
      if (pid !== s.haunt?.revealer && pid !== s.seats[0]) return 'Waiting for the haunt revealer to continue.'
      s.prompt = null
      return null
    }
    if (a.type === 'steal') return stealOrDamage(s, pid, a.card)
    if (a.type === 'chooseTile' && p.kind === 'chooseTile') {
      if (p.pid !== pid) return 'Someone else is choosing.'
      if (!p.options.includes(a.tile)) return 'Pick one of the highlighted tiles.'
      s.prompt = null
      currentHaunt(s)?.onChooseTile?.(s, p, a.tile)
      return null
    }
    return 'Finish the current step first.'
  }
  switch (a.type) {
    case 'attack':
      return attackAction(s, pid, a.target, a.weapon ?? null)
    case 'loot':
      return loot(s, pid, a.card)
    case 'monsterMove':
      return monsterMove(s, pid, a.monster, a.tile)
    case 'monsterAttack':
      return monsterAttack(s, pid, a.monster, a.target)
    case 'endMonsterTurn':
      return endMonsterTurn(s, pid)
    case 'special': {
      const haunt = currentHaunt(s)
      const sp = haunt?.specials.find((x) => x.id === a.id)
      if (!sp) return 'Unknown action.'
      const ex = s.explorers[pid]!
      if (sp.side !== ex.side) return "That isn't your side's action."
      const monsterSpecial = sp.side === 'traitor' && haunt!.monsterTurn === 'instead'
      const err = monsterSpecial ? monsterTurnCheck(s, pid) : playerCanAct(s, pid)
      if (err) return err
      if (s.turn!.used.includes(`special:${sp.id}`)) return 'You can only do that once per turn.'
      const why = sp.check(s, pid)
      if (why) return why
      const res = sp.run(s, pid, { tile: a.tile, count: a.count })
      if (!res) s.turn!.used.push(`special:${sp.id}`)
      return res
    }
    default:
      return 'Unknown action.'
  }
}

/** Tiles a hero could be moved to within `steps` moves (used by Compel). */
export function reachable(s: HauntedState, from: PlacedTile, steps: number): string[] {
  const d = distances(s, from)
  return [...d.entries()].filter(([, n]) => n <= steps).map(([uid]) => uid)
}

export { settle }
