/**
 * The room engine: pure functions that turn (room state, event) into a new
 * room state. Only the host runs these. No networking, no React, no timers,
 * which makes join / leave / rejoin behaviour easy to unit test.
 */
import type {
  GameModule,
  Player,
  PlayerId,
  RoomAction,
  RoomSnapshot,
  RoomState,
  RuleContext,
  RuleResult,
} from './types'

export const MAX_ROOM_PLAYERS = 16

const BOT_NAMES = ['Robo Rita', 'Clank', 'Beep Boop', 'Sprocket', 'Widget', 'Gizmo']
export const MAX_NAME_LENGTH = 20

export type GameLookup = (gameId: string) => GameModule | undefined

export function cleanName(raw: string): string {
  const name = raw.replace(/\s+/g, ' ').trim().slice(0, MAX_NAME_LENGTH)
  return name || 'Player'
}

function bump(room: RoomState, changes: Partial<RoomState>): RoomState {
  return { ...room, ...changes, version: room.version + 1 }
}

/** Make a name unique among the other players by adding " 2", " 3"... */
function uniqueName(players: Player[], name: string, selfId: PlayerId): string {
  const taken = new Set(
    players.filter((p) => p.id !== selfId).map((p) => p.name.toLowerCase()),
  )
  if (!taken.has(name.toLowerCase())) return name
  for (let n = 2; ; n++) {
    const candidate = `${name.slice(0, MAX_NAME_LENGTH - 3)} ${n}`
    if (!taken.has(candidate.toLowerCase())) return candidate
  }
}

export function createRoom(
  code: string,
  host: { id: PlayerId; name: string },
  now: number,
): RoomState {
  return {
    code,
    hostId: host.id,
    players: [{ id: host.id, name: cleanName(host.name), connected: true, joinedAt: now }],
    selectedGameId: null,
    game: null,
    version: 1,
    createdAt: now,
  }
}

export type JoinResult =
  | { room: RoomState; playerId: PlayerId; rejoined: boolean }
  | { error: string }

/**
 * A player says hello. Three cases:
 *  1. We know their id → they are reconnecting; give them their seat back.
 *  2. Their name matches a *disconnected* player → treat it as the same
 *     person on a new device/tab and hand that seat over.
 *  3. Otherwise they are new.
 */
export function joinRoom(
  room: RoomState,
  hello: { id: PlayerId; name: string },
  now: number,
): JoinResult {
  const name = cleanName(hello.name)

  const existing = room.players.find((p) => p.id === hello.id)
  if (existing) {
    const players = room.players.map((p) =>
      p.id === hello.id
        ? { ...p, connected: true, name: uniqueName(room.players, name, p.id) }
        : p,
    )
    return { room: bump(room, { players }), playerId: hello.id, rejoined: true }
  }

  const orphan = room.players.find(
    (p) => !p.connected && p.id !== room.hostId && p.name.toLowerCase() === name.toLowerCase(),
  )
  if (orphan) {
    const players = room.players.map((p) =>
      p.id === orphan.id ? { ...p, connected: true } : p,
    )
    return { room: bump(room, { players }), playerId: orphan.id, rejoined: true }
  }

  if (room.players.length >= MAX_ROOM_PLAYERS) {
    return { error: 'This room is full.' }
  }

  const player: Player = {
    id: hello.id,
    name: uniqueName(room.players, name, hello.id),
    connected: true,
    joinedAt: now,
  }
  return {
    room: bump(room, { players: [...room.players, player] }),
    playerId: hello.id,
    rejoined: false,
  }
}

export function setConnected(room: RoomState, playerId: PlayerId, connected: boolean): RoomState {
  const player = room.players.find((p) => p.id === playerId)
  if (!player || player.connected === connected) return room
  return bump(room, {
    // Dropping out of the room also drops you out of the call.
    players: room.players.map((p) => (p.id === playerId ? { ...p, connected, call: connected ? p.call : undefined } : p)),
  })
}

