/**
 * House geometry: placing tiles, doors, movement links, line of sight.
 * Each region (upper / ground / basement) is its own grid.
 */
import { TILE_BY_ID } from '../data/tiles'
import type { Dir, HauntedState, PlacedTile, Region, TileDef } from '../types'
import { DIRS, DX, DY, opposite } from '../types'

export function rotateDoors(doors: number, rot: number): number {
  let d = doors & 15
  for (let i = 0; i < rot; i++) d = ((d << 1) | (d >> 3)) & 15
  return d
}

export const hasDoor = (t: PlacedTile, d: Dir) => t.flipped ? true : !!(t.doors & (1 << d))

export function def(t: PlacedTile): TileDef {
  return TILE_BY_ID.get(t.tileId)!
}

export function tileAt(s: HauntedState, region: Region, x: number, y: number): PlacedTile | undefined {
  for (const t of Object.values(s.tiles)) if (t.region === region && t.x === x && t.y === y) return t
  return undefined
}

export function placedByTileId(s: HauntedState, tileId: string): PlacedTile | undefined {
  return Object.values(s.tiles).find((t) => t.tileId === tileId)
}

export function isLanding(t: PlacedTile) {
  return !!def(t).landing
}

/** Symbols currently active on a tile (flipped tiles have none). */
export function symbols(t: PlacedTile) {
  return t.flipped ? [] : def(t).symbols
}

export function place(s: HauntedState, tileId: string, region: Region, x: number, y: number, rot: number): PlacedTile {
  const d = TILE_BY_ID.get(tileId)!
  const uid = `t${++s.seq}`
  const t: PlacedTile = { uid, tileId, region, x, y, rot: (rot & 3) as 0 | 1 | 2 | 3, doors: rotateDoors(d.doors, rot), tokens: [] }
  s.tiles[uid] = t
  return t
}

/** Rotations (0-3) of `tileId` that put a door facing `towards`. */
export function validRotations(s: HauntedState, tileId: string, region: Region, x: number, y: number, towards: Dir): number[] {
  const d = TILE_BY_ID.get(tileId)!
  const out: number[] = []
  for (let r = 0; r < 4; r++) {
    const doors = rotateDoors(d.doors, r)
    if (!(doors & (1 << towards))) continue
    if (!leavesOpenDoor(s, region, x, y, doors)) continue
    out.push(r)
  }
  return out
}

/**
 * The house must always keep at least one unexplored doorway on each
 * region. Would placing a tile with these doors at (x, y) keep one open?
 */
function leavesOpenDoor(s: HauntedState, region: Region, x: number, y: number, doors: number): boolean {
  for (const d of DIRS) {
    if (doors & (1 << d) && !tileAt(s, region, x + DX[d]!, y + DY[d]!)) return true
  }
  for (const t of Object.values(s.tiles)) {
    if (t.region !== region) continue
    for (const d of DIRS) {
      if (!hasDoor(t, d)) continue
      const nx = t.x + DX[d]!
      const ny = t.y + DY[d]!
      if (nx === x && ny === y) continue
      if (!tileAt(s, region, nx, ny)) return true
    }
  }
  return false
}

/** Open doorways (door with nothing behind it) in a region. */
export function openDoorways(s: HauntedState, region: Region): { from: PlacedTile; dir: Dir; x: number; y: number }[] {
  const out: { from: PlacedTile; dir: Dir; x: number; y: number }[] = []
  for (const t of Object.values(s.tiles)) {
    if (t.region !== region) continue
    for (const d of DIRS) {
      if (!hasDoor(t, d)) continue
      const x = t.x + DX[d]!
      const y = t.y + DY[d]!
      if (!tileAt(s, region, x, y)) out.push({ from: t, dir: d, x, y })
    }
  }
  return out
}

/** Tiles you can step to in one move from `t` (doors on both sides, plus "leads to" links). */
export function neighbors(s: HauntedState, t: PlacedTile, opts: { monster?: boolean } = {}): PlacedTile[] {
  const out: PlacedTile[] = []
  for (const d of DIRS) {
    if (!hasDoor(t, d)) continue
    const n = tileAt(s, t.region, t.x + DX[d]!, t.y + DY[d]!)
    if (n && hasDoor(n, opposite(d))) out.push(n)
  }
  for (const link of def(t).leadsTo ?? []) {
    if (link.monstersOnly && !opts.monster) continue
    if (t.flipped && !def(t).landing) continue
    const n = placedByTileId(s, link.tile)
    if (n && !out.includes(n)) out.push(n)
  }
  // Two-way links declared on the other tile.
  for (const other of Object.values(s.tiles)) {
    for (const link of def(other).leadsTo ?? []) {
      if (link.tile !== t.tileId || link.oneWay) continue
      if (link.monstersOnly && !opts.monster) continue
      if (!out.includes(other)) out.push(other)
    }
  }
  return out
}

/** Placed tiles that share an edge with `t` on its grid (doors or not). */
export function gridAdjacent(s: HauntedState, t: PlacedTile): PlacedTile[] {
  const out: PlacedTile[] = []
  for (const d of DIRS) {
    const n = tileAt(s, t.region, t.x + DX[d]!, t.y + DY[d]!)
    if (n) out.push(n)
  }
  return out
}

/** Shortest number of moves between tiles (ignoring costs), or Infinity. */
export function distances(s: HauntedState, from: PlacedTile, opts: { monster?: boolean } = {}): Map<string, number> {
  const dist = new Map<string, number>([[from.uid, 0]])
  const queue = [from]
  while (queue.length) {
    const cur = queue.shift()!
    for (const n of neighbors(s, cur, opts)) {
      if (!dist.has(n.uid)) {
        dist.set(n.uid, dist.get(cur.uid)! + 1)
        queue.push(n)
      }
    }
  }
  return dist
}

/**
 * Line of sight: tiles reachable in a straight line through connected
 * doorways without changing direction or region.
 */
export function inSight(s: HauntedState, a: PlacedTile, b: PlacedTile): boolean {
  if (a.uid === b.uid) return true
  if (a.region !== b.region) return false
  for (const d of DIRS) {
    let cur = a
    for (;;) {
      if (!hasDoor(cur, d)) break
      const n = tileAt(s, cur.region, cur.x + DX[d]!, cur.y + DY[d]!)
      if (!n || !hasDoor(n, opposite(d))) break
      if (n.uid === b.uid) return true
      cur = n
    }
  }
  return false
}

export function dirBetween(a: PlacedTile, b: PlacedTile): Dir | null {
  if (a.region !== b.region) return null
  for (const d of DIRS) if (a.x + DX[d]! === b.x && a.y + DY[d]! === b.y) return d
  return null
}
