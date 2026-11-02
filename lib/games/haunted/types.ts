/**
 * Haunted House: shared types.
 *
 * Gameplay follows Betrayal at House on the Hill (3rd edition) rules.
 * Names and all text are original; see data/ for sources and notes.
 */
import type { PlayerId } from '@/lib/engine/types'

export type Trait = 'speed' | 'might' | 'sanity' | 'knowledge'
export const TRAITS: Trait[] = ['speed', 'might', 'sanity', 'knowledge']
export const PHYSICAL: Trait[] = ['speed', 'might']
export const MENTAL: Trait[] = ['sanity', 'knowledge']

export type Region = 'basement' | 'ground' | 'upper'
export const REGIONS: Region[] = ['upper', 'ground', 'basement']

/** Door bitmask: N=1, E=2, S=4, W=8. */
export type Dir = 0 | 1 | 2 | 3 // N E S W
export const DIRS: Dir[] = [0, 1, 2, 3]
export const DX = [0, 1, 0, -1]
export const DY = [-1, 0, 1, 0]
export const opposite = (d: Dir) => ((d + 2) % 4) as Dir
export const dirName = (d: Dir) => ['north', 'east', 'south', 'west'][d]!

export type CardKind = 'event' | 'item' | 'omen'

/* ------------------------------------------------------------------ */
/*  Static data                                                        */
/* ------------------------------------------------------------------ */

export interface TraitTrack {
  /** Eight values, lowest (critical) first. Below index 0 is death. */
  values: number[]
  /** Index of the starting (green) value. */
  start: number
}

export interface ExplorerDef {
  id: string
  name: string
  color: string
  colorName: string
  age: number
  blurb: string
  traits: Record<Trait, TraitTrack>
}

export type TileEffect =
  | { kind: 'gainOnDiscover'; trait: Trait; amount: number }
  | { kind: 'armory' }
  | { kind: 'obstacle' }
  | { kind: 'collapsed' }
  | { kind: 'furnace' }
  | { kind: 'chute' }
  | { kind: 'elevator' }
  | { kind: 'panicRoom' }

export interface TileDef {
  id: string
  name: string
  regions: Region[]
  /** Door bitmask in the tile's unrotated orientation. */
  doors: number
  /** Card symbols on the tile (Vault has two items). */
  symbols: CardKind[]
  effect?: TileEffect
  /** Static links to other tiles, e.g. stairs ("Leads to"). One-way if `oneWay`. */
  leadsTo?: { tile: string; oneWay?: boolean; monstersOnly?: boolean }[]
  landing?: boolean
  rules?: string
}

export type ItemEffect =
  | { kind: 'feather' }
  | { kind: 'brooch' }
  | { kind: 'weapon'; trait: 'might' | 'speed'; extraDice: number; addResult?: number; range?: 'adjacent' | 'sight'; noDamageIfLose?: boolean; speedCost?: number }
  | { kind: 'doll' }
  | { kind: 'dynamite' }
  | { kind: 'firstAid' }
  | { kind: 'flashlight' }
  | { kind: 'headphones' }
  | { kind: 'jacket' }
  | { kind: 'coin' }
  | { kind: 'camera' }
  | { kind: 'map' }
  | { kind: 'mirror' }
  | { kind: 'stopwatch' }
  | { kind: 'necklace' }
  | { kind: 'rabbitFoot' }
  | { kind: 'skeletonKey' }
  | { kind: 'amulet' }
  | { kind: 'medicine' }
  | { kind: 'armor' }
  | { kind: 'idol' }
  | { kind: 'none' }

export interface CardDef {
  id: string
  kind: CardKind
  name: string
  flavor: string
  rules: string
  /** Trait changes applied when the card is drawn. */
  onDraw?: Partial<Record<Trait, number>>
  effect?: ItemEffect
  /** The omen this card counts as for haunt triggers. */
  omen?: OmenId
  /** True where the card's exact 3rd-edition text couldn't be sourced. */
  approx?: boolean
}

