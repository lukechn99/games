/**
 * Haunt 44 (The Missing Friend + Mask). Traitor: left of the haunt revealer.
 * The traitor is a mannequin-maker with plastic helpers; the heroes must
 * burn every room in the house.
 */
import { gridAdjacent, isLanding, placedByTileId } from '../engine/board'
import { alive, damage, heal, log, nameOf } from '../engine/core'
import { traitRoll } from '../engine/play'
import type { HauntedState, PlacedTile } from '../types'
import { TRAITS } from '../types'
import type { HauntDef } from './types'
import { addMonster, allHeroesDead, byCount, chooseTile, heroes, livingHeroes, nextHero, traitor } from './util'

type Data = { burned?: boolean; pending?: string[]; fires?: string[][] }
const data = (s: HauntedState) => s.haunt!.data as Data

const GROUND_LANDING = ['entrance', 'hallway', 'groundStairs']

export function isBurning(t: PlacedTile) {
  return t.flipped === 'burning' || t.tokens.includes('fire')
}

function setFire(s: HauntedState, t: PlacedTile) {
  if (isBurning(t)) return
  if (isLanding(t)) {
    // The three ground-floor starting rooms count as one landing.
    const group = GROUND_LANDING.includes(t.tileId) ? GROUND_LANDING.map((id) => placedByTileId(s, id)!) : [t]
    for (const g of group) if (!g.tokens.includes('fire')) g.tokens.push('fire')
  } else {
    t.flipped = 'burning'
    t.tokens = t.tokens.filter((x) => x !== 'obstacle')
  }
}

/** Connected groups of burning rooms (by shared walls, per floor). */
function fires(s: HauntedState): PlacedTile[][] {
  const seen = new Set<string>()
  const groups: PlacedTile[][] = []
  for (const t of Object.values(s.tiles)) {
    if (!isBurning(t) || seen.has(t.uid)) continue
    const group: PlacedTile[] = []
    const stack = [t]
    seen.add(t.uid)
    while (stack.length) {
      const cur = stack.pop()!
      group.push(cur)
      for (const n of gridAdjacent(s, cur)) {
        if (isBurning(n) && !seen.has(n.uid)) {
          seen.add(n.uid)
          stack.push(n)
        }
      }
    }
    groups.push(group)
  }
  return groups
}

function spreadOptions(s: HauntedState, group: PlacedTile[]): string[] {
  const out = new Set<string>()
  for (const t of group) for (const n of gridAdjacent(s, t)) if (!isBurning(n)) out.add(n.uid)
  return [...out]
}

/** Ask the hero side to choose where each fire spreads, then spread them together. */
function askSpread(s: HauntedState, index: number) {
  const d = data(s)
  const groups = d.fires ?? []
  const chooser = nextHero(s)
  if (index >= groups.length || !chooser) {
    for (const uid of d.pending ?? []) setFire(s, s.tiles[uid]!)
    if ((d.pending ?? []).length) log(s, 'The fire spreads.')
    d.pending = []
    d.fires = []
    return
  }
  const options = groups[index]!.filter((uid) => !(d.pending ?? []).includes(uid))
  chooseTile(s, chooser, 'spread', `Choose where fire ${index + 1} spreads`, options, { index }, (uid) => {
    d.pending = [...(d.pending ?? []), uid]
    askSpread(s, index + 1)
  })
}

function wholeHouseBurning(s: HauntedState) {
  return Object.values(s.tiles).every(isBurning)
}

