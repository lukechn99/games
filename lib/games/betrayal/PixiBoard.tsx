'use client'

import { useRef, useEffect, useCallback } from 'react'
import { Application, Container, Graphics, Text, TextStyle, FederatedPointerEvent } from 'pixi.js'
import type { Floor, PlayerState, Direction, BetrayalGameState, RoomDef } from './types'
import { ROOM_MAP } from './data/rooms'
import { CHARACTER_MAP } from './data/characters'

/* ------------------------------------------------------------------ */
/*  Constants                                                          */
/* ------------------------------------------------------------------ */

const TILE_SIZE = 130
const TILE_GAP = 4
const CELL = TILE_SIZE + TILE_GAP
const GRID_OFFSET_X = 800
const GRID_OFFSET_Y = 600

/* ── Gothic color palettes per floor ── */
const FLOOR_BG: Record<Floor, number> = {
  ground: 0x1a1510,    // deep dark brown
  upper: 0x0e1520,     // midnight blue
  basement: 0x1a0e0e,  // blood-dark
}

const FLOOR_TILE_BG: Record<Floor, number> = {
  ground: 0x3a3020,    // warm wood
  upper: 0x263548,      // dusty blue
  basement: 0x3d2020,   // dark crimson
}

const FLOOR_BORDER: Record<Floor, number> = {
  ground: 0x6b5a3a,    // aged gold/wood trim
  upper: 0x4a6a8a,     // faded blue/silver
  basement: 0x7a3a3a,  // blood red trim
}

const FLOOR_ACCENT: Record<Floor, number> = {
  ground: 0xc9a55a,    // golden
  upper: 0x7aabd4,     // silver-blue
  basement: 0xd45a5a,  // crimson
}

const CARD_TYPE_COLORS: Record<string, number> = {
  event: 0xf5c542,
  item: 0x42adf5,
  omen: 0xc842f5,
}

const CARD_TYPE_ICONS: Record<string, string> = {
  event: '⚡',
  item: '🛡',
  omen: '🔮',
}

const DOOR_THICKNESS = 8
const DOOR_LENGTH = 28
const DOOR_COLOR = 0xd4a574 // warm wood door color

/* ------------------------------------------------------------------ */
/*  Helpers                                                            */
/* ------------------------------------------------------------------ */

function rotateDoors(doors: Direction[], rotation: number): Direction[] {
  const order: Direction[] = ['north', 'east', 'south', 'west']
  return doors.map((d) => {
    const idx = order.indexOf(d)
    return order[(idx + rotation) % 4]!
  })
}

function gridToPixel(row: number, col: number) {
  return {
    x: GRID_OFFSET_X + col * CELL,
    y: GRID_OFFSET_Y + row * CELL,
  }
}

/** Deterministic hash for consistent "random" patterns per tile */
function hashStr(s: string): number {
  let hash = 0
  for (let i = 0; i < s.length; i++) {
    const char = s.charCodeAt(i)
    hash = ((hash << 5) - hash) + char
    hash = hash & hash
  }
  return Math.abs(hash)
}

/* ------------------------------------------------------------------ */
/*  Drawing helpers for atmospheric tiles                              */
/* ------------------------------------------------------------------ */

function drawWoodFloor(gfx: Graphics, x: number, y: number, w: number, h: number, seed: number) {
  // Draw wood plank pattern
  const plankCount = 5 + (seed % 3)
  const plankHeight = h / plankCount
  for (let i = 0; i < plankCount; i++) {
    const py = y + i * plankHeight
    const shade = ((seed + i * 7) % 20) - 10
    const color = 0x3a3020 + (shade > 0 ? shade * 0x010100 : 0)
    gfx.rect(x + 2, py + 1, w - 4, plankHeight - 2)
    gfx.fill({ color, alpha: 0.3 })
  }
}

