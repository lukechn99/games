'use client'

import {
  useEffect,
  useState,
  useCallback,
  useRef,
  useMemo,
} from 'react'
import { useConnections } from '@/lib/connections-provider'
import { useGame } from '@/lib/game-context'
import { CHARACTERS, CHARACTER_MAP } from './data/characters'
import { ROOM_STACK, ROOM_MAP } from './data/rooms'
import { EVENT_CARDS, ITEM_CARDS, OMEN_CARDS, CARD_MAP } from './data/cards'
import type {
  BetrayalGameState,
  PlayerState,
  TraitName,
  Floor,
  Direction,
  PlacedRoom,
  RoomDef,
  CardDef,
} from './types'
import PixiBoard from './PixiBoard'
import CharacterSheet from './CharacterSheet'
import DiceRoller, { rollDice } from './DiceRoller'
import GameInstructions, { TurnActions } from './GameInstructions'

/* ------------------------------------------------------------------ */
/*  Helpers                                                            */
/* ------------------------------------------------------------------ */

function shuffle<T>(arr: T[]): T[] {
  const a = [...arr]
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1))
    ;[a[i], a[j]] = [a[j]!, a[i]!]
  }
  return a
}

function createInitialBoard(): PlacedRoom[] {
  return [
    { roomId: 'entrance_hall',     floor: 'ground',   row: 0, col: 0, rotation: 0 },
    { roomId: 'foyer',             floor: 'ground',   row: 1, col: 0, rotation: 0 },
    { roomId: 'grand_staircase',   floor: 'ground',   row: -1, col: 0, rotation: 0 },
    { roomId: 'upper_landing',     floor: 'upper',    row: 0, col: 0, rotation: 0 },
    { roomId: 'basement_landing',  floor: 'basement', row: 0, col: 0, rotation: 0 },
  ]
}

function createPlayer(peerId: string, playerName: string): PlayerState {
  return {
    peerId,
    playerName,
    characterId: null,
    traitIndices: { speed: 0, might: 0, sanity: 0, knowledge: 0 },
    currentFloor: 'ground',
    currentRow: 0,
    currentCol: 0,
    items: [],
    omens: [],
    alive: true,
    movesRemaining: 0,
  }
}

function getAdjacentCell(row: number, col: number, dir: Direction): { row: number; col: number } {
  switch (dir) {
    case 'north': return { row: row - 1, col }
    case 'south': return { row: row + 1, col }
    case 'east':  return { row, col: col + 1 }
    case 'west':  return { row, col: col - 1 }
  }
}

function oppositeDir(dir: Direction): Direction {
  const map: Record<Direction, Direction> = {
    north: 'south', south: 'north', east: 'west', west: 'east',
  }
  return map[dir]
}

function rotateDoors(doors: Direction[], rotation: number): Direction[] {
  const order: Direction[] = ['north', 'east', 'south', 'west']
  return doors.map((d) => {
    const idx = order.indexOf(d)
    return order[(idx + rotation) % 4]!
  })
}

function findPlacedRoom(board: PlacedRoom[], floor: Floor, row: number, col: number) {
  return board.find((p) => p.floor === floor && p.row === row && p.col === col)
}

function getRoomDoors(placed: PlacedRoom): Direction[] {
  const def = ROOM_MAP[placed.roomId]
  if (!def) return []
  return rotateDoors(def.doors, placed.rotation)
}

/** Find a rotation that makes at least one door face the required direction */
function findRotation(roomDef: RoomDef, requiredDir: Direction): number {
  for (let rot = 0; rot < 4; rot++) {
    const rotated = rotateDoors(roomDef.doors, rot)
    if (rotated.includes(requiredDir)) {
      return rot
    }
  }
  return 0
}

/* ------------------------------------------------------------------ */
/*  Card Display Overlay                                               */
/* ------------------------------------------------------------------ */

function CardOverlay({
  card,
  onDismiss,
}: {
  card: CardDef
  onDismiss: () => void
}) {
  const typeColors: Record<string, string> = {
    event: '#f5c542',
    item: '#42adf5',
    omen: '#c842f5',
  }
  const color = typeColors[card.type] ?? '#888'

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm">
      <div
        className="max-w-sm w-full rounded-xl overflow-hidden shadow-2xl"
        style={{ border: `3px solid ${color}` }}
      >
        {/* Header */}
        <div
          className="px-5 py-3 text-center"
          style={{ background: `${color}30` }}
        >
          <span
            className="text-xs font-bold uppercase tracking-widest"
            style={{ color }}
          >
            {card.type}
          </span>
        </div>

        {/* Body */}
        <div className="bg-gray-900 px-5 py-6 space-y-4">
          <h3 className="text-xl font-bold text-white text-center">
            {card.name}
          </h3>
          <p className="text-sm text-gray-400 italic text-center leading-relaxed">
            &ldquo;{card.flavour}&rdquo;
          </p>
          <div
            className="text-sm text-gray-200 text-center p-3 rounded-lg"
            style={{ background: `${color}15`, border: `1px solid ${color}30` }}
          >
            {card.effect}
          </div>
        </div>

        {/* Footer */}
        <div className="bg-gray-900 px-5 pb-4">
          <button
            type="button"
            onClick={onDismiss}
            className="w-full py-2 rounded-lg text-sm font-bold uppercase tracking-wider transition-colors"
            style={{
              background: color,
              color: '#000',
            }}
          >
            Continue
          </button>
        </div>
      </div>
    </div>
  )
}

