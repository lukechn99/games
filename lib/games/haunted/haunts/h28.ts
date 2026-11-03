/**
 * Haunt 28 (Ghost Hunters + Idol). Traitor: the haunt revealer.
 * The traitor is swallowed and plays a huge spectral fish; water floods the
 * house tile by tile. Heroes gather explosives and force them down its throat.
 */
import { gridAdjacent, isLanding, symbols } from '../engine/board'
import { alive, damage, hasCard, log, nameOf } from '../engine/core'
import { bury, traitRoll } from '../engine/play'
import type { HauntedState, PlacedTile } from '../types'
import type { HauntDef } from './types'
import { addMonster, allHeroesDead, byCount, chooseTile, nonLandingTiles, traitor } from './util'

type Data = { traps: Record<string, number>; pool: number; won?: boolean; drowned?: boolean }
const data = (s: HauntedState) => s.haunt!.data as Data

const flooded = (t: PlacedTile) => t.flipped === 'flooded'

function flood(s: HauntedState, uid: string) {
  const t = s.tiles[uid]
  if (!t || isLanding(t) || flooded(t)) return
  t.flipped = 'flooded'
  t.tokens = t.tokens.filter((x) => x !== 'obstacle')
  log(s, 'Black water surges into another room.')
}

/** Tiles the traitor may flood next. */
function floodOptions(s: HauntedState): string[] {
  const dry = nonLandingTiles(s).filter((t) => !flooded(t))
  let opts = dry.filter((t) => gridAdjacent(s, t).some(flooded))
  if (!opts.length) opts = dry.filter((t) => gridAdjacent(s, t).some(isLanding))
  return opts.map((t) => t.uid)
}

function askSetupFloods(s: HauntedState, region: string, remaining: number) {
  if (remaining <= 0) return
  const opts = nonLandingTiles(s).filter((t) => t.region === region && !flooded(t)).map((t) => t.uid)
  chooseTile(s, s.haunt!.traitor!, 'flood-setup', `Flood a room on this floor (${remaining} left)`, opts, { region, remaining }, (uid) => {
    flood(s, uid)
    askSetupFloods(s, region, remaining - 1)
  })
}