function drawStoneFloor(gfx: Graphics, x: number, y: number, w: number, h: number, seed: number) {
  // Draw stone block pattern
  const rows = 3 + (seed % 2)
  const blockH = h / rows
  for (let r = 0; r < rows; r++) {
    const cols = 2 + ((seed + r) % 3)
    const blockW = w / cols
    const offset = (r % 2) * (blockW / 2)
    for (let c = 0; c < cols + 1; c++) {
      const bx = x + c * blockW - offset
      const by = y + r * blockH
      if (bx < x - blockW || bx > x + w) continue
      gfx.rect(bx + 1, by + 1, blockW - 2, blockH - 2)
      gfx.fill({ color: 0x2a1818, alpha: 0.25 })
      gfx.stroke({ color: 0x1a0e0e, width: 0.5, alpha: 0.3 })
    }
  }
}

function drawDustyFloor(gfx: Graphics, x: number, y: number, w: number, h: number, seed: number) {
  // Carpet/dusty pattern for upper floor
  const margin = 8
  gfx.rect(x + margin, y + margin, w - margin * 2, h - margin * 2)
  gfx.fill({ color: 0x1e2d3e, alpha: 0.3 })
  gfx.stroke({ color: 0x4a6a8a, width: 0.5, alpha: 0.15 })
  
  // Add subtle dust particles
  for (let i = 0; i < 6; i++) {
    const dx = x + margin + ((seed * (i + 1) * 37) % (w - margin * 2))
    const dy = y + margin + ((seed * (i + 1) * 53) % (h - margin * 2))
    gfx.circle(dx, dy, 1)
    gfx.fill({ color: 0xffffff, alpha: 0.05 })
  }
}

/* ── Draw a gothic door ── */
function drawDoor(gfx: Graphics, x: number, y: number, dir: Direction, floor: Floor) {
  const doorColor = DOOR_COLOR
  const archColor = FLOOR_ACCENT[floor]
  
  let dx: number, dy: number, dw: number, dh: number

  switch (dir) {
    case 'north':
      dx = x + TILE_SIZE / 2 - DOOR_LENGTH / 2
      dy = y - DOOR_THICKNESS / 2
      dw = DOOR_LENGTH
      dh = DOOR_THICKNESS
      break
    case 'south':
      dx = x + TILE_SIZE / 2 - DOOR_LENGTH / 2
      dy = y + TILE_SIZE - DOOR_THICKNESS / 2
      dw = DOOR_LENGTH
      dh = DOOR_THICKNESS
      break
    case 'east':
      dx = x + TILE_SIZE - DOOR_THICKNESS / 2
      dy = y + TILE_SIZE / 2 - DOOR_LENGTH / 2
      dw = DOOR_THICKNESS
      dh = DOOR_LENGTH
      break
    case 'west':
      dx = x - DOOR_THICKNESS / 2
      dy = y + TILE_SIZE / 2 - DOOR_LENGTH / 2
      dw = DOOR_THICKNESS
      dh = DOOR_LENGTH
      break
  }

  // Door frame (darker)
  gfx.roundRect(dx! - 2, dy! - 2, dw! + 4, dh! + 4, 2)
  gfx.fill({ color: 0x2a1a10, alpha: 0.8 })
  
  // Door itself
  gfx.roundRect(dx!, dy!, dw!, dh!, 2)
  gfx.fill(doorColor)
  
  // Small arch accent
  gfx.roundRect(dx!, dy!, dw!, dh!, 2)
  gfx.stroke({ color: archColor, width: 1, alpha: 0.5 })
}

