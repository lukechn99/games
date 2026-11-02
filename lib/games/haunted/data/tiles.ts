import type { TileDef } from '../types'

/*
 * Room tiles. Regions, card symbols, effects and links are the 3rd-edition
 * base-game tiles. Doorway layouts aren't published anywhere I could reach,
 * so each room has a sensible layout of 1-4 doors (approximation).
 *
 * Door bitmask: N=1 E=2 S=4 W=8.
 */
const DEAD_END = 1 // N
const STRAIGHT = 5 // N S
const CORNER = 3 // N E
const TEE = 7 // N E S
const CROSS = 15

export const STARTING_TILES: TileDef[] = [
  {
    id: 'entrance',
    name: 'Entrance Hall',
    regions: ['ground'],
    doors: 1 | 2 | 8,
    symbols: [],
    landing: true,
    rules: 'Everyone starts here. The front door has slammed shut behind you.',
  },
  {
    id: 'hallway',
    name: 'Hallway',
    regions: ['ground'],
    doors: CROSS,
    symbols: [],
    landing: true,
    leadsTo: [{ tile: 'secretStairs' }],
    rules: 'Leads to the Secret Staircase, once it has been found.',
  },
  {
    id: 'groundStairs',
    name: 'Ground Floor Staircase',
    regions: ['ground'],
    doors: 2 | 4 | 8,
    symbols: [],
    landing: true,
    leadsTo: [{ tile: 'upperLanding' }, { tile: 'basementLanding', monstersOnly: true }],
    rules: 'Leads to the Upper Landing. Monsters can also slip down to the Basement Landing.',
  },
  {
    id: 'upperLanding',
    name: 'Upper Landing',
    regions: ['upper'],
    doors: CROSS,
    symbols: [],
    landing: true,
    leadsTo: [{ tile: 'groundStairs' }],
    rules: 'Leads to the Ground Floor Staircase.',
  },
  {
    id: 'basementLanding',
    name: 'Basement Landing',
    regions: ['basement'],
    doors: CROSS,
    symbols: [],
    landing: true,
    leadsTo: [{ tile: 'groundStairs', monstersOnly: true }],
    rules: 'Only monsters can use the old stairs up to the Ground Floor Staircase.',
  },
]

