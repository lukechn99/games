'use client'

import { useState } from 'react'

/* ------------------------------------------------------------------ */
/*  Game Instructions Modal                                            */
/* ------------------------------------------------------------------ */

const SECTIONS = [
  {
    id: 'overview',
    title: 'Overview',
    content: `**Betrayal at House on the Hill** plays out like a horror movie. You begin by cooperatively exploring a haunted house, placing tiles to build it as you go.

**Object of the Game:**
• Before the haunt: Explore the house and strengthen your explorer.
• After the haunt: Be the first to meet your side's victory conditions — as a hero, or as the traitor.

The game unfolds in two parts. First, all players explore cooperatively. Then, when the haunt is triggered, one player may become the traitor and the teams race to complete secret goals.`,
  },
  {
    id: 'turn',
    title: 'On Your Turn',
    content: `Before the haunt, on your turn you may:

**1. Move** — Your Speed trait = max tiles you can move. Move through connected doorways to adjacent tiles.

**2. Discover Rooms** — Move through an unexplored doorway to discover a new room. Draw a tile, place it, then draw any Event/Item/Omen card shown on it. **Discovering a room ends your turn.**

**3. Trade** — Once per turn, if on the same tile as another explorer, you may freely exchange Items and Omens (with their permission). You can't trade an item you've already used this turn.

**4. Use Special Actions** — Many Items and Omens have special actions (marked ★). Each can be used once per turn.

You may do these in any order. You don't have to use all your movement or take all available actions. Your turn also ends voluntarily whenever you choose.`,
  },
  {
    id: 'movement',
    title: 'Movement & Rooms',
    content: `**Movement:** Check your Speed trait at the start of your turn. That's your maximum movement for the turn. If Speed changes mid-turn, your movement doesn't change.

**Adjacency:** Tiles are adjacent if they share a directly connected doorway. If two tiles touch but only one shows a doorway, they are NOT adjacent — that's a "false feature" (closet/alcove).

**Obstacles:** Some tiles have barriers that cost 2 moves to leave instead of 1. After the haunt, opposing characters also act as obstacles.

**Discovering Rooms:** When you move through an unexplored doorway:
1. Draw from the tile stack (skip tiles that don't match your floor).
2. Place it so at least one doorway connects to where you came from.
3. Move your explorer onto the new tile.
4. Resolve any tile text, then draw a matching card if the tile shows an Event, Item, or Omen symbol.
5. **Your turn ends.**`,
  },
  {
    id: 'cards',
    title: 'Cards',
    content: `**Event Cards** (yellow ⚡) — Spooky things that happen in the house. Read the text aloud and follow instructions. Events often require trait rolls. After resolving, bury the card (bottom of deck).

**Item Cards** (blue 🛡) — Useful objects you find. Read aloud, then keep the card face-up in front of you. Items provide special abilities to help you survive.

**Omen Cards** (purple 🔮) — Eerie harbingers of evil. Read aloud, keep the card. **Whenever you draw an Omen, you must make a haunt roll.**`,
  },
  {
    id: 'traits',
    title: 'Traits & Damage',
    content: `Each explorer has four traits: **Speed**, **Might**, **Sanity**, and **Knowledge**.

**Gaining/Losing Traits:** Move the clip up or down on the track as instructed. A trait at its highest value can't go higher.

**Healing:** Return the trait to its starting (green) value. If already at or above starting value, it stays.

**Critical:** A trait at its lowest value (near the skull) is critical.

**Damage Types:**
• **Physical** damage → lose Might and/or Speed
• **Mental** damage → lose Knowledge and/or Sanity
• **General** damage → you choose which traits are affected

Damage is measured in *spaces* moved on the track, not the numerical values. You can divide damage however you like within the associated traits.

**Before the haunt:** You cannot die. If damage would drop a trait below critical, it stays at critical. You can't assign damage to a critical trait if another associated trait is still available.

**After the haunt:** If any trait reaches the skull symbol (☠), that explorer dies.`,
  },
  {
    id: 'dice',
    title: 'Dice & Rolls',
    content: `Betrayal dice have faces with 0, 1, or 2 dots. After rolling, add up all the dots for your result.

**Trait Rolls:** Roll dice equal to your current value in that trait.

**Attack Rolls:** Both attacker and defender roll the same trait (usually Might). Whoever rolls lower takes damage equal to the difference.

**Haunt Rolls:** Roll dice equal to the total number of Omens discovered by ALL players. If the result is **5 or higher**, the haunt begins! If the last Omen card is drawn, the haunt starts automatically.

**Other Rolls:** Sometimes you're told to roll a fixed number of dice — this is not a trait roll.`,
  },
  {
    id: 'haunt',
    title: 'The Haunt',
    content: `When the haunt begins, the player who made the haunt roll is the "haunt revealer" — typically they become the traitor.

**Types of Haunts:**
• **No Traitor** — All players work together.
• **One Traitor** — One player vs. everyone else.
• **Hidden Traitor** — Traitor identity is secret; players may attack each other.
• **Free-for-All** — Every explorer for themselves!

**After the haunt starts:**
• You can now attack monsters and opposing explorers on your tile (once per turn).
• **Attacking:** Both sides roll Might (or another trait if a weapon says so). Higher roll wins; loser takes damage = difference.
• Traitors and monsters act as obstacles (cost 2 moves to leave their tile).
• The traitor may ignore damaging tile effects (but must still roll for elevators, etc.)
• Dead explorers leave corpses — you can loot one Item/Omen per turn from a corpse on your tile.

**Winning:** The first team to complete their haunt objectives wins!`,
  },
  {
    id: 'floors',
    title: 'The House',
    content: `The house has three floors:

**Upper Floor** — Blue-tinted rooms above. Connected to the Ground Floor via the Grand Staircase / Upper Landing.

**Ground Floor** — Where you begin (Entrance Hall). The main floor with the most room variety.

**Basement** — Dark red-tinted rooms below. Connected to the Ground Floor via the Grand Staircase / Basement Landing.

**Starting Tiles:** The Entrance Hall, Foyer, and Grand Staircase are pre-placed on the Ground Floor. The Upper Landing and Basement Landing start on their respective floors. All explorers begin in the Entrance Hall.

Some special rooms connect floors: the Coal Chute slides you to the basement; the Mystic Elevator can take you to any floor (roll to determine which).`,
  },
] as const