/* ── Draw a character token with detail ── */
function drawCharacterToken(
  world: Container,
  tx: number,
  ty: number,
  color: number,
  initials: string,
  isMe: boolean,
  isCurrentTurn: boolean
) {
  const tokenRadius = 16
  const token = new Graphics()

  // Glow for current turn
  if (isCurrentTurn) {
    token.circle(tx, ty, tokenRadius + 6)
    token.fill({ color: 0x00ff88, alpha: 0.15 })
    token.circle(tx, ty, tokenRadius + 4)
    token.stroke({ color: 0x00ff88, width: 1.5, alpha: 0.4 })
  }

  // Drop shadow
  token.circle(tx + 2, ty + 2, tokenRadius)
  token.fill({ color: 0x000000, alpha: 0.4 })

  // Outer ring (darker)
  token.circle(tx, ty, tokenRadius + 1)
  token.fill({ color: 0x000000, alpha: 0.6 })

  // Main circle with gradient-like effect
  token.circle(tx, ty, tokenRadius)
  token.fill(color)

  // Inner highlight (glossy effect)
  token.circle(tx - 3, ty - 4, tokenRadius * 0.5)
  token.fill({ color: 0xffffff, alpha: 0.15 })

  // Border
  token.circle(tx, ty, tokenRadius)
  token.stroke({ color: isMe ? 0xffffff : 0x000000, width: isMe ? 3 : 2, alpha: isMe ? 0.9 : 0.7 })

  // "Me" indicator ring
  if (isMe) {
    token.circle(tx, ty, tokenRadius + 3)
    token.stroke({ color: 0xffffff, width: 1.5, alpha: 0.5 })
  }

  world.addChild(token)

  // Initials text
  const initialText = new Text({
    text: initials,
    style: new TextStyle({
      fontFamily: '"Palatino Linotype", "Book Antiqua", Palatino, Georgia, serif',
      fontSize: 12,
      fontWeight: 'bold',
      fill: 0xffffff,
      stroke: { color: 0x000000, width: 3 },
    }),
  })
  initialText.anchor.set(0.5)
  initialText.x = tx
  initialText.y = ty
  world.addChild(initialText)
}

/* ------------------------------------------------------------------ */
/*  Room tile rendering                                                */
/* ------------------------------------------------------------------ */

