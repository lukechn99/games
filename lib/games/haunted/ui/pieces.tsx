'use client'

/**
 * Game pieces drawn in SVG: room tiles, card symbols, pawns, monsters, dice.
 * Everything is code-drawn; no artwork is copied.
 */
import type { CardKind, PlacedTile, Region } from '../types'
import { TILE_BY_ID } from '../data/tiles'

export const T = 120 // tile size in board units

export const REGION_STYLE: Record<Region, { floor: string; grain: string; wall: string; label: string }> = {
  upper: { floor: '#3a3550', grain: '#463f60', wall: '#cfc6e8', label: 'Upper' },
  ground: { floor: '#4a3426', grain: '#583f2e', wall: '#e8d5bd', label: 'Ground' },
  basement: { floor: '#2f3a33', grain: '#38463d', wall: '#c4d6c9', label: 'Basement' },
}

export const INK = {
  event: '#7fd1c7',
  item: '#e9c46a',
  omen: '#e76f6f',
}

/** Card-type symbols: a spiral (event), a key (item), an eye (omen). */
export function Glyph({ kind, x, y, size = 22 }: { kind: CardKind; x: number; y: number; size?: number }) {
  const s = size / 24
  const color = INK[kind]
  return (
    <g transform={`translate(${x - size / 2} ${y - size / 2}) scale(${s})`} aria-hidden="true">
      <circle cx="12" cy="12" r="11.5" fill="#00000066" stroke={color} strokeWidth="1.2" />
      {kind === 'event' && (
        <path d="M12 12m0-1.5a1.5 1.5 0 1 1-1.5 1.5a3 3 0 0 1 3-3a4.5 4.5 0 0 1 4.5 4.5a6 6 0 0 1-6 6a7.5 7.5 0 0 1-7.5-7.5"
          fill="none" stroke={color} strokeWidth="1.6" strokeLinecap="round" />
      )}
      {kind === 'item' && (
        <g fill="none" stroke={color} strokeWidth="1.8" strokeLinecap="round">
          <circle cx="9" cy="9" r="3.2" />
          <path d="M11.3 11.3L18 18M15.5 15.5l2-2M17.5 17.5l1.5-1.5" />
        </g>
      )}
      {kind === 'omen' && (
        <g fill="none" stroke={color} strokeWidth="1.6">
          <path d="M4 12c2.5-4 5-5.5 8-5.5s5.5 1.5 8 5.5c-2.5 4-5 5.5-8 5.5S6.5 16 4 12z" />
          <circle cx="12" cy="12" r="2.4" fill={color} />
        </g>
      )}
    </g>
  )
}

function wallPath(doors: number, flipped: boolean) {
  // Each wall is drawn as two segments with a gap where a door is.
  const inset = 6
  const a = inset
  const b = T - inset
  const gapA = T / 2 - 16
  const gapB = T / 2 + 16
  const seg: string[] = []
  const side = (dir: number, x1: number, y1: number, x2: number, y2: number) => {
    const open = flipped || doors & (1 << dir)
    if (!open) {
      seg.push(`M${x1} ${y1}L${x2} ${y2}`)
      return
    }
    if (x1 === x2) {
      seg.push(`M${x1} ${y1}L${x1} ${gapA}M${x1} ${gapB}L${x2} ${y2}`)
    } else {
      seg.push(`M${x1} ${y1}L${gapA} ${y1}M${gapB} ${y1}L${x2} ${y2}`)
    }
  }
  side(0, a, a, b, a)
  side(1, b, a, b, b)
  side(2, a, b, b, b)
  side(3, a, a, a, b)
  return seg.join('')
}