export default function GameInstructions({
  isOpen,
  onClose,
}: {
  isOpen: boolean
  onClose: () => void
}) {
  const [activeSection, setActiveSection] = useState('overview')

  if (!isOpen) return null

  const section = SECTIONS.find((s) => s.id === activeSection) ?? SECTIONS[0]

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-sm">
      <div className="max-w-3xl w-full max-h-[85vh] mx-4 rounded-2xl overflow-hidden shadow-2xl border border-amber-900/50 bg-gray-950 flex flex-col">
        {/* Header */}
        <div className="px-6 py-4 bg-gradient-to-r from-amber-900/40 to-red-900/30 border-b border-amber-800/30 flex items-center justify-between shrink-0">
          <div>
            <h2 className="text-xl font-bold text-amber-200 tracking-wide">
              How to Play
            </h2>
            <p className="text-xs text-amber-400/60 mt-0.5">
              Betrayal at House on the Hill &mdash; 3rd Edition Rules
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="w-9 h-9 rounded-lg bg-white/5 hover:bg-white/10 text-white/60 hover:text-white flex items-center justify-center transition-colors text-lg"
          >
            &times;
          </button>
        </div>

        <div className="flex flex-1 min-h-0">
          {/* Sidebar */}
          <nav className="w-48 shrink-0 border-r border-white/5 overflow-y-auto py-2 bg-black/30">
            {SECTIONS.map((s) => (
              <button
                key={s.id}
                type="button"
                onClick={() => setActiveSection(s.id)}
                className={`
                  w-full text-left px-4 py-2.5 text-sm transition-all
                  ${activeSection === s.id
                    ? 'bg-amber-900/30 text-amber-200 font-semibold border-l-2 border-amber-500'
                    : 'text-gray-400 hover:text-gray-200 hover:bg-white/5 border-l-2 border-transparent'
                  }
                `}
              >
                {s.title}
              </button>
            ))}
          </nav>

          {/* Content */}
          <div className="flex-1 overflow-y-auto p-6">
            <h3 className="text-lg font-bold text-white mb-4">{section.title}</h3>
            <div className="prose prose-invert prose-sm max-w-none">
              {section.content.split('\n\n').map((paragraph, i) => (
                <div key={i} className="mb-3">
                  {paragraph.split('\n').map((line, j) => {
                    // Render bold text
                    const parts = line.split(/(\*\*[^*]+\*\*)/)
                    return (
                      <p key={j} className="text-sm text-gray-300 leading-relaxed mb-1">
                        {parts.map((part, k) => {
                          if (part.startsWith('**') && part.endsWith('**')) {
                            return (
                              <strong key={k} className="text-amber-200 font-semibold">
                                {part.slice(2, -2)}
                              </strong>
                            )
                          }
                          return <span key={k}>{part}</span>
                        })}
                      </p>
                    )
                  })}
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* Footer */}
        <div className="px-6 py-3 bg-black/30 border-t border-white/5 text-center shrink-0">
          <button
            type="button"
            onClick={onClose}
            className="px-6 py-2 rounded-lg bg-amber-700 hover:bg-amber-600 text-white text-sm font-bold uppercase tracking-wider transition-colors"
          >
            Close Rules
          </button>
        </div>
      </div>
    </div>
  )
}

/* ------------------------------------------------------------------ */
/*  Quick Reference (inline, for the sidebar)                          */
/* ------------------------------------------------------------------ */

export function TurnActions({
  isMyTurn,
  movesRemaining,
  hasPendingRoom,
  phase,
}: {
  isMyTurn: boolean
  movesRemaining: number
  hasPendingRoom: boolean
  phase: string
}) {
  if (!isMyTurn) {
    return (
      <div className="p-3 rounded-lg bg-black/30 border border-white/5">
        <p className="text-xs text-gray-500 text-center italic">
          Waiting for the current player&apos;s turn...
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-2">
      <h4 className="text-xs text-amber-400/80 uppercase tracking-wider font-bold flex items-center gap-1.5">
        <span className="w-2 h-2 rounded-full bg-green-400 animate-pulse" />
        Your Turn — Available Actions
      </h4>
      <div className="space-y-1.5">
        {/* Move */}
        <div className={`flex items-start gap-2 p-2 rounded-lg text-xs ${
          movesRemaining > 0 ? 'bg-green-900/20 border border-green-800/30' : 'bg-gray-800/30 border border-gray-700/20 opacity-50'
        }`}>
          <span className="text-base leading-none mt-0.5">🚶</span>
          <div>
            <span className="font-semibold text-white">Move</span>
            <span className="text-gray-400 ml-1">
              {movesRemaining > 0
                ? `— ${movesRemaining} move${movesRemaining !== 1 ? 's' : ''} remaining`
                : '— No moves left'}
            </span>
            <p className="text-gray-500 mt-0.5">Use arrow keys / WASD or click direction buttons</p>
          </div>
        </div>

        {/* Place room */}
        {hasPendingRoom && (
          <div className="flex items-start gap-2 p-2 rounded-lg text-xs bg-emerald-900/20 border border-emerald-800/30 animate-pulse">
            <span className="text-base leading-none mt-0.5">🏠</span>
            <div>
              <span className="font-semibold text-emerald-200">Place Room</span>
              <span className="text-emerald-400/70 ml-1">— Click a highlighted cell on the board</span>
              <p className="text-emerald-500/60 mt-0.5">Placing a room will end your turn</p>
            </div>
          </div>
        )}

        {/* End Turn */}
        <div className="flex items-start gap-2 p-2 rounded-lg text-xs bg-amber-900/15 border border-amber-800/20">
          <span className="text-base leading-none mt-0.5">⏭</span>
          <div>
            <span className="font-semibold text-amber-200">End Turn</span>
            <span className="text-gray-400 ml-1">— Pass to the next explorer</span>
            <p className="text-gray-500 mt-0.5">You don&apos;t have to use all your moves</p>
          </div>
        </div>

        {/* Attack (only during haunt) */}
        {phase === 'haunt' && (
          <div className="flex items-start gap-2 p-2 rounded-lg text-xs bg-red-900/15 border border-red-800/20">
            <span className="text-base leading-none mt-0.5">⚔️</span>
            <div>
              <span className="font-semibold text-red-300">Attack</span>
              <span className="text-gray-400 ml-1">— Target on your tile (once per turn)</span>
              <p className="text-gray-500 mt-0.5">Both roll Might; loser takes the difference as damage</p>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