/** A player leaves for good (Leave button or kicked). Their seat is freed. */
export function removePlayer(
  room: RoomState,
  playerId: PlayerId,
  ctx: RuleContext,
  games: GameLookup,
): RoomState {
  if (playerId === room.hostId) return room
  if (!room.players.some((p) => p.id === playerId)) return room

  let game = room.game
  if (game && game.seats.includes(playerId)) {
    const mod = games(game.gameId)
    const state = mod?.playerLeft ? mod.playerLeft(game.state, playerId, ctx) : game.state
    game = { ...game, state, seats: game.seats.filter((id) => id !== playerId) }
  }
  return bump(room, { players: room.players.filter((p) => p.id !== playerId), game })
}

function seatedPlayers(room: RoomState, mod: GameModule): PlayerId[] {
  return [...room.players]
    .filter((p) => p.connected && (!p.bot || !!mod.bot))
    .sort((a, b) => a.joinedAt - b.joinedAt)
    .map((p) => p.id)
}

function startRound(
  room: RoomState,
  mod: GameModule,
  ctx: RuleContext,
  round: number,
): RuleResult<RoomState> {
  const seats = seatedPlayers(room, mod)
  if (seats.length < mod.minPlayers) {
    return { error: `${mod.name} needs at least ${mod.minPlayers} connected players.` }
  }
  if (seats.length > mod.maxPlayers) {
    return { error: `${mod.name} allows at most ${mod.maxPlayers} players.` }
  }
  const state = mod.setup(seats, ctx)
  return { state: bump(room, { game: { gameId: mod.id, seats, state, round } }) }
}

export function applyAction(
  room: RoomState,
  playerId: PlayerId,
  action: RoomAction,
  ctx: RuleContext,
  games: GameLookup,
): RuleResult<RoomState> {
  const isHost = playerId === room.hostId
  const hostOnly = () => ({ error: 'Only the host can do that.' })

  if (!room.players.some((p) => p.id === playerId)) {
    return { error: 'You are not in this room.' }
  }

  switch (action.type) {
    case 'selectGame': {
      if (!isHost) return hostOnly()
      if (room.game) return { error: 'End the current game first.' }
      if (action.gameId !== null && !games(action.gameId)) return { error: 'Unknown game.' }
      return { state: bump(room, { selectedGameId: action.gameId }) }
    }
    case 'startGame': {
      if (!isHost) return hostOnly()
      if (room.game) return { error: 'A game is already running.' }
      const mod = room.selectedGameId ? games(room.selectedGameId) : undefined
      if (!mod) return { error: 'Pick a game first.' }
      return startRound(room, mod, ctx, 1)
    }
    case 'playAgain': {
      if (!isHost) return hostOnly()
      if (!room.game) return { error: 'No game to restart.' }
      const mod = games(room.game.gameId)
      if (!mod) return { error: 'Unknown game.' }
      return startRound(room, mod, ctx, room.game.round + 1)
    }
    case 'endGame': {
      if (!isHost) return hostOnly()
      if (!room.game) return { state: room }
      return { state: bump(room, { game: null }) }
    }
    case 'kick': {
      if (!isHost) return hostOnly()
      if (action.playerId === room.hostId) return { error: "You can't kick yourself." }
      return { state: removePlayer(room, action.playerId, ctx, games) }
    }
    case 'addBot': {
      if (!isHost) return hostOnly()
      if (room.players.length >= MAX_ROOM_PLAYERS) return { error: 'This room is full.' }
      const names = BOT_NAMES.filter((n) => !room.players.some((p) => p.name === n))
      const name = names[0] ?? `Bot ${room.players.length + 1}`
      const id = `bot-${room.version}-${Math.floor(ctx.random() * 1e6)}`
      const level = (['easy', 'medium', 'hard'] as const).includes(action.level) ? action.level : 'medium'
      const bot: Player = { id, name, connected: true, joinedAt: ctx.now, bot: { level } }
      return { state: bump(room, { players: [...room.players, bot] }) }
    }
    case 'setBotLevel': {
      if (!isHost) return hostOnly()
      const target = room.players.find((p) => p.id === action.playerId)
      if (!target?.bot) return { error: 'That is not a computer player.' }
      if (!(['easy', 'medium', 'hard'] as const).includes(action.level)) return { error: 'Unknown level.' }
      return {
        state: bump(room, {
          players: room.players.map((p) => (p.id === target.id ? { ...p, bot: { level: action.level } } : p)),
        }),
      }
    }
    case 'call': {
      const peer = action.peer
      if (peer !== null && (typeof peer !== 'string' || !peer || peer.length > 100)) return { error: 'Invalid call address.' }
      return {
        state: bump(room, {
          players: room.players.map((p) =>
            p.id === playerId ? { ...p, call: peer ? { peer, video: action.video !== false } : undefined } : p,
          ),
        }),
      }
    }
    case 'rename': {
      const name = uniqueName(room.players, cleanName(action.name), playerId)
      return {
        state: bump(room, {
          players: room.players.map((p) => (p.id === playerId ? { ...p, name } : p)),
        }),
      }
    }
    case 'game': {
      const game = room.game
      if (!game) return { error: 'No game is running.' }
      if (!game.seats.includes(playerId)) return { error: "You're spectating this round." }
      const mod = games(game.gameId)
      if (!mod) return { error: 'Unknown game.' }
      const result = mod.action(game.state, playerId, action.action, ctx)
      if ('error' in result) return result
      return { state: bump(room, { game: { ...game, state: result.state } }) }
    }
    default:
      return { error: 'Unknown action.' }
  }
}