export function TileArt({ tile, highlight }: { tile: PlacedTile; highlight?: 'move' | 'choose' | 'target' | null }) {
  const def = TILE_BY_ID.get(tile.tileId)!
  const style = REGION_STYLE[tile.region]
  const flooded = tile.flipped === 'flooded'
  const burning = tile.flipped === 'burning'
  const fire = tile.tokens.includes('fire')
  const floor = flooded ? '#1d3e5c' : burning ? '#5a1f12' : style.floor
  const grain = flooded ? '#25507a' : burning ? '#7a2c17' : style.grain
  const symbols = tile.flipped ? [] : def.symbols
  const name = tile.flipped ? (flooded ? 'Flooded' : 'Burning') : def.name
  const ring =
    highlight === 'move' ? '#9ae6b4' : highlight === 'choose' ? '#f6d860' : highlight === 'target' ? '#ff8a8a' : null
  return (
    <g>
      <rect x="2" y="2" width={T - 4} height={T - 4} rx="4" fill={floor} />
      {/* floorboards */}
      {!tile.flipped &&
        [1, 2, 3, 4, 5].map((i) => (
          <line key={i} x1="8" x2={T - 8} y1={i * (T / 6)} y2={i * (T / 6)} stroke={grain} strokeWidth="2" />
        ))}
      {flooded &&
        [0, 1, 2].map((i) => (
          <path key={i} d={`M12 ${36 + i * 26}q12 -8 24 0t24 0t24 0t24 0`} fill="none" stroke="#5fa8d3" strokeWidth="2" opacity="0.7" />
        ))}
      {(burning || fire) && (
        <g opacity={burning ? 1 : 0.85}>
          {[30, 60, 90].map((x, i) => (
            <path key={x} d={`M${x} ${T - 18}c-10 -12 -2 -22 0 -${30 + i * 6}c4 12 12 18 6 ${30 + i * 6}z`} fill={i === 1 ? '#f4a261' : '#e76f51'} />
          ))}
        </g>
      )}
      <path d={wallPath(tile.doors, !!tile.flipped)} stroke={style.wall} strokeWidth="5" strokeLinecap="round" fill="none" />
      <TileName name={name} />
      {symbols.map((k, i) => (
        <Glyph key={i} kind={k} x={T / 2 + (i - (symbols.length - 1) / 2) * 26} y={T - 24} />
      ))}
      {tile.tokens.includes('obstacle') && (
        <g transform={`translate(${T - 30} ${T - 32})`}>
          <rect width="20" height="14" rx="2" fill="#8d6e63" stroke="#3e2723" />
          <path d="M2 4h16M2 9h16" stroke="#3e2723" />
        </g>
      )}
      {tile.tokens.includes('altar') && (
        <g transform={`translate(${T / 2 - 14} ${T / 2 + 10})`}>
          <rect width="28" height="16" rx="2" fill="#f1e3c8" stroke="#9c7c4c" />
          <path d="M14 -6v8M10 -2h8" stroke="#f1e3c8" strokeWidth="2" />
        </g>
      )}
      {ring && <rect x="3" y="3" width={T - 6} height={T - 6} rx="5" fill="none" stroke={ring} strokeWidth="4" strokeDasharray="10 6" />}
    </g>
  )
}

/** Room name, wrapped onto two lines when it's long. */
function TileName({ name }: { name: string }) {
  const words = name.split(' ')
  let lines = [name]
  if (name.length > 13 && words.length > 1) {
    let best = 1
    let bestDiff = Infinity
    for (let i = 1; i < words.length; i++) {
      const diff = Math.abs(words.slice(0, i).join(' ').length - words.slice(i).join(' ').length)
      if (diff < bestDiff) {
        bestDiff = diff
        best = i
      }
    }
    lines = [words.slice(0, best).join(' '), words.slice(best).join(' ')]
  }
  const size = Math.max(...lines.map((l) => l.length)) > 13 ? 10.5 : 12
  return (
    <text x={T / 2} y={lines.length > 1 ? 21 : 26} textAnchor="middle" fontSize={size} fontWeight="700" fill="#f5efe6"
      style={{ fontFamily: 'var(--font-display)' }}>
      {lines.map((l, i) => (
        <tspan key={i} x={T / 2} dy={i === 0 ? 0 : 12}>{l}</tspan>
      ))}
    </text>
  )
}

export function Pawn({ color, label, x, y, dead, me }: { color: string; label: string; x: number; y: number; dead?: boolean; me?: boolean }) {
  return (
    <g transform={`translate(${x} ${y})`} opacity={dead ? 0.5 : 1}>
      {me && <circle r="17" fill="none" stroke="#fff" strokeWidth="2" strokeDasharray="3 3" />}
      <ellipse cx="0" cy="11" rx="12" ry="4" fill="#00000088" />
      <path d="M-9 10c0-9 3-12 9-12s9 3 9 12z" fill={color} stroke="#111" strokeWidth="1.5" />
      <circle cy="-7" r="7" fill={color} stroke="#111" strokeWidth="1.5" />
      <text y="9" textAnchor="middle" fontSize="9" fontWeight="800" fill="#111">{label}</text>
      {dead && <path d="M-8 -14l16 16M8 -14l-16 16" stroke="#111" strokeWidth="2.5" />}
    </g>
  )
}

export function MonsterToken({ kind, label, x, y, stunned, selected }: { kind: string; label: string; x: number; y: number; stunned?: boolean; selected?: boolean }) {
  const fill = kind === 'shark' ? '#2b6cb0' : kind === 'mannequin' ? '#d9c7b8' : '#c9b8e8'
  return (
    <g transform={`translate(${x} ${y})`} opacity={stunned ? 0.55 : 1}>
      {selected && <circle r="19" fill="none" stroke="#f6d860" strokeWidth="3" />}
      <path d="M0 -15L14 0L0 15L-14 0z" fill={fill} stroke="#5b0000" strokeWidth="2.5" />
      <text y="4" textAnchor="middle" fontSize="11" fontWeight="800" fill="#5b0000">{label}</text>
      {stunned && <text y="-18" textAnchor="middle" fontSize="10" fill="#fff">zz</text>}
    </g>
  )
}

/** A Betrayal-style die: blank, one pip or two pips. */
export function Die({ value, size = 28 }: { value: number; size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 28 28" aria-label={`${value}`}>
      <rect x="1" y="1" width="26" height="26" rx="6" fill="#f3ecdf" stroke="#2a2420" strokeWidth="2" />
      {value >= 1 && <circle cx={value === 2 ? 9 : 14} cy={value === 2 ? 9 : 14} r="3.5" fill="#2a2420" />}
      {value === 2 && <circle cx="19" cy="19" r="3.5" fill="#2a2420" />}
    </svg>
  )
}