function drawRoomTile(
  world: Container,
  placed: { roomId: string; row: number; col: number; rotation: number; floor: Floor },
  roomDef: RoomDef,
  floor: Floor,
  onTileClickRef: React.RefObject<((row: number, col: number) => void) | undefined>
) {
  const tileContainer = new Container()
  const { x, y } = gridToPixel(placed.row, placed.col)
  tileContainer.x = x
  tileContainer.y = y

  const bg = new Graphics()
  const seed = hashStr(placed.roomId)

  // === Gothic tile background ===
  
  // Base fill with rounded corners
  bg.roundRect(0, 0, TILE_SIZE, TILE_SIZE, 4)
  bg.fill(FLOOR_TILE_BG[floor])

  // Floor-specific texture pattern
  if (floor === 'ground') {
    drawWoodFloor(bg, 0, 0, TILE_SIZE, TILE_SIZE, seed)
  } else if (floor === 'basement') {
    drawStoneFloor(bg, 0, 0, TILE_SIZE, TILE_SIZE, seed)
  } else {
    drawDustyFloor(bg, 0, 0, TILE_SIZE, TILE_SIZE, seed)
  }

  // Vignette effect (darker edges)
  bg.rect(0, 0, TILE_SIZE, 6)
  bg.fill({ color: 0x000000, alpha: 0.2 })
  bg.rect(0, TILE_SIZE - 6, TILE_SIZE, 6)
  bg.fill({ color: 0x000000, alpha: 0.2 })
  bg.rect(0, 0, 6, TILE_SIZE)
  bg.fill({ color: 0x000000, alpha: 0.15 })
  bg.rect(TILE_SIZE - 6, 0, 6, TILE_SIZE)
  bg.fill({ color: 0x000000, alpha: 0.15 })

  // Decorative border
  bg.roundRect(0, 0, TILE_SIZE, TILE_SIZE, 4)
  bg.stroke({ color: FLOOR_BORDER[floor], width: 2, alpha: 0.7 })

  // Inner decorative line
  bg.roundRect(3, 3, TILE_SIZE - 6, TILE_SIZE - 6, 3)
  bg.stroke({ color: FLOOR_BORDER[floor], width: 0.5, alpha: 0.25 })

  tileContainer.addChild(bg)

  // === Doors ===
  const rotatedDoors = rotateDoors(roomDef.doors, placed.rotation)
  const doorGfx = new Graphics()
  for (const dir of rotatedDoors) {
    drawDoor(doorGfx, 0, 0, dir, floor)
  }
  tileContainer.addChild(doorGfx)

  // === Room name ===
  const nameText = new Text({
    text: roomDef.name,
    style: new TextStyle({
      fontFamily: '"Palatino Linotype", "Book Antiqua", Palatino, Georgia, serif',
      fontSize: 11,
      fontWeight: 'bold',
      fill: 0xffffff,
      align: 'center',
      wordWrap: true,
      wordWrapWidth: TILE_SIZE - 20,
      stroke: { color: 0x000000, width: 3 },
      letterSpacing: 0.5,
    }),
  })
  nameText.anchor.set(0.5, 0)
  nameText.x = TILE_SIZE / 2
  nameText.y = 10
  tileContainer.addChild(nameText)

  // === Effect text (short flavour) ===
  if (roomDef.effect) {
    const shortEffect = roomDef.effect.length > 50
      ? roomDef.effect.slice(0, 47) + '...'
      : roomDef.effect
    const effectText = new Text({
      text: shortEffect,
      style: new TextStyle({
        fontFamily: '"Palatino Linotype", "Book Antiqua", Palatino, Georgia, serif',
        fontSize: 8,
        fontStyle: 'italic',
        fill: FLOOR_ACCENT[floor],
        align: 'center',
        wordWrap: true,
        wordWrapWidth: TILE_SIZE - 20,
        stroke: { color: 0x000000, width: 2 },
      }),
    })
    effectText.anchor.set(0.5, 1)
    effectText.x = TILE_SIZE / 2
    effectText.y = TILE_SIZE - 10
    effectText.alpha = 0.7
    tileContainer.addChild(effectText)
  }

  // === Card type indicator (gothic badge) ===
  if (roomDef.cardDraw) {
    const cardColor = CARD_TYPE_COLORS[roomDef.cardDraw] ?? 0x888888
    const icon = CARD_TYPE_ICONS[roomDef.cardDraw] ?? '?'

    // Badge background
    const badge = new Graphics()
    badge.roundRect(TILE_SIZE - 30, TILE_SIZE - 30, 24, 24, 4)
    badge.fill({ color: 0x000000, alpha: 0.6 })
    badge.roundRect(TILE_SIZE - 30, TILE_SIZE - 30, 24, 24, 4)
    badge.stroke({ color: cardColor, width: 1.5, alpha: 0.8 })
    tileContainer.addChild(badge)

    const typeText = new Text({
      text: icon,
      style: new TextStyle({
        fontSize: 12,
      }),
    })
    typeText.anchor.set(0.5)
    typeText.x = TILE_SIZE - 18
    typeText.y = TILE_SIZE - 18
    tileContainer.addChild(typeText)
  }

  // === Starting tile indicator (golden star) ===
  if (roomDef.isStarting) {
    const starGfx = new Graphics()
    // Star shape approximation using small diamond
    starGfx.star(16, TILE_SIZE - 16, 5, 7, 3)
    starGfx.fill({ color: 0xffd700, alpha: 0.8 })
    starGfx.stroke({ color: 0x000000, width: 1, alpha: 0.5 })
    tileContainer.addChild(starGfx)
  }

  // === Barrier indicator ===
  if (roomDef.barrier) {
    const barrierGfx = new Graphics()
    barrierGfx.roundRect(4, 4, TILE_SIZE - 8, TILE_SIZE - 8, 3)
    barrierGfx.stroke({ color: 0xff4444, width: 1, alpha: 0.3 })
    tileContainer.addChild(barrierGfx)

    const barrierText = new Text({
      text: '⚠',
      style: new TextStyle({ fontSize: 10 }),
    })
    barrierText.anchor.set(0.5)
    barrierText.x = 16
    barrierText.y = 16
    barrierText.alpha = 0.6
    tileContainer.addChild(barrierText)
  }

  // === Click handler ===
  bg.eventMode = 'static'
  bg.cursor = 'pointer'
  const row = placed.row
  const col = placed.col
  bg.on('pointerdown', (e: FederatedPointerEvent) => {
    if (e.button === 0 && !e.shiftKey) {
      onTileClickRef.current?.(row, col)
    }
  })

  world.addChild(tileContainer)
}