/** Advance game timers. Returns the same object when nothing changed. */
export function tickRoom(room: RoomState, ctx: RuleContext, games: GameLookup): RoomState {
  const game = room.game
  if (!game) return room
  const mod = games(game.gameId)
  if (!mod?.tick) return room
  const state = mod.tick(game.state, ctx)
  if (state === game.state) return room
  return bump(room, { game: { ...game, state } })
}

/**
 * Let one computer player take one action, if any wants to. Returns the new
 * room, or null if no bot has anything to do. The host calls this on a timer
 * so bots move at a human-ish pace.
 */
export function botStep(room: RoomState, ctx: RuleContext, games: GameLookup): RoomState | null {
  const game = room.game
  if (!game) return null
  const mod = games(game.gameId)
  if (!mod?.bot || mod.isOver?.(game.state)) return null
  for (const p of room.players) {
    if (!p.bot || !game.seats.includes(p.id)) continue
    const view = mod.view(game.state, p.id)
    for (let attempt = 0; attempt < 3; attempt++) {
      let action: unknown = null
      try {
        action = mod.bot(view, ctx, p.bot.level, attempt)
      } catch (err) {
        console.warn('[bot] crashed', err)
        continue
      }
      if (action === null || action === undefined) break
      const result = applyAction(room, p.id, { type: 'game', action }, ctx, games)
      if (!('error' in result)) return result.state
      console.warn('[bot] action rejected', action, result.error)
    }
  }
  return null
}

/** Build the personalised snapshot a single player is allowed to see. */
export function snapshotFor(
  room: RoomState,
  playerId: PlayerId,
  games: GameLookup,
  now: number,
): RoomSnapshot {
  let game: RoomSnapshot['game'] = null
  if (room.game) {
    const mod = games(room.game.gameId)
    const seated = room.game.seats.includes(playerId)
    game = {
      gameId: room.game.gameId,
      seats: room.game.seats,
      round: room.game.round,
      view: mod ? mod.view(room.game.state, seated ? playerId : null) : null,
    }
  }
  return {
    code: room.code,
    hostId: room.hostId,
    you: playerId,
    players: room.players,
    selectedGameId: room.selectedGameId,
    game,
    version: room.version,
    hostNow: now,
  }
}