export const haunt44: HauntDef = {
  number: 44,
  title: 'The Mannequin Show',
  traitorRule: 'leftOfRevealer',
  monsterTurn: 'after',
  hero: {
    intro:
      'A mask on the side table wears your missing friend\'s face. Then one of your companions turns, and their skin has the sheen of plastic. Figures in the hallways move whenever you blink.',
    goal: 'Burn the whole house down. You win at the end of a hero\'s turn if every room is burning.',
    rules: [
      'Burning rooms are face down: doors on every side, no symbols or effects. A burning landing gets a fire token instead; the three ground-floor starting rooms count as one landing.',
      'Entering a burning room deals you 1 General damage.',
      'Set a fire (once per turn): make a Sanity roll. 4+: your room starts burning.',
      'After the monsters\' turn, each separate fire spreads to one room next to it (walls don\'t matter). Your side picks where. If none can spread, a landing catches fire.',
    ],
  },
  shared: [
    'Burning rooms are face down: doors on every side, no symbols and no room effects.',
    'A burning landing gets a fire token instead. The three ground-floor starting rooms count as one landing.',
    'Heroes take 1 General damage when they enter a burning room. The traitor and the Mannequins don\'t.',
    'Mannequin: Might 7, Speed 6. One that starts its turn in a hero\'s line of sight only rolls 2 dice to move.',
  ],
  traitor: {
    intro:
      'Such lovely guests, and such lovely skin. Your workshop needs material, and tonight it walked right in through the front door.',
    goal: 'Win when every hero is dead.',
    rules: [
      'Your Mannequins (Might 7, Speed 6) take a turn after yours. A Mannequin that starts its turn in a hero\'s line of sight only rolls 2 dice to move.',
      'You are made of plastic: damage from attacks against you is reduced by 1.',
      'Neither you nor your Mannequins are hurt by burning rooms.',
    ],
  },
  setup(s) {
    const t = traitor(s)
    heal(t, TRAITS)
    s.haunt!.data = {} satisfies Data
    const revealer = s.explorers[s.haunt!.revealer]!
    setFire(s, s.tiles[revealer.tile]!)
    if (s.seats.length === 3) {
      const other = heroes(s).find((h) => h.pid !== revealer.pid)
      const tile = other ? s.tiles[other.tile]! : undefined
      if (tile && !isLanding(tile)) setFire(s, tile)
    }
    const landings = ['groundStairs', 'upperLanding', 'basementLanding'].map((id) => placedByTileId(s, id)!)
    const n = byCount(s, [1, 2, 3, 4])
    for (let i = 0; i < n; i++) {
      addMonster(s, { kind: 'mannequin', name: `Mannequin ${i + 1}`, tile: landings[i % landings.length]!.uid, might: 7, speed: 6, sanity: 4, knowledge: 2, canStun: true })
    }
  },
  specials: [
    {
      id: 'setFire',
      label: 'Set a fire',
      side: 'hero',
      rules: 'Make a Sanity roll. 4+: your room starts burning.',
      check(s, pid) {
        return isBurning(s.tiles[s.explorers[pid]!.tile]!) ? 'This room is already burning.' : null
      },
      run(s, pid) {
        traitRoll(s, pid, 'sanity', 'Set a fire', { kind: 'special', id: 'setFire' })
        return null
      },
      resolve(s, pid, total) {
        if (total >= 4) {
          setFire(s, s.tiles[s.explorers[pid]!.tile]!)
          log(s, `${nameOf(s, pid)} sets the room alight.`)
        } else log(s, `${nameOf(s, pid)} can't bring themselves to do it.`)
      },
    },
  ],
  onEnter(s, pid, tile) {
    const ex = s.explorers[pid]!
    if (ex.side === 'hero' && isBurning(tile)) damage(s, pid, 'general', 1, 'The flames lick at you.')
  },
  onMonsterTurnEnd(s) {
    const groups = fires(s)
      .map((g) => spreadOptions(s, g))
      .filter((o) => o.length)
    if (!groups.length) {
      const landing = ['upperLanding', 'basementLanding', 'entrance']
        .map((id) => placedByTileId(s, id)!)
        .find((t) => !isBurning(t))
      if (landing) {
        setFire(s, landing)
        log(s, `Fire breaks out on the ${landing.region === 'ground' ? 'ground floor' : landing.region} landing.`)
      }
      return
    }
    data(s).fires = groups
    data(s).pending = []
    askSpread(s, 0)
  },
  onChooseTile(s, p, uid) {
    if (p.purpose !== 'spread') return
    const d = data(s)
    d.pending = [...(d.pending ?? []), uid]
    askSpread(s, Number(p.data?.index) + 1)
  },
  onTurnEnd(s, pid) {
    if (s.explorers[pid]!.side === 'hero' && wholeHouseBurning(s)) data(s).burned = true
  },
  checkWin(s) {
    if (data(s).burned && livingHeroes(s).length)
      return { winner: 'heroes', text: 'You burst out through the smoke as the roof caves in. At an upstairs window, a plastic face slowly melts.' }
    if (allHeroesDead(s)) return { winner: 'traitor', text: 'The last piece of material is cut and pinned. The show can go on.' }
    return null
  },
  blockLeave(s, pid) {
    return alive(s.explorers[pid]) ? null : 'You are out of the game.'
  },
}
