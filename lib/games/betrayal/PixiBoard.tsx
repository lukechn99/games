'use client'

import { useRef, useEffect, useCallback } from 'react'
import { Application, Container, Graphics, Text, TextStyle, FederatedPointerEvent } from 'pixi.js'
import type { Floor, PlayerState, Direction, BetrayalGameState } from './types'
import { ROOM_MAP } from './data/rooms'
import { CHARACTER_MAP } from './data/characters'

/* ------------------------------------------------------------------ */
/*  Constants                                                          */
/* ------------------------------------------------------------------ */

const TILE_SIZE = 120
const TILE_GAP = 4
const CELL = TILE_SIZE + TILE_GAP
const GRID_OFFSET_X = 800
const GRID_OFFSET_Y = 600

const FLOOR_BG: Record<Floor, number> = {
  ground: 0x2d2d2d,
  upper: 0x1e3a5f,
  basement: 0x3e1e1e,
}

const FLOOR_TILE_BG: Record<Floor, number> = {
  ground: 0x4a6741,
  upper: 0x3a5a8a,
  basement: 0x6a4040,
}

const CARD_TYPE_COLORS = {
  event: 0xf5c542,
  item: 0x42adf5,
  omen: 0xc842f5,
} as const

const DOOR_OFFSETS: Record<Direction, { x: number; y: number; w: number; h: number }> = {
  north: { x: TILE_SIZE / 2 - 12, y: -2,               w: 24, h: 6 },
  south: { x: TILE_SIZE / 2 - 12, y: TILE_SIZE - 4,    w: 24, h: 6 },
  east:  { x: TILE_SIZE - 4,      y: TILE_SIZE / 2 - 12, w: 6, h: 24 },
  west:  { x: -2,                 y: TILE_SIZE / 2 - 12, w: 6, h: 24 },
}

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

    // ── Grid guide lines ──
    const gridGuide = new Graphics()
    for (let r = -10; r <= 10; r++) {
      for (let c = -10; c <= 10; c++) {
        const { x, y } = gridToPixel(r, c)
        gridGuide.rect(x, y, TILE_SIZE, TILE_SIZE)
        gridGuide.fill({ color: 0xffffff, alpha: 0.03 })
        gridGuide.stroke({ color: 0xffffff, width: 0.5, alpha: 0.06 })
      }
    }
    world.addChild(gridGuide)

    // ── Placed rooms on this floor ──
    const floorRooms = state.board.filter((p) => p.floor === floor)
    for (const placed of floorRooms) {
      const roomDef = ROOM_MAP[placed.roomId]
      if (!roomDef) continue

      const tileContainer = new Container()
      const { x, y } = gridToPixel(placed.row, placed.col)
      tileContainer.x = x
      tileContainer.y = y

      // Background
      const bg = new Graphics()
      bg.roundRect(0, 0, TILE_SIZE, TILE_SIZE, 6)
      bg.fill(FLOOR_TILE_BG[floor])
      bg.stroke({ color: 0xffffff, width: 1.5, alpha: 0.5 })
      tileContainer.addChild(bg)

      // Doors
      const rotatedDoors = rotateDoors(roomDef.doors, placed.rotation)
      const doorGfx = new Graphics()
      for (const dir of rotatedDoors) {
        const off = DOOR_OFFSETS[dir]
        doorGfx.roundRect(off.x, off.y, off.w, off.h, 2)
        doorGfx.fill(0xd4a574)
      }
      tileContainer.addChild(doorGfx)

      // Room name
      const nameText = new Text({
        text: roomDef.name,
        style: new TextStyle({
          fontFamily: 'Arial, sans-serif',
          fontSize: 11,
          fontWeight: 'bold',
          fill: 0xffffff,
          align: 'center',
          wordWrap: true,
          wordWrapWidth: TILE_SIZE - 16,
        }),
      })
      nameText.anchor.set(0.5, 0)
      nameText.x = TILE_SIZE / 2
      nameText.y = 8
      tileContainer.addChild(nameText)

      // Card type indicator
      if (roomDef.cardDraw) {
        const indicator = new Graphics()
        indicator.circle(TILE_SIZE - 16, TILE_SIZE - 16, 8)
        indicator.fill(CARD_TYPE_COLORS[roomDef.cardDraw])
        tileContainer.addChild(indicator)

        const typeInitial = roomDef.cardDraw[0]!.toUpperCase()
        const typeText = new Text({
          text: typeInitial,
          style: new TextStyle({
            fontFamily: 'Arial, sans-serif',
            fontSize: 9,
            fontWeight: 'bold',
            fill: 0x000000,
          }),
        })
        typeText.anchor.set(0.5)
        typeText.x = TILE_SIZE - 16
        typeText.y = TILE_SIZE - 16
        tileContainer.addChild(typeText)
      }

      // Special indicators
      if (roomDef.isStarting) {
        const starGfx = new Graphics()
        starGfx.circle(16, TILE_SIZE - 16, 6)
        starGfx.fill({ color: 0xffd700, alpha: 0.8 })
        tileContainer.addChild(starGfx)
      }

      // Click handler
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

    // ── Highlight open exits (places where a new tile could be placed) ──
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
        highlight.roundRect(0, 0, TILE_SIZE, TILE_SIZE, 6)
        highlight.fill({ color: 0x00ff88, alpha: 0.12 })
        highlight.stroke({ color: 0x00ff88, width: 2, alpha: 0.6 })
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
        const tokenRadius = 14
        const offsetAngle = (i * (2 * Math.PI)) / Math.max(players.length, 1)
        const spreadRadius = players.length > 1 ? 20 : 0
        const tx = cx + TILE_SIZE / 2 + Math.cos(offsetAngle) * spreadRadius
        const ty = cy + TILE_SIZE / 2 + 10 + Math.sin(offsetAngle) * spreadRadius

        const token = new Graphics()
        // Shadow
        token.circle(tx + 1, ty + 1, tokenRadius)
        token.fill({ color: 0x000000, alpha: 0.3 })
        // Main circle
        token.circle(tx, ty, tokenRadius)
        token.fill(color)
        token.stroke({ color: isMe ? 0xffffff : 0x000000, width: isMe ? 3 : 1.5 })
        world.addChild(token)

        // Initials
        const initials = charDef
          ? charDef.name.split(' ').map((w) => w[0]).join('').slice(0, 2)
          : '?'
        const initialText = new Text({
          text: initials,
          style: new TextStyle({
            fontFamily: 'Arial, sans-serif',
            fontSize: 11,
            fontWeight: 'bold',
            fill: 0xffffff,
            stroke: { color: 0x000000, width: 2 },
          }),
        })
        initialText.anchor.set(0.5)
        initialText.x = tx
        initialText.y = ty
        world.addChild(initialText)
      })
    }

    // ── Current player movement indicator ──
    if (state.currentTurnPeerId === myPeerId && state.phase === 'exploration') {
      const me = state.players[myPeerId!]
      if (me && me.currentFloor === floor && me.movesRemaining > 0) {
        const { x, y } = gridToPixel(me.currentRow, me.currentCol)
        const pulse = new Graphics()
        pulse.roundRect(
          x - 4,
          y - 4,
          TILE_SIZE + 8,
          TILE_SIZE + 8,
          8
        )
        pulse.stroke({ color: 0x00ff88, width: 2, alpha: 0.7 })
        world.addChild(pulse)
      }
    }

    // ── Floor label ──
    const floorLabel = new Text({
      text: floor.toUpperCase() + ' FLOOR',
      style: new TextStyle({
        fontFamily: 'Arial, sans-serif',
        fontSize: 16,
        fontWeight: 'bold',
        fill: 0xffffff,
        stroke: { color: 0x000000, width: 3 },
        letterSpacing: 2,
      }),
    })
    floorLabel.x = 10
    floorLabel.y = 10
    // Add to stage directly so it doesn't pan
    // Actually add to world for simplicity
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
