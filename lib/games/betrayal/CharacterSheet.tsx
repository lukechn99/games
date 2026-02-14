'use client'

import type { TraitName, PlayerState } from './types'
import { CHARACTER_MAP } from './data/characters'

/* ------------------------------------------------------------------ */
/*  Trait colours & labels                                             */
/* ------------------------------------------------------------------ */

const TRAIT_CONFIG: Record<TraitName, { label: string; color: string; bgColor: string }> = {
  speed:     { label: 'Speed',     color: '#22c55e', bgColor: 'rgba(34,197,94,0.15)' },
  might:     { label: 'Might',     color: '#ef4444', bgColor: 'rgba(239,68,68,0.15)' },
  sanity:    { label: 'Sanity',    color: '#3b82f6', bgColor: 'rgba(59,130,246,0.15)' },
  knowledge: { label: 'Knowledge', color: '#f59e0b', bgColor: 'rgba(245,158,11,0.15)' },
}

const TRAIT_ORDER: TraitName[] = ['speed', 'might', 'sanity', 'knowledge']

/* ------------------------------------------------------------------ */
/*  Single Trait Track                                                 */
/* ------------------------------------------------------------------ */

function TraitTrack({
  trait,
  values,
  currentIndex,
  startIndex,
}: {
  trait: TraitName
  values: number[]
  currentIndex: number
  startIndex: number
}) {
  const config = TRAIT_CONFIG[trait]

  return (
    <div className="flex items-center gap-2" style={{ background: config.bgColor, borderRadius: 8, padding: '6px 10px' }}>
      <span
        className="text-xs font-bold uppercase tracking-wider w-20 shrink-0"
        style={{ color: config.color }}
      >
        {config.label}
      </span>
      <div className="flex items-center gap-1 flex-1">
        {values.map((val, idx) => {
          const isCurrent = idx === currentIndex
          const isStart = idx === startIndex
          const isDead = idx === 0

          return (
            <div
              key={idx}
              className="relative flex items-center justify-center transition-all duration-200"
              style={{
                width: 28,
                height: 28,
                borderRadius: isCurrent ? 6 : 4,
                background: isCurrent
                  ? config.color
                  : isDead
                    ? 'rgba(255,0,0,0.2)'
                    : 'rgba(255,255,255,0.08)',
                border: isStart
                  ? `2px solid ${config.color}`
                  : isCurrent
                    ? '2px solid rgba(255,255,255,0.8)'
                    : '1px solid rgba(255,255,255,0.1)',
                transform: isCurrent ? 'scale(1.15)' : 'scale(1)',
                boxShadow: isCurrent ? `0 0 8px ${config.color}80` : 'none',
              }}
            >
              <span
                className="text-xs font-bold"
                style={{
                  color: isCurrent ? '#fff' : isDead ? '#ff4444' : 'rgba(255,255,255,0.5)',
                }}
              >
                {isDead ? '\u2620' : val}
              </span>
              {isStart && !isCurrent && (
                <div
                  className="absolute -bottom-1 w-1.5 h-1.5 rounded-full"
                  style={{ background: config.color }}
                />
              )}
            </div>
          )
        })}
      </div>
      <span
        className="text-lg font-bold w-8 text-right tabular-nums"
        style={{ color: config.color }}
      >
        {values[currentIndex]}
      </span>
    </div>
  )
}

/* ------------------------------------------------------------------ */
/*  Full Character Sheet                                               */
/* ------------------------------------------------------------------ */

interface CharacterSheetProps {
  player: PlayerState
  isCurrentPlayer?: boolean
  compact?: boolean
}

export default function CharacterSheet({
  player,
  isCurrentPlayer = false,
  compact = false,
}: CharacterSheetProps) {
  const charDef = player.characterId ? CHARACTER_MAP[player.characterId] : null

  if (!charDef) {
    return (
      <div className="p-3 rounded-lg bg-card border border-border">
        <p className="text-muted-foreground text-sm">No character selected</p>
      </div>
    )
  }

  const colorHex = `#${charDef.color.toString(16).padStart(6, '0')}`

  return (
    <div
      className="rounded-lg overflow-hidden transition-all"
      style={{
        background: 'rgba(0,0,0,0.6)',
        border: isCurrentPlayer
          ? `2px solid ${colorHex}`
          : '1px solid rgba(255,255,255,0.1)',
        boxShadow: isCurrentPlayer
          ? `0 0 16px ${colorHex}40`
          : 'none',
      }}
    >
      {/* Header */}
      <div
        className="flex items-center gap-3 px-3 py-2"
        style={{ background: `${colorHex}25` }}
      >
        {/* Token circle */}
        <div
          className="w-8 h-8 rounded-full flex items-center justify-center text-white font-bold text-xs shrink-0"
          style={{
            background: colorHex,
            border: '2px solid rgba(255,255,255,0.3)',
          }}
        >
          {charDef.name.split(' ').map((w) => w[0]).join('').slice(0, 2)}
        </div>

        <div className="flex-1 min-w-0">
          <div className="text-sm font-bold text-white truncate">{charDef.name}</div>
          {!compact && (
            <div className="text-xs text-muted-foreground">
              Age {charDef.age} &middot; {charDef.colorName}
              {player.items.length > 0 && ` \u00B7 ${player.items.length} items`}
              {player.omens.length > 0 && ` \u00B7 ${player.omens.length} omens`}
            </div>
          )}
        </div>

        {!player.alive && (
          <span className="text-red-500 font-bold text-xs">DEAD</span>
        )}

        {player.movesRemaining > 0 && isCurrentPlayer && (
          <span
            className="text-xs font-mono px-2 py-0.5 rounded"
            style={{ background: `${colorHex}30`, color: colorHex }}
          >
            {player.movesRemaining} moves
          </span>
        )}
      </div>

      {/* Trait tracks */}
      <div className={compact ? 'p-2 space-y-1' : 'p-3 space-y-1.5'}>
        {TRAIT_ORDER.map((trait) => (
          <TraitTrack
            key={trait}
            trait={trait}
            values={[...charDef.traits[trait].values]}
            currentIndex={player.traitIndices[trait]}
            startIndex={charDef.traits[trait].startIndex}
          />
        ))}
      </div>
    </div>
  )
}