export const haunt28: HauntDef = {
  number: 28,
  title: 'Something in the Water',
  traitorRule: 'revealer',
  monsterTurn: 'instead',
  hero: {
    intro:
      'Salt fills the air and the floorboards are wet. Your friend vanished in a swirl of black water, and now something huge is circling beneath the house.',
    goal: 'Blow the creature apart: gather explosives, then force them down its throat.',
    rules: [
      'Flooded rooms are face down: they have doors on every side and no symbols. Landings never flood.',
      'At the start of each hero turn, the water spreads one room.',
      'Search for explosives (once per turn): in a room with an Item symbol, make a Speed roll. 4+: take an explosive.',
      'Feed it explosives (once per turn): in the creature\'s room, make a Might roll, +2 for each explosive you use and +2 if you carry Dynamite. 10+: you win. Otherwise take 2 Physical damage and your turn ends.',
    ],
  },
  shared: [
    'Flooded rooms are face down: doors on every side, no symbols and no room effects. Landings never flood.',
    'The Drowned Thing (Might 8, Speed 2) can\'t be stunned, and can swim between neighboring flooded rooms through walls.',
    'Explosives are tokens heroes can find and carry.',
  ],
  traitor: {
    intro:
      'The water poured from the idol and something vast rose out of it. You remember teeth. Now you are inside it, and you are very, very hungry.',
    goal: 'Win when every hero is dead, or when every room in the house (except landings) is flooded.',
    rules: [
      'You play the creature (Might 8, Speed 2) instead of your explorer. It can\'t be stunned.',
      'At the start of each hero\'s turn, flood a room next to a flooded room (or next to a landing if none).',
      'Rising tide (once per turn): move the creature to any flooded room.',
      'The creature can swim between any two neighboring flooded rooms, walls or not.',
    ],
  },
  setup(s) {
    const t = traitor(s)
    const tile = s.tiles[t.tile]!
    addMonster(s, { kind: 'shark', name: 'The Drowned Thing', tile: tile.uid, might: 8, speed: 2, sanity: 4, knowledge: 4, canStun: false })
    for (const c of [...t.items, ...t.omens]) bury(s, t, c)
    t.removed = true
    log(s, `${nameOf(s, t.pid)} is swallowed whole.`)
    s.haunt!.data = { traps: {}, pool: 5 } satisfies Data
    flood(s, tile.uid)
    askSetupFloods(s, tile.region, byCount(s, [0, 1, 2, 3]))
  },
  specials: [
    {
      id: 'search',
      label: 'Search for explosives',
      side: 'hero',
      rules: 'In a room with an Item symbol, make a Speed roll. 4+: take an explosive.',
      check(s, pid) {
        const tile = s.tiles[s.explorers[pid]!.tile]!
        if (!symbols(tile).includes('item')) return 'You need to be in a room with an Item symbol.'
        if (data(s).pool <= 0) return 'There are no explosives left to find.'
        return null
      },
      run(s, pid) {
        traitRoll(s, pid, 'speed', 'Search for explosives', { kind: 'special', id: 'search' })
        return null
      },
      resolve(s, pid, total) {
        const d = data(s)
        if (total >= 4 && d.pool > 0) {
          d.pool--
          d.traps[pid] = (d.traps[pid] ?? 0) + 1
          log(s, `${nameOf(s, pid)} finds an explosive.`)
        } else log(s, `${nameOf(s, pid)} finds nothing.`)
      },
    },
    {
      id: 'force',
      label: 'Feed it explosives',
      side: 'hero',
      rules: 'In the creature\'s room: Might roll, +2 per explosive used, +2 with Dynamite. 10+ wins.',
      check(s, pid) {
        const me = s.explorers[pid]!
        if (!s.monsters.some((m) => m.tile === me.tile)) return 'You need to be in the same room as the creature.'
        return null
      },
      countPrompt(s, pid) {
        const max = data(s).traps[pid] ?? 0
        return max ? { label: 'How many explosives?', max } : null
      },
      run(s, pid, { count }) {
        const d = data(s)
        const have = d.traps[pid] ?? 0
        const use = Math.max(0, Math.min(have, count ?? have))
        d.traps[pid] = have - use
        const bonus = use * 2 + (hasCard(s.explorers[pid]!, 'dynamite') ? 2 : 0)
        traitRoll(s, pid, 'might', `Feed it explosives (+${bonus})`, { kind: 'special', id: 'force' }, { bonus })
        return null
      },
      resolve(s, pid, total) {
        if (total >= 10) {
          data(s).won = true
          log(s, `${nameOf(s, pid)} rams the explosives home. The creature bursts!`)
          return
        }
        log(s, 'It spits the explosives back out.')
        damage(s, pid, 'physical', 2, 'The creature thrashes.')
        if (s.turn?.pid === pid) s.turn.ended = true
      },
    },
    {
      id: 'music',
      label: 'Rising tide',
      side: 'traitor',
      rules: 'Move the creature to any flooded room.',
      check(s) {
        return Object.values(s.tiles).some(flooded) ? null : 'Nothing is flooded.'
      },
      tilePrompt(s) {
        return { label: 'Pick a flooded room', options: Object.values(s.tiles).filter(flooded).map((t) => t.uid) }
      },
      run(s, _pid, { tile }) {
        const t = tile ? s.tiles[tile] : undefined
        if (!t || !flooded(t)) return 'Pick a flooded room.'
        const shark = s.monsters.find((m) => m.kind === 'shark')!
        shark.tile = t.uid
        log(s, 'A fin cuts through the water somewhere else in the house.')
        return null
      },
    },
  ],
  onHeroTurnStart(s) {
    const opts = floodOptions(s)
    chooseTile(s, s.haunt!.traitor!, 'flood', 'Flood a room', opts, {}, (uid) => flood(s, uid))
  },
  onChooseTile(s, p, uid) {
    if (p.purpose === 'flood') flood(s, uid)
    if (p.purpose === 'flood-setup') {
      flood(s, uid)
      askSetupFloods(s, String(p.data?.region), Number(p.data?.remaining) - 1)
    }
  },
  onMonsterTurnEnd(s) {
    if (nonLandingTiles(s).every(flooded)) data(s).drowned = true
  },
  checkWin(s) {
    const d = data(s)
    if (d.won) return { winner: 'heroes', text: 'Soaked and shaking, you stagger out into the night. Somewhere behind you, the water drains away.' }
    if (allHeroesDead(s)) return { winner: 'traitor', text: 'The house is quiet again, except for the slow lapping of water in the dark.' }
    if (d.drowned) return { winner: 'traitor', text: 'Every room is underwater. The house belongs to the deep now.' }
    return null
  },
  blockLeave(s, pid) {
    return alive(s.explorers[pid]) ? null : 'You are out of the game.'
  },
}