export type OmenId = 'armor' | 'book' | 'dagger' | 'dog' | 'holySymbol' | 'idol' | 'mask' | 'ring' | 'skull'

export type EventOutcome =
  | { kind: 'nothing' }
  | { kind: 'gain'; trait: Trait | 'physical' | 'mental' | 'any'; amount: number }
  | { kind: 'lose'; trait: Trait; amount: number }
  | { kind: 'damage'; type: DamageType; amount: number; dice?: boolean }
  | { kind: 'drawItem' }
  | { kind: 'teleport'; to: 'basementLanding' | 'entrance' | 'upperLanding' }
  | { kind: 'heal'; traits: Trait[] }
  | { kind: 'multi'; outcomes: EventOutcome[] }

export interface EventDef {
  id: string
  name: string
  flavor: string
  /** Trait to roll; null = no roll, `outcomes[0]` applies. */
  roll: Trait | null
  /** Highest threshold first: first row with total >= min applies. */
  outcomes: { min: number; text: string; outcome: EventOutcome }[]
  approx?: boolean
}

export type DamageType = 'physical' | 'mental' | 'general'

/* ------------------------------------------------------------------ */
/*  Game state                                                         */
/* ------------------------------------------------------------------ */

export interface Pos {
  region: Region
  x: number
  y: number
}

export interface PlacedTile {
  uid: string
  tileId: string
  region: Region
  x: number
  y: number
  /** Doors after rotation (bitmask). */
  doors: number
  rot: 0 | 1 | 2 | 3
  /** Haunt-specific overlay: flooded / burning (face down, 4 doors, no symbols). */
  flipped?: 'flooded' | 'burning'
  tokens: string[]
}

export interface ExplorerState {
  pid: PlayerId
  explorerId: string
  /** Current index on each track. -1 = dead. */
  idx: Record<Trait, number>
  tile: string // PlacedTile uid
  items: string[]
  omens: string[]
  dead: boolean
  /** Removed from play (e.g. swallowed by the shark); not a corpse. */
  removed?: boolean
  side: 'hero' | 'traitor' | 'none'
  /** Haunt 30: omens visible to the traitor. */
  revealed: string[]
  /** Cards gained this turn (can't be used for special actions yet). */
  newThisTurn: string[]
  extraTurns: number
}

export interface MonsterState {
  id: string
  kind: string
  name: string
  tile: string
  stunned: boolean
  might: number
  speed: number
  sanity: number
  knowledge: number
  canStun: boolean
}

export interface RollRecord {
  id: number
  by: string
  label: string
  dice: number[]
  bonus: number
  total: number
}

export interface TurnState {
  pid: PlayerId
  /** 'player' or a monster kind taking its turn. */
  actor: 'player' | 'monsters'
  movesLeft: number
  attacked: boolean
  traded: boolean
  looted: boolean
  used: string[]
  elevatorUsed: boolean
  /** Entered the lift tile this turn (it can only be ridden on entry). */
  enteredElevator: boolean
  ended: boolean
  /** End-of-turn tile effects have been applied. */
  endFx: boolean
  /** Monster turns: movement left per monster, and who has attacked. */
  monsterMoves?: Record<string, number>
  monsterAttacked?: string[]
}

export type Prompt =
  | { kind: 'place'; pid: PlayerId; tileId: string; at: Pos; from: string; options: number[]; viaDir: Dir }
  | { kind: 'damage'; pid: PlayerId; type: DamageType; amount: number; reason: string; then?: Continuation }
  | { kind: 'event'; pid: PlayerId; cardId: string; stage: 'read' | 'rolled'; roll?: number; then?: Continuation }
  | { kind: 'card'; pid: PlayerId; cardId: string; then?: Continuation }
  | { kind: 'reroll'; pid: PlayerId; roll: PendingRoll }
  | { kind: 'gainChoice'; pid: PlayerId; traits: Trait[]; amount: number; reason: string; then?: Continuation }
  | { kind: 'trade'; from: PlayerId; to: PlayerId; give: string[]; take: string[] }
  | { kind: 'chooseTile'; pid: PlayerId; purpose: string; label: string; options: string[]; data?: Record<string, unknown> }
  | { kind: 'haunt'; stage: 'reveal' }
  | { kind: 'elevator'; pid: PlayerId; roll: number }
  | { kind: 'attackResult'; pid: PlayerId; target: string; margin: number; canSteal: boolean }

