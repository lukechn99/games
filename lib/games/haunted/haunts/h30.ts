/**
 * Haunt 30 (The Missing Friend + Ring). Traitor: lowest Sanity other than
 * the haunt revealer. A possessed traitor wants the Ring; heroes keep their
 * omens hidden, find the altar, and lure the spirit there for a ceremony.
 */
import { placedByTileId, symbols } from '../engine/board'
import { alive, heal, log, nameOf } from '../engine/core'
import { reachable } from '../engine/haunt'
import { placeSecretStairs, traitRoll } from '../engine/play'
import type { HauntedState } from '../types'
import { TRAITS } from '../types'
import type { HauntDef } from './types'
import { addMonster, allHeroesDead, byCount, chooseTile, pickRandom, traitor } from './util'

export const RING = 'omenRing'

type Data = { won?: boolean; altarPlaced?: boolean }
const data = (s: HauntedState) => s.haunt!.data as Data

function altarTile(s: HauntedState) {
  return Object.values(s.tiles).find((t) => t.tokens.includes('altar'))
}

function placeAltar(s: HauntedState, uid: string) {
  const t = s.tiles[uid]
  if (!t || data(s).altarPlaced) return
  t.tokens.push('altar')
  data(s).altarPlaced = true
  log(s, 'An altar stands in the last room of the house. A perfect place for a wedding.')
}

export const haunt30: HauntDef = {
  number: 30,
  title: 'Something Borrowed',
  traitorRule: { lowest: 'sanity', excludeRevealer: true },
  monsterTurn: 'after',
  hero: {
    intro:
      'You found your missing friend clutching a torn veil. A spirit is wearing one of your companions now, wailing for a bride it lost long ago. It wants the ring you found. Use that.',
    goal: 'Find the altar, lure the spirit to it, and perform the ceremony.',
    rules: [
      'Keep your omens hidden: the traitor can\'t see them unless they\'re revealed.',
      'Only a few rooms are left in the house. The altar appears in the last one discovered.',
      'Compel the spirit (once per turn): if you carry the Ring, reveal it and make a Knowledge roll. Move the traitor up to that many rooms.',
      'Perform the ceremony (once per turn): in the altar room with the traitor, make a Sanity roll. 6+: you win.',
    ],
  },
  traitor: {
    intro:
      'This body will do. Now you need the ring, and then a body for her. Hand in hand, forever, as it should have been.',
    goal: 'Win when you hold the Ring.',
    rules: [
      'Your traits can\'t drop below their starting values.',
      'When you attack a hero, one of their hidden omens is turned face up.',
      'When a hero dies, all their omens are turned face up.',
      'Once you enter the altar room, you can\'t leave it.',
      'Your Wedding Guests (Might 5, Speed 4) take a turn after yours.',
      'Win a fight by 2 or more to steal a card instead of dealing damage, or loot it from a body.',
    ],
  },
  setup(s) {
    placeSecretStairs(s)
    const keep = byCount(s, [4, 6, 9, 12])
    if (s.stack.length > keep) s.stack = s.stack.slice(0, keep)
    const t = traitor(s)
    const revealer = s.explorers[s.haunt!.revealer]!
    revealer.omens.push(...t.omens)
    t.omens = []
    heal(t, TRAITS)
    t.tile = placedByTileId(s, 'entrance')!.uid
    s.haunt!.data = {} satisfies Data
    const omenTiles = Object.values(s.tiles).filter((x) => symbols(x).includes('omen'))
    const n = byCount(s, [1, 2, 3, 4])
    const stairs = placedByTileId(s, 'groundStairs')!
    for (let i = 0; i < n; i++) {
      const pick = pickRandom(omenTiles)
      if (pick) omenTiles.splice(omenTiles.indexOf(pick), 1)
      const spot = pick ?? stairs
      addMonster(s, { kind: 'guest', name: `Wedding Guest ${i + 1}`, tile: spot.uid, might: 5, speed: 4, sanity: 2, knowledge: 3, canStun: true })
    }
    if (s.stack.length === 0) {
      const last = Object.values(s.tiles).at(-1)!
      placeAltar(s, last.uid)
    }
  },
  specials: [
    {
      id: 'compel',
      label: 'Compel the spirit',
      side: 'hero',
      rules: 'Reveal the Ring and make a Knowledge roll. Move the traitor up to that many rooms.',
      check(s, pid) {
        if (!s.explorers[pid]!.omens.includes(RING)) return 'You need the Ring.'
        const t = traitor(s)
        if (!alive(t)) return 'The spirit has no body to move.'
        if (s.tiles[t.tile]!.tokens.includes('altar')) return 'The spirit is already bound to the altar.'
        return null
      },
      run(s, pid) {
        const ex = s.explorers[pid]!
        if (!ex.revealed.includes(RING)) ex.revealed.push(RING)
        log(s, `${nameOf(s, pid)} holds up the Ring.`)
        traitRoll(s, pid, 'knowledge', 'Compel the spirit', { kind: 'special', id: 'compel' })
        return null
      },
      resolve(s, pid, total) {
        const t = traitor(s)
        const options = reachable(s, s.tiles[t.tile]!, total)
        chooseTile(s, pid, 'compel', `Move the spirit up to ${total} rooms`, options, {}, (uid) => {
          t.tile = uid
          log(s, `The spirit is drawn toward the ring.`)
        })
      },
    },
    {
      id: 'ceremony',
      label: 'Perform the ceremony',
      side: 'hero',
      rules: 'In the altar room with the traitor, make a Sanity roll. 6+ wins.',
      check(s, pid) {
        const altar = altarTile(s)
        const me = s.explorers[pid]!
        if (!altar || me.tile !== altar.uid) return 'You need to be at the altar.'
        const t = traitor(s)
        if (!alive(t) || t.tile !== altar.uid) return 'The spirit must be at the altar too.'
        return null
      },
      run(s, pid) {
        traitRoll(s, pid, 'sanity', 'Perform the ceremony', { kind: 'special', id: 'ceremony' })
        return null
      },
      resolve(s, pid, total) {
        if (total >= 6) {
          data(s).won = true
          log(s, `${nameOf(s, pid)} completes the ceremony. The spirit lets go.`)
        } else log(s, 'The words come out wrong. The spirit laughs.')
      },
    },
  ],
  onDiscover(s, tile) {
    if (s.stack.length === 0) placeAltar(s, tile.uid)
  },
  onChooseTile(s, p, uid) {
    if (p.purpose === 'compel') {
      traitor(s).tile = uid
      log(s, 'The spirit is drawn toward the ring.')
    }
  },
  onTraitorAttack(s, target) {
    const ex = s.explorers[target]!
    const hidden = ex.omens.filter((c) => !ex.revealed.includes(c))
    const pick = pickRandom(hidden)
    if (pick) ex.revealed.push(pick)
  },
  blockLeave(s, pid) {
    const ex = s.explorers[pid]!
    if (ex.side === 'traitor' && s.tiles[ex.tile]!.tokens.includes('altar')) return 'You are bound to the altar.'
    return null
  },
  checkWin(s) {
    if (data(s).won) return { winner: 'heroes', text: 'The spirit slips free of your friend. You carry them out into the cold air and call for help.' }
    if (traitor(s).omens.includes(RING)) return { winner: 'traitor', text: 'The ring is yours again. Somewhere in the house, a bride begins to stir.' }
    if (allHeroesDead(s)) return { winner: 'traitor', text: 'No one is left to stop the wedding.' }
    return null
  },
}