/* ------------------------------------------------------------------ */
/*  Haunt Roll Overlay                                                 */
/* ------------------------------------------------------------------ */

function HauntRollOverlay({
  omenCount,
  onRoll,
}: {
  omenCount: number
  onRoll: () => void
}) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-sm">
      <div className="max-w-sm w-full rounded-xl bg-gray-900 p-6 text-center space-y-4 border-2 border-purple-500">
        <h3 className="text-xl font-bold text-purple-400">Haunt Roll</h3>
        <p className="text-sm text-gray-300">
          An Omen has been revealed! Roll {omenCount} {omenCount === 1 ? 'die' : 'dice'} (one per Omen discovered).
          <br />
          If the result is <strong className="text-purple-300">5 or higher</strong>, the haunt begins!
        </p>
        <p className="text-xs text-gray-500">
          Total Omens discovered: {omenCount}
        </p>
        <button
          type="button"
          onClick={onRoll}
          className="px-6 py-3 rounded-lg bg-purple-600 hover:bg-purple-500 text-white font-bold uppercase tracking-wider transition-colors"
        >
          Roll for Haunt
        </button>
      </div>
    </div>
  )
}

/* ------------------------------------------------------------------ */
/*  Character Selection Screen                                         */
/* ------------------------------------------------------------------ */

function CharacterSelect({
  players,
  myPeerId,
  isHost,
  onSelect,
  onStart,
  onShowRules,
}: {
  players: Record<string, PlayerState>
  myPeerId: string
  isHost: boolean
  onSelect: (characterId: string) => void
  onStart: () => void
  onShowRules: () => void
}) {
  const takenIds = new Set(
    Object.values(players)
      .map((p) => p.characterId)
      .filter(Boolean)
  )
  const myChar = players[myPeerId]?.characterId
  const allSelected = Object.values(players).every((p) => p.characterId !== null)

  return (
    <div className="h-full overflow-auto p-4 space-y-6 bg-gray-950">
      <div className="text-center space-y-2">
        <h2 className="text-2xl font-bold text-white">Choose Your Explorer</h2>
        <p className="text-sm text-gray-400">
          Each character has unique starting attributes. Choose wisely.
        </p>
        <button
          type="button"
          onClick={onShowRules}
          className="inline-flex items-center gap-1.5 px-4 py-2 rounded-lg bg-amber-800/30 hover:bg-amber-700/40 text-amber-300 hover:text-amber-200 text-sm font-medium transition-colors border border-amber-700/30"
        >
          <span className="text-base">📖</span> How to Play
        </button>
      </div>

      {/* Player selections */}
      <div className="flex flex-wrap justify-center gap-2">
        {Object.values(players).map((p) => {
          const c = p.characterId ? CHARACTER_MAP[p.characterId] : null
          return (
            <span
              key={p.peerId}
              className="text-xs px-3 py-1.5 rounded-full"
              style={{
                background: c ? `#${c.color.toString(16).padStart(6, '0')}30` : 'rgba(255,255,255,0.06)',
                color: c ? `#${c.color.toString(16).padStart(6, '0')}` : '#888',
                border: `1px solid ${c ? `#${c.color.toString(16).padStart(6, '0')}50` : 'rgba(255,255,255,0.1)'}`,
              }}
            >
              {p.playerName}: {c ? c.name : 'Choosing...'}
            </span>
          )
        })}
      </div>

      {/* Character grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 max-w-5xl mx-auto">
        {CHARACTERS.map((char) => {
          const taken = takenIds.has(char.id) && char.id !== myChar
          const selected = char.id === myChar
          const colorHex = `#${char.color.toString(16).padStart(6, '0')}`

          return (
            <button
              key={char.id}
              type="button"
              disabled={taken}
              onClick={() => onSelect(char.id)}
              className={`
                text-left rounded-xl p-4 transition-all duration-200
                ${taken
                  ? 'opacity-30 cursor-not-allowed'
                  : selected
                    ? 'cursor-pointer'
                    : 'hover:scale-[1.02] cursor-pointer'
                }
              `}
              style={{
                background: selected ? `${colorHex}20` : 'rgba(255,255,255,0.04)',
                border: `2px solid ${selected ? colorHex : 'rgba(255,255,255,0.08)'}`,
                outline: selected ? `2px solid ${colorHex}` : undefined,
                outlineOffset: selected ? '2px' : undefined,
              }}
            >
              <div className="flex items-center gap-3 mb-3">
                <div
                  className="w-10 h-10 rounded-full flex items-center justify-center font-bold text-sm text-white shrink-0"
                  style={{ background: colorHex }}
                >
                  {char.name.split(' ').map((w) => w[0]).join('').slice(0, 2)}
                </div>
                <div>
                  <div className="font-bold text-white text-sm">{char.name}</div>
                  <div className="text-xs text-gray-400">
                    Age {char.age} &middot; {char.colorName}
                  </div>
                </div>
              </div>
              <p className="text-xs text-gray-500 mb-2 italic">{char.description}</p>
              <div className="grid grid-cols-4 gap-1">
                {(['speed', 'might', 'sanity', 'knowledge'] as TraitName[]).map((t) => (
                  <div key={t} className="text-center">
                    <div className="text-[10px] text-gray-500 uppercase">{t.slice(0, 3)}</div>
                    <div className="text-sm font-bold text-gray-300">
                      {char.traits[t].values[char.traits[t].startIndex]}
                    </div>
                  </div>
                ))}
              </div>
            </button>
          )
        })}
      </div>

      {/* Start button */}
      {isHost && (
        <div className="text-center pb-6">
          <button
            type="button"
            disabled={!allSelected}
            onClick={onStart}
            className={`
              px-8 py-3 rounded-xl text-sm font-bold uppercase tracking-wider
              transition-all duration-200
              ${allSelected
                ? 'bg-green-600 hover:bg-green-500 text-white cursor-pointer shadow-lg shadow-green-600/25'
                : 'bg-gray-700 text-gray-500 cursor-not-allowed'
              }
            `}
          >
            {allSelected ? 'Begin Exploration' : 'Waiting for all players...'}
          </button>
        </div>
      )}
    </div>
  )
}

