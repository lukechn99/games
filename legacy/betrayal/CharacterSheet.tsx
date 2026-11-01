'use client'

import type { TraitName, PlayerState } from './types'
import { CHARACTER_MAP } from './data/characters'
import { CARD_MAP } from './data/cards'

/* ------------------------------------------------------------------ */
/*  Trait colours & labels                                             */
/* ------------------------------------------------------------------ */

const TRAIT_CONFIG: Record<TraitName, { label: string; abbr: string; color: string; bgColor: string; icon: string }> = {
  speed:     { label: 'Speed',     abbr: 'SPD', color: '#22c55e', bgColor: 'rgba(34,197,94,0.12)', icon: '💨' },
  might:     { label: 'Might',     abbr: 'MGT', color: '#ef4444', bgColor: 'rgba(239,68,68,0.12)', icon: '💪' },
  sanity:    { label: 'Sanity',    abbr: 'SAN', color: '#3b82f6', bgColor: 'rgba(59,130,246,0.12)', icon: '🧠' },
  knowledge: { label: 'Knowledge', abbr: 'KNW', color: '#f59e0b', bgColor: 'rgba(245,158,11,0.12)', icon: '📖' },
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
  compact,
}: {
  trait: TraitName
  values: number[]
  currentIndex: number
  startIndex: number
  compact?: boolean
}) {
  const config = TRAIT_CONFIG[trait]
  const isCritical = currentIndex <= 1

  return (
    <div
      className="flex items-center gap-1.5"
      style={{
        background: isCritical ? 'rgba(255,0,0,0.08)' : config.bgColor,
        borderRadius: 8,
        padding: compact ? '4px 8px' : '6px 10px',
        border: isCritical ? '1px solid rgba(255,0,0,0.2)' : '1px solid transparent',
      }}
    >
      <span
        className="font-bold uppercase tracking-wider shrink-0"
        style={{ color: config.color, fontSize: compact ? 9 : 10, width: compact ? 28 : 72 }}
      >
        {compact ? config.abbr : config.label}
      </span>
      <div className="flex items-center gap-0.5 flex-1">
        {values.map((val, idx) => {
          const isCurrent = idx === currentIndex
          const isStart = idx === startIndex
          const isDead = idx === 0

          return (
            <div
              key={idx}
              className="relative flex items-center justify-center transition-all duration-200"
              style={{
                width: compact ? 22 : 28,
                height: compact ? 22 : 28,
                borderRadius: isCurrent ? 6 : 4,
                background: isCurrent
                  ? config.color
                  : isDead
                    ? 'rgba(255,0,0,0.2)'
                    : 'rgba(255,255,255,0.06)',
                border: isStart && !isCurrent
                  ? `2px solid ${config.color}80`
                  : isCurrent
                    ? '2px solid rgba(255,255,255,0.8)'
                    : '1px solid rgba(255,255,255,0.08)',
                transform: isCurrent ? 'scale(1.1)' : 'scale(1)',
                boxShadow: isCurrent ? `0 0 10px ${config.color}60` : 'none',
              }}
            >
              <span
                className="font-bold"
                style={{
                  fontSize: compact ? 9 : 11,
                  color: isCurrent ? '#fff' : isDead ? '#ff4444' : 'rgba(255,255,255,0.4)',
                }}
              >
                {isDead ? '\u2620' : val}
              </span>
              {isStart && !isCurrent && (
                <div
                  className="absolute -bottom-0.5 w-1 h-1 rounded-full"
                  style={{ background: config.color }}
                />
              )}
            </div>
          )
        })}
      </div>
      <span
        className="font-bold w-6 text-right tabular-nums"
        style={{ color: isCritical ? '#ff4444' : config.color, fontSize: compact ? 12 : 16 }}
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
        <p className="text-muted-foreground text-sm italic">No character selected</p>
      </div>
    )
  }

  const colorHex = `#${charDef.color.toString(16).padStart(6, '0')}`

  return (
    <div
      className="rounded-xl overflow-hidden transition-all"
      style={{
        background: 'rgba(0,0,0,0.5)',
        border: isCurrentPlayer
          ? `2px solid ${colorHex}`
          : '1px solid rgba(255,255,255,0.08)',
        boxShadow: isCurrentPlayer
          ? `0 0 20px ${colorHex}30, inset 0 0 20px ${colorHex}08`
          : 'none',
      }}
    >
      {/* Header */}
      <div
        className="flex items-center gap-3 px-3 py-2"
        style={{
          background: `linear-gradient(135deg, ${colorHex}20, transparent)`,
          borderBottom: `1px solid ${colorHex}15`,
        }}
      >
        {/* Token circle */}
        <div
          className="rounded-full flex items-center justify-center text-white font-bold shrink-0"
          style={{
            width: compact ? 28 : 34,
            height: compact ? 28 : 34,
            background: `radial-gradient(circle at 35% 35%, ${colorHex}, ${colorHex}88)`,
            border: '2px solid rgba(255,255,255,0.25)',
            boxShadow: `0 2px 8px ${colorHex}40`,
            fontSize: compact ? 10 : 12,
          }}
        >
          {charDef.name.split(' ').map((w) => w[0]).join('').slice(0, 2)}
        </div>

        <div className="flex-1 min-w-0">
          <div
            className="font-bold text-white truncate"
            style={{
              fontSize: compact ? 12 : 14,
              fontFamily: '"Palatino Linotype", "Book Antiqua", Palatino, Georgia, serif',
            }}
          >
            {charDef.name}
          </div>
          {!compact && (
            <div className="text-xs text-gray-400">
              Age {charDef.age} &middot; {charDef.colorName}
              {player.items.length > 0 && ` \u00B7 ${player.items.length} item${player.items.length !== 1 ? 's' : ''}`}
              {player.omens.length > 0 && ` \u00B7 ${player.omens.length} omen${player.omens.length !== 1 ? 's' : ''}`}
            </div>
          )}
        </div>

        {!player.alive && (
          <span className="text-red-500 font-bold text-xs px-2 py-0.5 rounded bg-red-950/50 border border-red-900/50">
            &#9760; DEAD
          </span>
        )}

        {player.movesRemaining > 0 && isCurrentPlayer && (
          <span
            className="text-xs font-mono px-2 py-0.5 rounded-lg font-bold"
            style={{ background: `${colorHex}20`, color: colorHex, border: `1px solid ${colorHex}30` }}
          >
            {player.movesRemaining} mv
          </span>
        )}
      </div>

      {/* Trait tracks */}
      <div className={compact ? 'p-2 space-y-0.5' : 'p-3 space-y-1'}>
        {TRAIT_ORDER.map((trait) => (
          <TraitTrack
            key={trait}
            trait={trait}
            values={[...charDef.traits[trait].values]}
            currentIndex={player.traitIndices[trait]}
            startIndex={charDef.traits[trait].startIndex}
            compact={compact}
          />
        ))}
      </div>

      {/* Items & Omens (non-compact only) */}
      {!compact && (player.items.length > 0 || player.omens.length > 0) && (
        <div className="px-3 pb-3 space-y-1.5">
          <div className="h-px bg-white/5" />
          {player.items.length > 0 && (
            <div className="flex flex-wrap gap-1">
              {player.items.map((cardId) => {
                const card = CARD_MAP[cardId]
                return (
                  <span
                    key={cardId}
                    className="px-2 py-0.5 rounded text-[10px] font-medium bg-blue-900/30 text-blue-300 border border-blue-800/30"
                    title={card?.effect}
                  >
                    🛡 {card?.name ?? cardId}
                  </span>
                )
              })}
            </div>
          )}
          {player.omens.length > 0 && (
            <div className="flex flex-wrap gap-1">
              {player.omens.map((cardId) => {
                const card = CARD_MAP[cardId]
                return (
                  <span
                    key={cardId}
                    className="px-2 py-0.5 rounded text-[10px] font-medium bg-purple-900/30 text-purple-300 border border-purple-800/30"
                    title={card?.effect}
                  >
                    🔮 {card?.name ?? cardId}
                  </span>
                )
              })}
            </div>
          )}
        </div>
      )}
    </div>
  )
}