/* ------------------------------------------------------------------ */
/*  Component                                                          */
/* ------------------------------------------------------------------ */

interface PixiBoardProps {
  gameState: BetrayalGameState
  myPeerId: string | null
  onTileClick?: (row: number, col: number) => void
  onPlayerMove?: (direction: Direction) => void
}

export default function PixiBoard({
  gameState,
  myPeerId,
  onTileClick,
  onPlayerMove,
}: PixiBoardProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const appRef = useRef<Application | null>(null)
  const worldRef = useRef<Container | null>(null)
  const isPanningRef = useRef(false)
  const lastPanRef = useRef({ x: 0, y: 0 })
  const panOffsetRef = useRef({ x: 0, y: 0 })
  const scaleRef = useRef(1)

  // Store callbacks in refs for stable access
  const onTileClickRef = useRef(onTileClick)
  onTileClickRef.current = onTileClick
  const onPlayerMoveRef = useRef(onPlayerMove)
  onPlayerMoveRef.current = onPlayerMove
  const gameStateRef = useRef(gameState)
  gameStateRef.current = gameState

  /* ── Initialise Pixi ── */
  useEffect(() => {
    const div = containerRef.current
    if (!div) return

    const app = new Application()
    appRef.current = app

    let destroyed = false

    const init = async () => {
      await app.init({
        resizeTo: div,
        backgroundColor: FLOOR_BG[gameState.viewingFloor],
        antialias: true,
        resolution: window.devicePixelRatio || 1,
        autoDensity: true,
      })

      if (destroyed) { app.destroy(true, { children: true }); return }

      div.appendChild(app.canvas)
      app.canvas.style.width = '100%'
      app.canvas.style.height = '100%'

      const world = new Container()
      world.label = 'world'
      app.stage.addChild(world)
      worldRef.current = world

      // Pan & zoom handlers on the stage
      app.stage.eventMode = 'static'
      app.stage.hitArea = app.screen

      app.stage.on('pointerdown', (e: FederatedPointerEvent) => {
        if (e.button === 1 || e.button === 2 || (e.button === 0 && e.shiftKey)) {
          isPanningRef.current = true
          lastPanRef.current = { x: e.globalX, y: e.globalY }
        }
      })

      app.stage.on('pointermove', (e: FederatedPointerEvent) => {
        if (!isPanningRef.current) return
        const dx = e.globalX - lastPanRef.current.x
        const dy = e.globalY - lastPanRef.current.y
        panOffsetRef.current.x += dx
        panOffsetRef.current.y += dy
        lastPanRef.current = { x: e.globalX, y: e.globalY }
        if (worldRef.current) {
          worldRef.current.x = panOffsetRef.current.x
          worldRef.current.y = panOffsetRef.current.y
        }
      })

      const pointerUp = () => { isPanningRef.current = false }
      app.stage.on('pointerup', pointerUp)
      app.stage.on('pointerupoutside', pointerUp)

      // Wheel zoom
      div.addEventListener('wheel', (e: WheelEvent) => {
        e.preventDefault()
        const factor = e.deltaY > 0 ? 0.9 : 1.1
        scaleRef.current = Math.max(0.2, Math.min(3, scaleRef.current * factor))
        if (worldRef.current) {
          worldRef.current.scale.set(scaleRef.current)
        }
      }, { passive: false })
    }

    init()

    return () => {
      destroyed = true
      if (app.canvas?.parentElement) {
        app.canvas.parentElement.removeChild(app.canvas)
      }
      app.destroy(true, { children: true })
      appRef.current = null
      worldRef.current = null
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  /* ── Re-draw when game state changes ── */
  const draw = useCallback(() => {
    const world = worldRef.current
    const app = appRef.current
    if (!world || !app) return

    const state = gameStateRef.current
    const floor = state.viewingFloor

    // Update background
    app.renderer.background.color = FLOOR_BG[floor]

    // Clear previous children
    world.removeChildren()

    // ── Atmospheric grid background ──
    const gridGuide = new Graphics()
    for (let r = -12; r <= 12; r++) {
      for (let c = -12; c <= 12; c++) {
        const { x, y } = gridToPixel(r, c)
        gridGuide.rect(x, y, TILE_SIZE, TILE_SIZE)
        gridGuide.fill({ color: 0xffffff, alpha: 0.015 })
        
        // Subtle grid lines
        gridGuide.rect(x, y, TILE_SIZE, TILE_SIZE)
        gridGuide.stroke({ color: FLOOR_BORDER[floor], width: 0.3, alpha: 0.08 })
      }
    }
    world.addChild(gridGuide)

    // ── Placed rooms on this floor ──
    const floorRooms = state.board.filter((p) => p.floor === floor)
    for (const placed of floorRooms) {
      const roomDef = ROOM_MAP[placed.roomId]
      if (!roomDef) continue
      drawRoomTile(world, placed, roomDef, floor, onTileClickRef)
    }

    // ── Highlight open exits (ghostly glow for discoverable spots) ──
    if (state.phase === 'exploration' && state.pendingRoom) {
      const occupiedSet = new Set(
        floorRooms.map((p) => `${p.row},${p.col}`)
      )
      const openSpots = new Set<string>()

      for (const placed of floorRooms) {
        const roomDef = ROOM_MAP[placed.roomId]
        if (!roomDef) continue
        const rotatedDoors = rotateDoors(roomDef.doors, placed.rotation)
        for (const dir of rotatedDoors) {
          let nr = placed.row
          let nc = placed.col
          if (dir === 'north') nr--
          if (dir === 'south') nr++
          if (dir === 'east') nc++
          if (dir === 'west') nc--
          const key = `${nr},${nc}`
          if (!occupiedSet.has(key)) {
            openSpots.add(key)
          }
        }
      }

      for (const spot of openSpots) {
        const [r, c] = spot.split(',').map(Number)
        const { x, y } = gridToPixel(r!, c!)
        const highlight = new Graphics()

        // Ghostly glow effect
        highlight.roundRect(-4, -4, TILE_SIZE + 8, TILE_SIZE + 8, 8)
        highlight.fill({ color: FLOOR_ACCENT[floor], alpha: 0.05 })
        highlight.roundRect(0, 0, TILE_SIZE, TILE_SIZE, 4)
        highlight.fill({ color: FLOOR_ACCENT[floor], alpha: 0.08 })
        highlight.roundRect(0, 0, TILE_SIZE, TILE_SIZE, 4)
        highlight.stroke({ color: FLOOR_ACCENT[floor], width: 2, alpha: 0.5 })

        // "?" text
        const qText = new Text({
          text: '?',
          style: new TextStyle({
            fontFamily: '"Palatino Linotype", "Book Antiqua", Palatino, Georgia, serif',
            fontSize: 28,
            fontWeight: 'bold',
            fill: FLOOR_ACCENT[floor],
            stroke: { color: 0x000000, width: 3 },
          }),
        })
        qText.anchor.set(0.5)
        qText.x = TILE_SIZE / 2
        qText.y = TILE_SIZE / 2
        qText.alpha = 0.4
        highlight.addChild(qText)

        highlight.x = x
        highlight.y = y
        highlight.eventMode = 'static'
        highlight.cursor = 'pointer'
        const row = r!
        const col = c!
        highlight.on('pointerdown', (e: FederatedPointerEvent) => {
          if (e.button === 0 && !e.shiftKey) {
            onTileClickRef.current?.(row, col)
          }
        })
        world.addChild(highlight)
      }
    }

    // ── Player tokens ──
    const playersOnFloor = Object.values(state.players).filter(
      (p) => p.currentFloor === floor && p.alive
    )

    // Group players by cell
    const cellPlayers: Record<string, PlayerState[]> = {}
    for (const p of playersOnFloor) {
      const key = `${p.currentRow},${p.currentCol}`
      if (!cellPlayers[key]) cellPlayers[key] = []
      cellPlayers[key]!.push(p)
    }

    for (const [key, players] of Object.entries(cellPlayers)) {
      const [r, c] = key.split(',').map(Number)
      const { x: cx, y: cy } = gridToPixel(r!, c!)

      players.forEach((player, i) => {
        const charDef = player.characterId ? CHARACTER_MAP[player.characterId] : null
        const color = charDef?.color ?? 0x888888
        const isMe = player.peerId === myPeerId
        const isCurrentTurn = player.peerId === state.currentTurnPeerId
        const offsetAngle = (i * (2 * Math.PI)) / Math.max(players.length, 1)
        const spreadRadius = players.length > 1 ? 22 : 0
        const tx = cx + TILE_SIZE / 2 + Math.cos(offsetAngle) * spreadRadius
        const ty = cy + TILE_SIZE / 2 + 12 + Math.sin(offsetAngle) * spreadRadius

        const initials = charDef
          ? charDef.name.split(' ').map((w) => w[0]).join('').slice(0, 2)
          : '?'

        drawCharacterToken(world, tx, ty, color, initials, isMe, isCurrentTurn)
      })
    }

    // ── Current player movement indicator (gothic glow) ──
    if (state.currentTurnPeerId === myPeerId && state.phase === 'exploration') {
      const me = state.players[myPeerId!]
      if (me && me.currentFloor === floor && me.movesRemaining > 0) {
        const { x, y } = gridToPixel(me.currentRow, me.currentCol)
        const pulse = new Graphics()
        // Double border glow
        pulse.roundRect(x - 6, y - 6, TILE_SIZE + 12, TILE_SIZE + 12, 8)
        pulse.stroke({ color: 0x00ff88, width: 1, alpha: 0.3 })
        pulse.roundRect(x - 3, y - 3, TILE_SIZE + 6, TILE_SIZE + 6, 6)
        pulse.stroke({ color: 0x00ff88, width: 2, alpha: 0.6 })
        world.addChild(pulse)
      }
    }

    // ── Floor label (gothic style) ──
    const floorNames: Record<Floor, string> = {
      upper: 'UPPER FLOOR',
      ground: 'GROUND FLOOR',
      basement: 'BASEMENT',
    }
    const floorLabel = new Text({
      text: `☠ ${floorNames[floor]} ☠`,
      style: new TextStyle({
        fontFamily: '"Palatino Linotype", "Book Antiqua", Palatino, Georgia, serif',
        fontSize: 18,
        fontWeight: 'bold',
        fill: FLOOR_ACCENT[floor],
        stroke: { color: 0x000000, width: 4 },
        letterSpacing: 3,
      }),
    })
    floorLabel.x = 10
    floorLabel.y = 10
    world.addChild(floorLabel)
  }, [myPeerId])

  /* ── Re-draw on state change ── */
  useEffect(() => {
    gameStateRef.current = gameState
    draw()
  }, [gameState, draw])

  /* ── Keyboard controls for movement ── */
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const dirMap: Record<string, Direction> = {
        ArrowUp: 'north',
        ArrowDown: 'south',
        ArrowRight: 'east',
        ArrowLeft: 'west',
        w: 'north',
        s: 'south',
        d: 'east',
        a: 'west',
      }
      const dir = dirMap[e.key]
      if (dir) {
        e.preventDefault()
        onPlayerMoveRef.current?.(dir)
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  /* ── Center camera on player ── */
  useEffect(() => {
    if (!myPeerId || !gameState.players[myPeerId]) return
    const me = gameState.players[myPeerId]
    if (!me || me.currentFloor !== gameState.viewingFloor) return

    const div = containerRef.current
    if (!div) return
    const { x, y } = gridToPixel(me.currentRow, me.currentCol)
    const centerX = div.clientWidth / 2 - (x + TILE_SIZE / 2) * scaleRef.current
    const centerY = div.clientHeight / 2 - (y + TILE_SIZE / 2) * scaleRef.current
    panOffsetRef.current = { x: centerX, y: centerY }
    if (worldRef.current) {
      worldRef.current.x = centerX
      worldRef.current.y = centerY
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [gameState.phase, myPeerId])

  return (
    <div
      ref={containerRef}
      className="w-full h-full relative"
      style={{ minHeight: 400 }}
      onContextMenu={(e) => e.preventDefault()}
    />
  )
}