/* ------------------------------------------------------------------ */
/*  Game Log                                                           */
/* ------------------------------------------------------------------ */

function GameLog({ log }: { log: string[] }) {
  const bottomRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [log.length])

  return (
    <div className="h-36 overflow-y-auto text-xs space-y-1 p-2 rounded-lg bg-black/40 border border-white/5">
      {log.length === 0 && (
        <p className="text-gray-600 italic">No events yet...</p>
      )}
      {log.map((entry, i) => (
        <p key={i} className="text-gray-400 leading-tight">
          {entry}
        </p>
      ))}
      <div ref={bottomRef} />
    </div>
  )
}

/* ------------------------------------------------------------------ */
/*  MAIN COMPONENT                                                     */
/* ------------------------------------------------------------------ */

export default function BetrayalGame() {
  const { room, myPeerId } = useConnections()
  const {
    isHost,
    gameState: rawGameState,
    dispatchGameState,
    sendPlayerAction,
    setPlayerActionHandler,
  } = useGame()

  const state = useMemo(
    () => (rawGameState ?? {}) as Partial<BetrayalGameState>,
    [rawGameState]
  )

  const [showingCard, setShowingCard] = useState<CardDef | null>(null)
  const [showHauntRoll, setShowHauntRoll] = useState(false)
  const [showInstructions, setShowInstructions] = useState(false)

  const peerIds = useMemo(
    () => (room ? Object.keys(room.peer_connections) : []),
    [room]
  )

  const playerNames: Record<string, string> = useMemo(
    () =>
      room?.peer_connections
        ? Object.fromEntries(
            Object.entries(room.peer_connections).map(([id, data]) => [
              id,
              (data as { playerName: string }).playerName,
            ])
          )
        : {},
    [room]
  )

  /* ── Host: initialise game state ── */
  const hasInit = useRef(false)
  useEffect(() => {
    if (!isHost || hasInit.current || peerIds.length < 1) return
    hasInit.current = true

    const players: Record<string, PlayerState> = {}
    for (const pid of peerIds) {
      players[pid] = createPlayer(pid, playerNames[pid] ?? 'Player')
    }

    const initial: BetrayalGameState = {
      phase: 'character_select',
      players,
      board: createInitialBoard(),
      eventDeck: shuffle(EVENT_CARDS.map((c) => c.id)),
      itemDeck: shuffle(ITEM_CARDS.map((c) => c.id)),
      omenDeck: shuffle(OMEN_CARDS.map((c) => c.id)),
      discardPile: [],
      currentTurnPeerId: null,
      turnOrder: peerIds,
      turnIndex: 0,
      omenCount: 0,
      hauntRevealed: false,
      hauntTraitorPeerId: null,
      lastDiceRoll: null,
      drawnCard: null,
      pendingRoom: null,
      viewingFloor: 'ground',
      log: ['Welcome to Betrayal at House on the Hill.', 'Choose your explorers to begin.'],
    }

    dispatchGameState(initial as unknown as Record<string, unknown>)
  }, [isHost, peerIds, playerNames, dispatchGameState])

  /* ── Helper to update state (host only) ── */
  const pushState = useCallback(
    (updater: (prev: BetrayalGameState) => BetrayalGameState) => {
      if (!isHost) return
      const current = rawGameState as unknown as BetrayalGameState
      if (!current) return
      const next = updater(current)
      dispatchGameState(next as unknown as Record<string, unknown>)
    },
    [isHost, rawGameState, dispatchGameState]
  )

  /* ── Host: handle player actions ── */
  useEffect(() => {
    if (!isHost) {
      setPlayerActionHandler(null)
      return
    }

    const handler = (fromPeerId: string, action: Record<string, unknown>) => {
      const gs = rawGameState as unknown as BetrayalGameState
      if (!gs) return

      if (action.action === 'select_character') {
        const charId = action.characterId as string
        // Check not taken by another player
        const taken = Object.values(gs.players).some(
          (p) => p.characterId === charId && p.peerId !== fromPeerId
        )
        if (taken) return

        const charDef = CHARACTER_MAP[charId]
        if (!charDef) return

        pushState((prev) => ({
          ...prev,
          players: {
            ...prev.players,
            [fromPeerId]: {
              ...prev.players[fromPeerId]!,
              characterId: charId,
              traitIndices: {
                speed: charDef.traits.speed.startIndex,
                might: charDef.traits.might.startIndex,
                sanity: charDef.traits.sanity.startIndex,
                knowledge: charDef.traits.knowledge.startIndex,
              },
            },
          },
          log: [...prev.log, `${prev.players[fromPeerId]?.playerName} chose ${charDef.name}.`],
        }))
      }

      if (action.action === 'start_exploration') {
        pushState((prev) => {
          const order = shuffle(Object.keys(prev.players))
          const firstPeer = order[0]!
          const me = prev.players[firstPeer]!
          const speed = me.characterId
            ? CHARACTER_MAP[me.characterId]!.traits.speed.values[me.traitIndices.speed]!
            : 4
          return {
            ...prev,
            phase: 'exploration',
            turnOrder: order,
            turnIndex: 0,
            currentTurnPeerId: firstPeer,
            players: {
              ...prev.players,
              [firstPeer]: { ...me, movesRemaining: speed },
            },
            log: [
              ...prev.log,
              'The exploration begins!',
              `${me.playerName}'s turn. (${speed} moves)`,
            ],
          }
        })
      }

      if (action.action === 'move') {
        const dir = action.direction as Direction
        if (!dir) return
        if (gs.currentTurnPeerId !== fromPeerId) return
        handleMove(gs, fromPeerId, dir)
      }

      if (action.action === 'end_turn') {
        if (gs.currentTurnPeerId !== fromPeerId) return
        advanceTurn(gs)
      }

      if (action.action === 'place_room') {
        if (gs.currentTurnPeerId !== fromPeerId) return
        const row = action.row as number
        const col = action.col as number
        handlePlaceRoom(gs, fromPeerId, row, col)
      }

      if (action.action === 'dismiss_card') {
        pushState((prev) => ({ ...prev, drawnCard: null }))
      }

      if (action.action === 'haunt_roll') {
        // 3rd Edition: Roll dice equal to the number of Omens discovered. 5+ triggers the haunt.
        const diceCount = gs.omenCount
        const diceResult = rollDice(diceCount)
        const total = diceResult.reduce<number>((s, d) => s + d, 0)
        const hauntTriggered = total >= 5

        pushState((prev) => ({
          ...prev,
          phase: hauntTriggered ? 'haunt' : 'exploration',
          lastDiceRoll: diceResult,
          hauntRevealed: hauntTriggered || prev.hauntRevealed,
          hauntTraitorPeerId: hauntTriggered ? fromPeerId : prev.hauntTraitorPeerId,
          log: [
            ...prev.log,
            `Haunt roll: ${total} with ${diceCount} dice (5+ triggers haunt).`,
            hauntTriggered
              ? `THE HAUNT BEGINS! ${prev.players[fromPeerId]?.playerName} is the traitor!`
              : 'The haunt is averted... for now.',
          ],
        }))
      }

      if (action.action === 'change_floor') {
        const floor = action.floor as Floor
        pushState((prev) => ({ ...prev, viewingFloor: floor }))
      }
    }

    setPlayerActionHandler(handler)
    return () => setPlayerActionHandler(null)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isHost, rawGameState, pushState, setPlayerActionHandler])

  /* ── Movement logic (host) ── */
  const handleMove = useCallback(
    (gs: BetrayalGameState, peerId: string, dir: Direction) => {
      const player = gs.players[peerId]
      if (!player || player.movesRemaining <= 0) return

      const currentPlaced = findPlacedRoom(gs.board, player.currentFloor, player.currentRow, player.currentCol)
      if (!currentPlaced) return

      const currentDoors = getRoomDoors(currentPlaced)
      if (!currentDoors.includes(dir)) return // no door in that direction

      const target = getAdjacentCell(player.currentRow, player.currentCol, dir)
      const targetPlaced = findPlacedRoom(gs.board, player.currentFloor, target.row, target.col)

      if (targetPlaced) {
        // Move into existing room
        const targetDoors = getRoomDoors(targetPlaced)
        if (!targetDoors.includes(oppositeDir(dir))) return // target has no matching door

        // 3rd Edition: Obstacles (barrier tiles, opposing team members after haunt) cost 2 moves to leave
        const currentRoom = ROOM_MAP[currentPlaced.roomId]
        const moveCost = currentRoom?.barrier ? 2 : 1
        if (player.movesRemaining < moveCost) return

        pushState((prev) => {
          const p = prev.players[peerId]!
          const roomDef = ROOM_MAP[targetPlaced.roomId]
          const newLog = [
            ...prev.log,
            `${p.playerName} moved ${dir} into ${roomDef?.name ?? 'a room'}.`,
          ]

          return {
            ...prev,
            players: {
              ...prev.players,
              [peerId]: {
                ...p,
                currentRow: target.row,
                currentCol: target.col,
                movesRemaining: p.movesRemaining - moveCost,
              },
            },
            log: newLog,
          }
        })
      } else {
        // Discover new room - draw from room stack
        // 3rd Edition: Draw from stack, skip tiles that don't match the current floor
        const availableRooms = ROOM_STACK.filter((r) =>
          r.floors.includes(player.currentFloor) &&
          !gs.board.some((b) => b.roomId === r.id)
        )

        if (availableRooms.length === 0) return

        const randomRoom = availableRooms[Math.floor(Math.random() * availableRooms.length)]!

        pushState((prev) => ({
          ...prev,
          pendingRoom: randomRoom,
          log: [...prev.log, `${player.playerName} discovered ${randomRoom.name}! Place it on the board.`],
        }))
      }
    },
    [pushState]
  )

  /* ── Place room logic (host) ── */
  const handlePlaceRoom = useCallback(
    (gs: BetrayalGameState, peerId: string, row: number, col: number) => {
      const player = gs.players[peerId]
      const pending = gs.pendingRoom
      if (!player || !pending) return

      // Find what door direction the player is approaching from
      const dr = row - player.currentRow
      const dc = col - player.currentCol
      let approachDir: Direction | null = null
      if (dr === -1 && dc === 0) approachDir = 'north'
      if (dr === 1 && dc === 0) approachDir = 'south'
      if (dr === 0 && dc === 1) approachDir = 'east'
      if (dr === 0 && dc === -1) approachDir = 'west'

      const neededDir = approachDir ? oppositeDir(approachDir) : 'north'
      const rotation = findRotation(pending, neededDir)

      const newPlaced: PlacedRoom = {
        roomId: pending.id,
        floor: player.currentFloor,
        row,
        col,
        rotation,
      }

      // Determine if a card should be drawn
      let drawnCardId: string | null = null
      const newEventDeck = [...gs.eventDeck]
      const newItemDeck = [...gs.itemDeck]
      const newOmenDeck = [...gs.omenDeck]
      let newOmenCount = gs.omenCount
      let needsHauntRoll = false

      if (pending.cardDraw) {
        if (pending.cardDraw === 'event' && newEventDeck.length > 0) {
          drawnCardId = newEventDeck.shift()!
        } else if (pending.cardDraw === 'item' && newItemDeck.length > 0) {
          drawnCardId = newItemDeck.shift()!
        } else if (pending.cardDraw === 'omen' && newOmenDeck.length > 0) {
          drawnCardId = newOmenDeck.shift()!
          newOmenCount++
          // 3rd Edition: If you draw the final Omen card, the haunt starts automatically
          if (newOmenDeck.length === 0) {
            needsHauntRoll = false // auto-trigger instead
          } else {
            needsHauntRoll = true
          }
        }
      }

      // Check if last omen triggers haunt automatically
      const autoHaunt = pending.cardDraw === 'omen' && newOmenDeck.length === 0

      pushState((prev) => {
        const p = prev.players[peerId]!
        const cardDef = drawnCardId ? CARD_MAP[drawnCardId] : null
        const newItems = cardDef?.type === 'item' ? [...p.items, drawnCardId!] : [...p.items]
        const newOmens = cardDef?.type === 'omen' ? [...p.omens, drawnCardId!] : [...p.omens]
        const logEntries = [...prev.log]

        if (drawnCardId && cardDef) {
          logEntries.push(`${p.playerName} drew ${cardDef.type}: ${cardDef.name}.`)
        }

        if (autoHaunt) {
          logEntries.push('The final Omen has been drawn! The haunt begins automatically!')
          logEntries.push(`THE HAUNT BEGINS! ${p.playerName} is the traitor!`)
        }

        return {
          ...prev,
          board: [...prev.board, newPlaced],
          pendingRoom: null,
          eventDeck: newEventDeck,
          itemDeck: newItemDeck,
          omenDeck: newOmenDeck,
          omenCount: newOmenCount,
          drawnCard: drawnCardId,
          phase: autoHaunt ? 'haunt' : needsHauntRoll ? 'haunt_roll' : prev.phase,
          hauntRevealed: autoHaunt || prev.hauntRevealed,
          hauntTraitorPeerId: autoHaunt ? peerId : prev.hauntTraitorPeerId,
          players: {
            ...prev.players,
            [peerId]: {
              ...p,
              currentRow: row,
              currentCol: col,
              movesRemaining: 0, // 3rd Edition: Discovering a room ends your turn
              items: newItems,
              omens: newOmens,
            },
          },
          log: logEntries,
        }
      })
    },
    [pushState]
  )

  /* ── Advance turn (host) ── */
  const advanceTurn = useCallback(
    (gs: BetrayalGameState) => {
      const nextIdx = (gs.turnIndex + 1) % gs.turnOrder.length
      const nextPeerId = gs.turnOrder[nextIdx]!
      const nextPlayer = gs.players[nextPeerId]!
      const speed = nextPlayer.characterId
        ? CHARACTER_MAP[nextPlayer.characterId]!.traits.speed.values[nextPlayer.traitIndices.speed]!
        : 4

      pushState((prev) => ({
        ...prev,
        turnIndex: nextIdx,
        currentTurnPeerId: nextPeerId,
        lastDiceRoll: null,
        drawnCard: null,
        pendingRoom: null,
        players: {
          ...prev.players,
          [nextPeerId]: { ...prev.players[nextPeerId]!, movesRemaining: speed },
        },
        log: [
          ...prev.log,
          `${nextPlayer.playerName}'s turn. (${speed} moves)`,
        ],
      }))
    },
    [pushState]
  )

  /* ── Player actions (any player) ── */

  const selectCharacter = useCallback(
    (charId: string) => {
      sendPlayerAction({ action: 'select_character', characterId: charId })
    },
    [sendPlayerAction]
  )

  const startExploration = useCallback(() => {
    sendPlayerAction({ action: 'start_exploration' })
  }, [sendPlayerAction])

  const movePlayer = useCallback(
    (dir: Direction) => {
      sendPlayerAction({ action: 'move', direction: dir })
    },
    [sendPlayerAction]
  )

  const endTurn = useCallback(() => {
    sendPlayerAction({ action: 'end_turn' })
  }, [sendPlayerAction])

  const placeTile = useCallback(
    (row: number, col: number) => {
      if (state.pendingRoom) {
        sendPlayerAction({ action: 'place_room', row, col })
      }
    },
    [state.pendingRoom, sendPlayerAction]
  )

  const dismissCard = useCallback(() => {
    setShowingCard(null)
    sendPlayerAction({ action: 'dismiss_card' })
  }, [sendPlayerAction])

  const doHauntRoll = useCallback(() => {
    setShowHauntRoll(false)
    sendPlayerAction({ action: 'haunt_roll' })
  }, [sendPlayerAction])

  const changeFloor = useCallback(
    (floor: Floor) => {
      sendPlayerAction({ action: 'change_floor', floor })
    },
    [sendPlayerAction]
  )

  /* ── Show card when drawn ── */
  useEffect(() => {
    if (state.drawnCard) {
      const card = CARD_MAP[state.drawnCard]
      if (card) setShowingCard(card)
    }
  }, [state.drawnCard])

  useEffect(() => {
    if (state.phase === 'haunt_roll') {
      setShowHauntRoll(true)
    }
  }, [state.phase])

  /* ── Render ── */

  if (!state.phase) {
    return (
      <div className="p-6 text-center">
        <div className="animate-pulse text-muted-foreground">Setting up...</div>
      </div>
    )
  }

  // Character selection phase
  if (state.phase === 'character_select') {
    return (
      <>
        <CharacterSelect
          players={state.players ?? {}}
          myPeerId={myPeerId ?? ''}
          isHost={isHost}
          onSelect={selectCharacter}
          onStart={startExploration}
          onShowRules={() => setShowInstructions(true)}
        />
        <GameInstructions
          isOpen={showInstructions}
          onClose={() => setShowInstructions(false)}
        />
      </>
    )
  }

  // Haunt revealed
  if (state.phase === 'haunt') {
    const traitor = state.hauntTraitorPeerId
      ? state.players?.[state.hauntTraitorPeerId]
      : null
    const traitorChar = traitor?.characterId
      ? CHARACTER_MAP[traitor.characterId]
      : null

    return (
      <div className="h-full flex items-center justify-center bg-gray-950 p-6">
        <div className="max-w-lg text-center space-y-6">
          <h2 className="text-4xl font-bold text-red-500 animate-pulse">
            THE HAUNT BEGINS
          </h2>
          <div className="text-6xl">&#128128;</div>
          {traitor && traitorChar && (
            <div className="space-y-2">
              <p className="text-xl text-gray-200">
                <strong
                  style={{
                    color: `#${traitorChar.color.toString(16).padStart(6, '0')}`,
                  }}
                >
                  {traitorChar.name}
                </strong>{' '}
                ({traitor.playerName}) is the traitor!
              </p>
            </div>
          )}
          <p className="text-sm text-gray-500">
            {state.omenCount} omens were found before the haunt was triggered.
          </p>
          <div className="text-sm text-gray-400 max-w-md mx-auto">
            In the full game, a specific haunt scenario would now be revealed
            based on the omen and room that triggered it. The traitor takes
            their Traitor&apos;s Tome and the heroes consult the Secrets of Survival.
          </div>

          {/* Show all character sheets */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 mt-8">
            {Object.values(state.players ?? {}).map((p) => (
              <CharacterSheet
                key={p.peerId}
                player={p}
                isCurrentPlayer={p.peerId === myPeerId}
                compact
              />
            ))}
          </div>
        </div>
      </div>
    )
  }

  // Main exploration / game view
  const fullState = state as BetrayalGameState
  const isMyTurn = fullState.currentTurnPeerId === myPeerId
  const myPlayer = myPeerId ? fullState.players[myPeerId] : null
  const currentTurnPlayer = fullState.currentTurnPeerId
    ? fullState.players[fullState.currentTurnPeerId]
    : null

  return (
    <div className="h-full flex flex-col lg:flex-row bg-gray-950 overflow-hidden">
      {/* ── Left panel: Board ── */}
      <div className="flex-1 relative min-h-0">
        <PixiBoard
          gameState={fullState}
          myPeerId={myPeerId}
          onTileClick={(row, col) => {
            if (fullState.pendingRoom) {
              placeTile(row, col)
            }
          }}
          onPlayerMove={(dir) => {
            if (isMyTurn) movePlayer(dir)
          }}
        />

        {/* Floor tabs */}
        <div className="absolute top-3 right-3 flex gap-1 z-10">
          {(['upper', 'ground', 'basement'] as Floor[]).map((f) => (
            <button
              key={f}
              type="button"
              onClick={() => changeFloor(f)}
              className={`
                px-3 py-1.5 rounded-lg text-xs font-bold uppercase tracking-wider
                transition-all duration-200
                ${fullState.viewingFloor === f
                  ? 'bg-white text-black shadow-lg'
                  : 'bg-white/10 text-white/60 hover:bg-white/20'
                }
              `}
            >
              {f === 'upper' ? 'Upper' : f === 'ground' ? 'Ground' : 'Basement'}
            </button>
          ))}
        </div>

        {/* Movement hint */}
        {isMyTurn && myPlayer && myPlayer.movesRemaining > 0 && (
          <div className="absolute bottom-3 left-3 bg-black/70 rounded-lg px-3 py-2 text-xs text-white/80 z-10">
            Arrow keys / WASD to move &middot; {myPlayer.movesRemaining} moves left
          </div>
        )}

        {/* Pending room notice */}
        {fullState.pendingRoom && isMyTurn && (
          <div className="absolute top-3 left-3 bg-green-900/80 border border-green-500/50 rounded-lg px-4 py-2 z-10">
            <p className="text-sm text-green-200 font-medium">
              Place: <strong>{fullState.pendingRoom.name}</strong>
            </p>
            <p className="text-xs text-green-400/70">Click a highlighted cell on the board</p>
          </div>
        )}
      </div>

      {/* ── Right panel: Character & controls ── */}
      <div className="w-full lg:w-96 shrink-0 border-t lg:border-t-0 lg:border-l border-white/10 bg-gray-900/50 flex flex-col overflow-hidden">
        {/* Turn indicator & instructions button */}
        <div className="p-3 border-b border-white/10">
          <div className="flex items-center justify-between">
            <div>
              <span className="text-xs text-gray-500 uppercase tracking-wider">
                Current Turn
              </span>
              <p className="text-sm font-bold text-white">
                {currentTurnPlayer?.playerName ?? '...'}
                {isMyTurn && (
                  <span className="ml-2 text-green-400 text-xs">(You)</span>
                )}
              </p>
            </div>
            <div className="flex items-center gap-3">
              <div className="text-right">
                <span className="text-xs text-gray-500">Omens</span>
                <p className="text-sm font-bold text-purple-400">
                  {fullState.omenCount}/{OMEN_CARDS.length}
                </p>
              </div>
              <button
                type="button"
                onClick={() => setShowInstructions(true)}
                className="w-8 h-8 rounded-lg bg-amber-800/30 hover:bg-amber-700/40 text-amber-300 hover:text-amber-200 flex items-center justify-center text-sm font-bold transition-colors border border-amber-700/30"
                title="How to Play"
              >
                ?
              </button>
            </div>
          </div>
        </div>

        {/* My character sheet */}
        <div className="p-3 space-y-3 overflow-y-auto flex-1">
          {myPlayer && (
            <CharacterSheet
              player={myPlayer}
              isCurrentPlayer={isMyTurn}
            />
          )}

          {/* Turn Actions Guide */}
          <TurnActions
            isMyTurn={isMyTurn}
            movesRemaining={myPlayer?.movesRemaining ?? 0}
            hasPendingRoom={!!fullState.pendingRoom}
            phase={fullState.phase}
          />

          {/* Movement controls */}
          {isMyTurn && (
            <div className="space-y-2">
              <h4 className="text-xs text-gray-500 uppercase tracking-wider font-bold">
                Movement
              </h4>
              <div className="grid grid-cols-3 gap-1.5 max-w-[180px] mx-auto">
                <div />
                <button
                  type="button"
                  onClick={() => movePlayer('north')}
                  disabled={!myPlayer || myPlayer.movesRemaining <= 0}
                  className="px-3 py-2.5 rounded-lg bg-white/5 hover:bg-white/15 text-white text-sm font-bold disabled:opacity-20 disabled:cursor-not-allowed transition-colors border border-white/10"
                >
                  &#8593;
                </button>
                <div />
                <button
                  type="button"
                  onClick={() => movePlayer('west')}
                  disabled={!myPlayer || myPlayer.movesRemaining <= 0}
                  className="px-3 py-2.5 rounded-lg bg-white/5 hover:bg-white/15 text-white text-sm font-bold disabled:opacity-20 disabled:cursor-not-allowed transition-colors border border-white/10"
                >
                  &#8592;
                </button>
                <div className="flex items-center justify-center">
                  <span className="text-xs text-gray-500 font-mono">{myPlayer?.movesRemaining ?? 0}</span>
                </div>
                <button
                  type="button"
                  onClick={() => movePlayer('east')}
                  disabled={!myPlayer || myPlayer.movesRemaining <= 0}
                  className="px-3 py-2.5 rounded-lg bg-white/5 hover:bg-white/15 text-white text-sm font-bold disabled:opacity-20 disabled:cursor-not-allowed transition-colors border border-white/10"
                >
                  &#8594;
                </button>
                <div />
                <button
                  type="button"
                  onClick={() => movePlayer('south')}
                  disabled={!myPlayer || myPlayer.movesRemaining <= 0}
                  className="px-3 py-2.5 rounded-lg bg-white/5 hover:bg-white/15 text-white text-sm font-bold disabled:opacity-20 disabled:cursor-not-allowed transition-colors border border-white/10"
                >
                  &#8595;
                </button>
                <div />
              </div>
              <button
                type="button"
                onClick={endTurn}
                className="w-full py-2.5 rounded-lg bg-amber-800/60 hover:bg-amber-700/70 text-amber-100 text-sm font-bold uppercase tracking-wider transition-colors border border-amber-700/40"
              >
                End Turn
              </button>
            </div>
          )}

          {/* Other players (compact) */}
          <div className="space-y-2">
            <h4 className="text-xs text-gray-500 uppercase tracking-wider font-bold">
              Other Explorers
            </h4>
            {Object.values(fullState.players)
              .filter((p) => p.peerId !== myPeerId)
              .map((p) => (
                <CharacterSheet
                  key={p.peerId}
                  player={p}
                  compact
                />
              ))}
          </div>

          {/* Dice result */}
          {fullState.lastDiceRoll && (
            <div className="p-3 rounded-lg bg-black/30 border border-white/5">
              <DiceRoller
                diceCount={fullState.lastDiceRoll.length}
                result={fullState.lastDiceRoll}
                label="Last Roll"
              />
            </div>
          )}

          {/* Game log */}
          <div>
            <h4 className="text-xs text-gray-500 uppercase tracking-wider font-bold mb-2">
              Log
            </h4>
            <GameLog log={fullState.log} />
          </div>
        </div>
      </div>

      {/* ── Overlays ── */}
      {showingCard && (
        <CardOverlay card={showingCard} onDismiss={dismissCard} />
      )}
      {showHauntRoll && state.phase === 'haunt_roll' && (
        <HauntRollOverlay
          omenCount={fullState.omenCount}
          onRoll={doHauntRoll}
        />
      )}
      <GameInstructions
        isOpen={showInstructions}
        onClose={() => setShowInstructions(false)}
      />
    </div>
  )
}