/** A dice roll waiting on possible rerolls before its effect applies. */
export interface PendingRoll {
  label: string
  dice: number[]
  bonus: number
  trait: Trait | null
  rerolled: string[]
  then: Continuation
}

/** What to do after an interrupt (damage allocation, card read, roll). */
export type Continuation =
  | { kind: 'endTurn' }
  | { kind: 'eventResult'; cardId: string }
  | { kind: 'special'; id: string; data?: Record<string, unknown> }
  | { kind: 'none' }
  | { kind: 'collapsed' }
  | { kind: 'dynamite'; targets: string[]; index: number }
  | { kind: 'attack'; target: string; weapon: string | null; defenderDice?: number[]; mode?: 'might' | 'speed' }

export interface HauntInfo {
  number: number
  title: string
  traitor: PlayerId | null
  revealer: PlayerId
  /** True if the chart pointed to a haunt that isn't built, and a stand-in was used. */
  substitute: boolean
  chartNumber: number
  data: Record<string, unknown>
}

export interface LogEntry {
  id: number
  text: string
  /** Only these players see it (hidden info). */
  to?: PlayerId[]
}

export interface HauntedState {
  phase: 'setup' | 'explore' | 'haunt' | 'over'
  seats: PlayerId[]
  scenario: string | null
  picks: Record<PlayerId, string | null>
  explorers: Record<PlayerId, ExplorerState>
  order: PlayerId[]
  turn: TurnState | null
  tiles: Record<string, PlacedTile>
  stack: string[]
  decks: { event: string[]; item: string[]; omen: string[] }
  omensDrawn: number
  prompt: Prompt | null
  queue: Prompt[]
  rolls: RollRecord[]
  log: LogEntry[]
  haunt: HauntInfo | null
  monsters: MonsterState[]
  winner: 'heroes' | 'traitor' | null
  winText: string | null
  seq: number
  /** Cards in nobody's hand: buried / removed from play. */
  buried: string[]
  /** Who plays next, when a rule overrides normal turn order. */
  nextPid: PlayerId | null
}

export type HauntedAction =
  | { type: 'pickExplorer'; explorerId: string }
  | { type: 'pickScenario'; scenarioId: string }
  | { type: 'begin' }
  | { type: 'move'; dir: Dir }
  | { type: 'moveTo'; tile: string }
  | { type: 'place'; rot: number }
  | { type: 'allocate'; split: Partial<Record<Trait, number>> }
  | { type: 'gainPick'; trait: Trait }
  | { type: 'continue' }
  | { type: 'rollEvent' }
  | { type: 'reroll'; item: string; die?: number; value?: number }
  | { type: 'acceptRoll' }
  | { type: 'endTurn' }
  | { type: 'useItem'; card: string; target?: string; tile?: string }
  | { type: 'offerTrade'; to: PlayerId; give: string[]; take: string[] }
  | { type: 'answerTrade'; accept: boolean }
  | { type: 'loot'; card: string }
  | { type: 'drop'; card: string }
  | { type: 'pickUp'; card: string }
  | { type: 'attack'; target: string; weapon?: string | null }
  | { type: 'steal'; card: string | null }
  | { type: 'chooseTile'; tile: string }
  | { type: 'special'; id: string; tile?: string; count?: number }
  | { type: 'elevatorRegion'; region: Region }
  | { type: 'monsterMove'; monster: string; tile: string }
  | { type: 'monsterAttack'; monster: string; target: string }
  | { type: 'endMonsterTurn' }
