/* ===================================================================
   Betrayal at House on the Hill – Core Type Definitions
   =================================================================== */

// ── Traits ──────────────────────────────────────────────────────────

export type TraitName = 'speed' | 'might' | 'sanity' | 'knowledge'

/** A single trait track: eight values (indices 0-7) with a starting index. */
export interface TraitScale {
  values: [number, number, number, number, number, number, number, number]
  startIndex: number
}

export type TraitScales = Record<TraitName, TraitScale>

// ── Characters ──────────────────────────────────────────────────────

export interface CharacterDef {
  id: string
  name: string
  age: number
  color: number          // hex colour for token / card trim
  colorName: string      // human-readable colour
  traits: TraitScales
  description: string
}

// ── Room Tiles ──────────────────────────────────────────────────────

export type Floor = 'ground' | 'upper' | 'basement'

export type Direction = 'north' | 'south' | 'east' | 'west'

export type CardType = 'event' | 'item' | 'omen'

export interface RoomDef {
  id: string
  name: string
  floors: Floor[]
  doors: Direction[]         // which walls have doors
  cardDraw?: CardType        // card to draw when entering (if any)
  effect?: string            // flavour/rules text
  isStarting?: boolean       // pre-placed at game start
  barrier?: boolean          // blocks movement until resolved
  dumbwaiter?: boolean       // connects upper ↔ basement
  specialExit?: {            // e.g. Mystic Elevator, Coal Chute
    toFloor: Floor
  }
}

/** A placed tile on the board grid. */
export interface PlacedRoom {
  roomId: string
  floor: Floor
  row: number
  col: number
  /** Rotation in 90° increments (0–3). Doors rotate accordingly. */
  rotation: number
}

// ── Cards ───────────────────────────────────────────────────────────

export interface CardDef {
  id: string
  name: string
  type: CardType
  flavour: string
  effect: string
}

// ── Dice ────────────────────────────────────────────────────────────

/** Betrayal dice have faces: 0, 1, 2 (blank, 1 pip, 2 pips). */
export type DieFace = 0 | 1 | 2

// ── Player / Game State ─────────────────────────────────────────────

export interface PlayerState {
  peerId: string
  playerName: string
  characterId: string | null
  traitIndices: Record<TraitName, number>
  currentFloor: Floor
  currentRow: number
  currentCol: number
  items: string[]       // card IDs
  omens: string[]       // card IDs
  alive: boolean
  movesRemaining: number
}

export type GamePhase =
  | 'character_select'
  | 'exploration'
  | 'haunt_roll'
  | 'haunt'
  | 'ended'

export interface BetrayalGameState {
  phase: GamePhase
  players: Record<string, PlayerState>
  board: PlacedRoom[]
  eventDeck: string[]     // card IDs remaining
  itemDeck: string[]
  omenDeck: string[]
  discardPile: string[]
  currentTurnPeerId: string | null
  turnOrder: string[]
  turnIndex: number
  omenCount: number
  hauntRevealed: boolean
  hauntTraitorPeerId: string | null
  lastDiceRoll: DieFace[] | null
  drawnCard: string | null        // currently displayed card
  pendingRoom: RoomDef | null     // room waiting to be placed
  viewingFloor: Floor
  log: string[]
}