export const ROOM_TILES: TileDef[] = [
  { id: 'armory', name: 'Armory', regions: ['ground', 'basement'], doors: CORNER, symbols: [], effect: { kind: 'armory' },
    rules: 'When you discover this room, turn over Item cards until you find a weapon. Keep it and bury the rest.' },
  { id: 'ballroom', name: 'Ballroom', regions: ['ground'], doors: CROSS, symbols: ['omen'] },
  { id: 'bloodyRoom', name: 'Bloody Room', regions: ['upper', 'ground'], doors: CROSS, symbols: ['item'] },
  { id: 'catacombs', name: 'Catacombs', regions: ['basement'], doors: STRAIGHT, symbols: ['omen'] },
  { id: 'chapel', name: 'Chapel', regions: ['ground'], doors: DEAD_END, symbols: ['omen'], effect: { kind: 'gainOnDiscover', trait: 'sanity', amount: 1 },
    rules: 'When you discover this room, gain 1 Sanity.' },
  { id: 'charredRoom', name: 'Charred Room', regions: ['upper', 'ground'], doors: CROSS, symbols: ['omen'] },
  { id: 'chasm', name: 'Chasm', regions: ['basement'], doors: STRAIGHT, symbols: ['event'] },
  { id: 'collapsedRoom', name: 'Collapsed Room', regions: ['upper', 'ground'], doors: CROSS, symbols: [], effect: { kind: 'collapsed' },
    rules: 'If you end your turn here, make a Speed roll. 5+: nothing happens. 0-4: you fall to the Basement Landing and take 1 die of Physical damage.' },
  { id: 'conservatory', name: 'Conservatory', regions: ['ground'], doors: DEAD_END, symbols: ['item'] },
  { id: 'crampedPassage', name: 'Cramped Passageway', regions: ['upper', 'ground', 'basement'], doors: STRAIGHT, symbols: ['event'] },
  { id: 'crawlspace', name: 'Crawlspace', regions: ['upper', 'basement'], doors: STRAIGHT, symbols: ['event'] },
  { id: 'diningRoom', name: 'Dining Room', regions: ['ground'], doors: CORNER, symbols: ['event'] },
  { id: 'furnaceRoom', name: 'Furnace Room', regions: ['basement'], doors: TEE, symbols: ['event'], effect: { kind: 'furnace' },
    rules: 'If you end your turn here, take 1 Physical damage.' },
  { id: 'gallery', name: 'Gallery', regions: ['upper'], doors: STRAIGHT, symbols: ['event'], leadsTo: [{ tile: 'ballroom', oneWay: true }],
    rules: 'Leads down to the Ballroom.' },
  { id: 'gameRoom', name: 'Game Room', regions: ['upper', 'basement'], doors: TEE, symbols: ['item'] },
  { id: 'graveyard', name: 'Graveyard', regions: ['ground'], doors: DEAD_END, symbols: ['omen'], leadsTo: [{ tile: 'cavern' }],
    rules: 'Leads to the Underground Cavern.' },
  { id: 'guestQuarters', name: 'Guest Quarters', regions: ['upper', 'ground'], doors: CORNER, symbols: ['event'] },
  { id: 'gymnasium', name: 'Gymnasium', regions: ['ground', 'basement'], doors: CORNER, symbols: [], effect: { kind: 'gainOnDiscover', trait: 'speed', amount: 1 },
    rules: 'When you discover this room, gain 1 Speed.' },
  { id: 'junkRoom', name: 'Junk Room', regions: ['upper', 'ground'], doors: CROSS, symbols: ['item'], effect: { kind: 'obstacle' },
    rules: 'When this room is discovered, it fills with an obstacle: leaving it costs 2 movement.' },
  { id: 'kitchen', name: 'Kitchen', regions: ['ground'], doors: CORNER, symbols: ['event'] },
  { id: 'laboratory', name: 'Laboratory', regions: ['ground'], doors: STRAIGHT, symbols: ['event'] },
  { id: 'larder', name: 'Larder', regions: ['ground'], doors: STRAIGHT, symbols: [], effect: { kind: 'gainOnDiscover', trait: 'might', amount: 1 },
    rules: 'When you discover this room, gain 1 Might.' },
  { id: 'laundryChute', name: 'Laundry Chute', regions: ['ground'], doors: DEAD_END, symbols: [], effect: { kind: 'chute' },
    leadsTo: [{ tile: 'basementLanding', oneWay: true }],
    rules: 'Leads down to the Basement Landing. If you end your turn here, you slide down to the Basement Landing.' },
  { id: 'library', name: 'Library', regions: ['upper', 'ground'], doors: CORNER, symbols: ['omen'], effect: { kind: 'gainOnDiscover', trait: 'knowledge', amount: 1 },
    rules: 'When you discover this room, gain 1 Knowledge.' },
  { id: 'elevator', name: 'Wandering Lift', regions: ['upper', 'ground', 'basement'], doors: DEAD_END, symbols: [], effect: { kind: 'elevator' },
    rules: 'Once per turn when you enter, you may roll 2 dice and move the lift (with you in it) to an open doorway. 4+: any floor. 3: upper. 2: ground. 0-1: basement.' },
  { id: 'nursery', name: 'Nursery', regions: ['upper', 'basement'], doors: CORNER, symbols: ['omen'] },
  { id: 'observatory', name: 'Observatory', regions: ['upper'], doors: CORNER, symbols: ['omen'] },
  { id: 'operatingTheatre', name: 'Operating Theatre', regions: ['upper', 'basement'], doors: CORNER, symbols: ['item'] },
  { id: 'organRoom', name: 'Organ Room', regions: ['upper', 'basement'], doors: CORNER, symbols: ['event'] },
  { id: 'panicRoom', name: 'Panic Room', regions: ['basement'], doors: DEAD_END, symbols: ['omen'], effect: { kind: 'panicRoom' },
    rules: 'When you discover this room, if the Secret Staircase is not yet in the house, it is placed in the basement.' },
  { id: 'primaryBedroom', name: 'Primary Bedroom', regions: ['upper', 'ground'], doors: CORNER, symbols: ['omen'] },
  { id: 'ritualRoom', name: 'Ritual Room', regions: ['basement'], doors: CORNER, symbols: ['omen'] },
  { id: 'salon', name: 'Salon', regions: ['upper', 'ground'], doors: TEE, symbols: ['event'] },
  { id: 'secretStairs', name: 'Secret Staircase', regions: ['basement'], doors: DEAD_END, symbols: [], leadsTo: [{ tile: 'hallway' }],
    rules: 'Leads up to the Hallway.' },
  { id: 'soundproofedRoom', name: 'Soundproofed Room', regions: ['upper', 'basement'], doors: DEAD_END, symbols: ['omen'] },
  { id: 'specimenRoom', name: 'Specimen Room', regions: ['upper', 'ground'], doors: CORNER, symbols: ['omen'] },
  { id: 'statuaryCorridor', name: 'Statuary Corridor', regions: ['upper'], doors: STRAIGHT, symbols: ['event'] },
  { id: 'tower', name: 'Tower', regions: ['upper'], doors: STRAIGHT, symbols: ['event'] },
  { id: 'cavern', name: 'Underground Cavern', regions: ['basement'], doors: CROSS, symbols: ['event'], leadsTo: [{ tile: 'graveyard' }],
    rules: 'Leads up to the Graveyard.' },
  { id: 'undergroundLake', name: 'Underground Lake', regions: ['basement'], doors: CORNER, symbols: ['event'] },
  { id: 'vault', name: 'Vault', regions: ['basement'], doors: DEAD_END, symbols: ['item', 'item'] },
  { id: 'winterBedroom', name: 'Winter Bedroom', regions: ['upper', 'ground'], doors: CORNER, symbols: ['omen'] },
]

export const ALL_TILES = [...STARTING_TILES, ...ROOM_TILES]
export const TILE_BY_ID = new Map(ALL_TILES.map((t) => [t.id, t]))
