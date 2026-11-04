/**
 * Core types shared by the room engine, the network layer and the games.
 *
 * Everything here is plain data so it can be sent over a data channel and
 * saved to localStorage as JSON.
 */

/** A stable player identity. Survives refreshes and reconnects. */
export type PlayerId = string

export interface Player {
  id: PlayerId
  name: string
  /** Whether the player currently has a live connection to the host. */
  connected: boolean
  /** When the player first joined (host clock, ms). Used for ordering. */
  joinedAt: number
  /** Set for computer players, which the host plays. */
  bot?: { level: BotLevel }
  /** Set while the player is in the video call: their media peer address. */
  call?: { peer: string; video: boolean }
}

export type BotLevel = 'easy' | 'medium' | 'hard'

/** Context the engine hands to game rules. Keeps rules pure and testable. */
export interface RuleContext {
  /** Host clock in ms. */
  now: number
  /** Returns a float in [0, 1). Injected so tests can be deterministic. */
  random: () => number
}

/** Result of applying an action: the new state or a human-readable error. */
export type RuleResult<S> = { state: S } | { error: string }

/**
 * A game is a set of pure functions. The host is the only one that runs
 * `setup`, `action`, `tick` and `playerLeft`. Every player (including the
 * host) renders whatever `view` returns for them.
 */
export interface GameModule<S = unknown, A = unknown, V = unknown> {
  id: string
  name: string
  description: string
  minPlayers: number
  maxPlayers: number
  /** Create the initial state for the given seated players. */
  setup(playerIds: PlayerId[], ctx: RuleContext): S
  /** Apply one player's action. Return an error to reject it. */
  action(state: S, playerId: PlayerId, action: A, ctx: RuleContext): RuleResult<S>
  /**
   * What a given player is allowed to see. `null` means a spectator who is
   * not seated in this game. Hidden information must be stripped here.
   */
  view(state: S, playerId: PlayerId | null): V
  /** Called about once a second by the host for timers. Return the same object if nothing changed. */
  tick?(state: S, ctx: RuleContext): S
  /** A seated player left the room for good (not just disconnected). */
  playerLeft?(state: S, playerId: PlayerId, ctx: RuleContext): S
  /** True once the game has finished (used for "play again"). */
  isOver?(state: S): boolean
  /**
   * Computer player: given exactly what this seat can see, return the next
   * action, or null to wait. Games without this can't seat bots. If the
   * action is rejected the host asks again with a higher `attempt`, and the
   * bot should fall back to something safe (like ending its turn).
   */
  bot?(view: V, ctx: RuleContext, level: BotLevel, attempt: number): A | null
  /** Pause before each computer-player action (ms). */
  botDelayMs?: number
}

export interface ActiveGame {
  gameId: string
  /** Players seated when the game started. Late joiners spectate. */
  seats: PlayerId[]
  state: unknown
  /** Incremented every time a new round of the same game starts. */
  round: number
}

/** The host's authoritative room state. Never sent to players as-is. */
export interface RoomState {
  code: string
  hostId: PlayerId
  players: Player[]
  selectedGameId: string | null
  game: ActiveGame | null
  /** Bumped on every change so clients can ignore stale snapshots. */
  version: number
  createdAt: number
}

/** What a single player receives from the host. */
export interface RoomSnapshot {
  code: string
  hostId: PlayerId
  you: PlayerId
  players: Player[]
  selectedGameId: string | null
  game: {
    gameId: string
    seats: PlayerId[]
    round: number
    /** Output of the game's `view` for this player. */
    view: unknown
  } | null
  version: number
  /** Host clock when the snapshot was made, so clients can correct for skew. */
  hostNow: number
}

/** Things any player can ask the room to do. Host-only ones are checked by the engine. */
export type RoomAction =
  | { type: 'selectGame'; gameId: string | null }
  | { type: 'startGame' }
  | { type: 'endGame' }
  | { type: 'playAgain' }
  | { type: 'kick'; playerId: PlayerId }
  | { type: 'addBot'; level: BotLevel }
  | { type: 'setBotLevel'; playerId: PlayerId; level: BotLevel }
  | { type: 'rename'; name: string }
  /** Join (peer set) or leave (peer null) the room's video call. */
  | { type: 'call'; peer: string | null; video?: boolean }
  | { type: 'game'; action: unknown }
