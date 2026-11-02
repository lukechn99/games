'use client'

import { Locate, Minus, Plus } from 'lucide-react'
import { useEffect, useMemo, useRef, useState, type PointerEvent as RPointerEvent } from 'react'
import { EXPLORER_BY_ID } from '../data/explorers'
import { TILE_BY_ID } from '../data/tiles'
import type { Dir, PlacedTile, Region } from '../types'
import { DX, DY } from '../types'
import type { HauntedView } from '../rules'
import { MonsterToken, Pawn, REGION_STYLE, T, TileArt } from './pieces'

export interface BoardProps {
  view: HauntedView
  region: Region
  /** Tiles to outline, and what tapping them does. */
  highlight: Record<string, 'move' | 'choose' | 'target'>
  /** Unexplored doorways from a tile that can be walked through. */
  explore: { from: string; dirs: Dir[] } | null
  selectedMonster: string | null
  onTile(uid: string): void
  onExplore(dir: Dir): void
  onMonster(id: string): void
  /** Tile to center on when the board first shows or the region changes. */
  focus: string | null
}

const PAD = T

export default function Board(p: BoardProps) {
  const tiles = useMemo(() => Object.values(p.view.tiles).filter((t) => t.region === p.region), [p.view.tiles, p.region])
  const bounds = useMemo(() => {
    const xs = tiles.map((t) => t.x)
    const ys = tiles.map((t) => t.y)
    return {
      minX: Math.min(0, ...xs) - 1,
      maxX: Math.max(0, ...xs) + 2,
      minY: Math.min(0, ...ys) - 1,
      maxY: Math.max(0, ...ys) + 2,
    }
  }, [tiles])

  const svgRef = useRef<SVGSVGElement>(null)
  const [cam, setCam] = useState({ x: 0, y: 0, zoom: 1 })
  const pointers = useRef(new Map<number, { x: number; y: number }>())
  const drag = useRef<{ moved: number; pinch?: number } | null>(null)

  // Center on the focused tile when the floor or focus changes.
  const focusTile = p.focus ? p.view.tiles[p.focus] : undefined
  const focusKey = `${p.region}:${p.focus ?? 'none'}`
  useEffect(() => {
    const t = focusTile?.region === p.region ? focusTile : tiles.find((x) => TILE_BY_ID.get(x.tileId)?.landing)
    // Camera follows the game state; this is an external sync, not derived render state.
     
    if (t) setCam((c) => ({ ...c, x: t.x * T + T / 2, y: t.y * T + T / 2 }))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [focusKey])

  const vw = 520 / cam.zoom
  const vh = 640 / cam.zoom
  const viewBox = `${cam.x - vw / 2} ${cam.y - vh / 2} ${vw} ${vh}`

  function toUnits(dx: number) {
    const el = svgRef.current
    if (!el) return dx
    const r = el.getBoundingClientRect()
    return dx * Math.max(vw / r.width, vh / r.height)
  }

  function onDown(e: RPointerEvent) {
    pointers.current.set(e.pointerId, { x: e.clientX, y: e.clientY })
    drag.current = { moved: 0 }
  }
  function onMove(e: RPointerEvent) {
    const prev = pointers.current.get(e.pointerId)
    if (!prev || !drag.current) return
    const cur = { x: e.clientX, y: e.clientY }
    pointers.current.set(e.pointerId, cur)
    if (pointers.current.size === 2) {
      const [a, b] = [...pointers.current.values()]
      const d = Math.hypot(a!.x - b!.x, a!.y - b!.y)
      if (drag.current.pinch) {
        const f = d / drag.current.pinch
        setCam((c) => ({ ...c, zoom: Math.min(2.5, Math.max(0.35, c.zoom * f)) }))
      }
      drag.current.pinch = d
      drag.current.moved += 10
      return
    }
    const dx = cur.x - prev.x
    const dy = cur.y - prev.y
    drag.current.moved += Math.abs(dx) + Math.abs(dy)
    if (drag.current.moved > 6) {
      if (e.currentTarget.hasPointerCapture?.(e.pointerId) === false) e.currentTarget.setPointerCapture?.(e.pointerId)
      setCam((c) => ({ ...c, x: c.x - toUnits(dx), y: c.y - toUnits(dy) }))
    }
  }
  function onUp(e: RPointerEvent) {
    pointers.current.delete(e.pointerId)
    if (pointers.current.size === 0) setTimeout(() => (drag.current = null), 0)
  }
  /** Ignore taps that were really drags. */
  const tap = (fn: () => void) => () => {
    if (drag.current && drag.current.moved > 6) return
    fn()
  }

  const zoomBy = (f: number) => setCam((c) => ({ ...c, zoom: Math.min(2.5, Math.max(0.35, c.zoom * f)) }))

  const occupants = useMemo(() => {
    const m = new Map<string, { kind: 'pawn' | 'monster'; id: string }[]>()
    for (const ex of Object.values(p.view.explorers)) {
      if (ex.removed) continue
      const list = m.get(ex.tile) ?? []
      list.push({ kind: 'pawn', id: ex.pid })
      m.set(ex.tile, list)
    }
    for (const mo of p.view.monsters) {
      const list = m.get(mo.tile) ?? []
      list.push({ kind: 'monster', id: mo.id })
      m.set(mo.tile, list)
    }
    return m
  }, [p.view.explorers, p.view.monsters])

  const exploreFrom = p.explore ? p.view.tiles[p.explore.from] : undefined
  const links = tiles.flatMap((t) => (TILE_BY_ID.get(t.tileId)?.leadsTo ?? []).filter((l) => !l.monstersOnly).map((l) => ({ t, to: l.tile })))

  return (
    <div className="relative h-full w-full touch-none select-none overflow-hidden" style={{ background: '#0f0c13' }}>
      <svg
        ref={svgRef}
        className="h-full w-full"
        viewBox={viewBox}
        preserveAspectRatio="xMidYMid meet"
        onPointerDown={onDown}
        onPointerMove={onMove}
        onPointerUp={onUp}
        onPointerCancel={onUp}
        onWheel={(e) => zoomBy(e.deltaY < 0 ? 1.1 : 0.9)}
        role="img"
        aria-label={`${REGION_STYLE[p.region].label} floor map`}
      >
        <defs>
          <pattern id="grid" width={T} height={T} patternUnits="userSpaceOnUse">
            <path d={`M${T} 0H0V${T}`} fill="none" stroke="#ffffff08" />
          </pattern>
        </defs>
        <rect
          x={bounds.minX * T - PAD}
          y={bounds.minY * T - PAD}
          width={(bounds.maxX - bounds.minX) * T + PAD * 2}
          height={(bounds.maxY - bounds.minY) * T + PAD * 2}
          fill="url(#grid)"
        />
        {tiles.map((t: PlacedTile) => {
          const h = p.highlight[t.uid] ?? null
          return (
            <g key={t.uid} transform={`translate(${t.x * T} ${t.y * T})`} onClick={tap(() => p.onTile(t.uid))}
              style={{ cursor: h ? 'pointer' : 'default' }}>
              <TileArt tile={t} highlight={h} />
            </g>
          )
        })}
        {links.map(({ t, to }) => (
          <text key={`${t.uid}-${to}`} x={t.x * T + T / 2} y={t.y * T + 48} textAnchor="middle" fontSize="9" fill="#d8cfee" opacity="0.85">
            ⇅ {TILE_BY_ID.get(to)?.name}
          </text>
        ))}
        {exploreFrom &&
          p.explore!.dirs.map((d) => {
            const x = (exploreFrom.x + DX[d]!) * T
            const y = (exploreFrom.y + DY[d]!) * T
            return (
              <g key={d} transform={`translate(${x} ${y})`} onClick={tap(() => p.onExplore(d))} style={{ cursor: 'pointer' }}>
                <rect x="8" y="8" width={T - 16} height={T - 16} rx="6" fill="#ffffff0d" stroke="#9ae6b4" strokeWidth="3" strokeDasharray="8 6" />
                <text x={T / 2} y={T / 2 - 2} textAnchor="middle" fontSize="28" fill="#9ae6b4">?</text>
                <text x={T / 2} y={T / 2 + 20} textAnchor="middle" fontSize="11" fill="#9ae6b4">Explore</text>
              </g>
            )
          })}
        {tiles.map((t) => {
          const occ = occupants.get(t.uid) ?? []
          return occ.map((o, i) => {
            const col = i % 3
            const row = Math.floor(i / 3)
            const x = t.x * T + 30 + col * 30
            const y = t.y * T + 58 + row * 28
            if (o.kind === 'pawn') {
              const ex = p.view.explorers[o.id]!
              const def = EXPLORER_BY_ID.get(ex.explorerId)!
              return (
                <Pawn key={o.id} x={x} y={y} color={def.color} label={def.name.replace(/^(Dr\.|Father) /, '')[0]!}
                  dead={ex.dead} me={o.id === p.view.me} />
              )
            }
            const m = p.view.monsters.find((mm) => mm.id === o.id)!
            return (
              <g key={o.id} onClick={tap(() => p.onMonster(m.id))} style={{ cursor: 'pointer' }}>
                <MonsterToken kind={m.kind} label={m.name.match(/\d+$/)?.[0] ?? m.name[4] ?? 'M'} x={x} y={y}
                  stunned={m.stunned} selected={p.selectedMonster === m.id} />
              </g>
            )
          })
        })}
      </svg>
      <div className="absolute right-3 top-3 flex flex-col gap-2">
        <button type="button" aria-label="Zoom in" onClick={() => zoomBy(1.25)} className="grid size-9 place-items-center rounded-full bg-black/60 text-white">
          <Plus className="size-4" />
        </button>
        <button type="button" aria-label="Zoom out" onClick={() => zoomBy(0.8)} className="grid size-9 place-items-center rounded-full bg-black/60 text-white">
          <Minus className="size-4" />
        </button>
        {focusTile && focusTile.region === p.region && (
          <button type="button" aria-label="Center on your explorer" onClick={() => setCam((c) => ({ ...c, x: focusTile.x * T + T / 2, y: focusTile.y * T + T / 2 }))}
            className="grid size-9 place-items-center rounded-full bg-black/60 text-white">
            <Locate className="size-4" />
          </button>
        )}
      </div>
    </div>
  )
}
