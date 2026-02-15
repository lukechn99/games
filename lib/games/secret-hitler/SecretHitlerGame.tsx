'use client'

import {
  useEffect,
  useCallback,
  useRef,
  useMemo,
} from 'react'
import { useConnections } from '@/lib/connections-provider'
import { useGame } from '@/lib/game-context'
import type {
  SecretHitlerGameState,
  PlayerState,
  PolicyCard,
  ExecutiveAction,
  GamePhase,
} from './types'
import {
  shuffle,
  createPolicyDeck,
  getRoleDistribution,
  getExecutiveActions,
  reshuffleDeckIfNeeded,
  getActionLabel,
  getActionDescription,
} from './types'

/* ================================================================== */
/*  STYLE CONSTANTS — Art Deco / 1930s Propaganda aesthetic            */
/* ================================================================== */

const LIBERAL_COLOR = '#1976D2'
const LIBERAL_BG = '#0D47A1'
const FASCIST_COLOR = '#D32F2F'
const FASCIST_BG = '#B71C1C'
const GOLD = '#FFB300'
const DARK_BG = '#121212'
const SERIF = '"Palatino Linotype", "Book Antiqua", Palatino, Georgia, serif'

/* ================================================================== */
/*  HELPER COMPONENTS                                                  */
/* ================================================================== */

/* ---- Decorative divider ---- */
function ArtDecoDivider({ color = GOLD }: { color?: string }) {
  return (
    <div className="flex items-center gap-3 my-3">
      <div className="flex-1 h-px" style={{ background: `linear-gradient(to right, transparent, ${color}60)` }} />
      <span style={{ color: `${color}` }} className="text-xs">&#9670;</span>
      <div className="flex-1 h-px" style={{ background: `linear-gradient(to left, transparent, ${color}60)` }} />
    </div>
  )
}

/* ---- Policy slot on the board ---- */
function PolicySlot({
  filled,
  type,
  index,
  executiveAction,
}: {
  filled: boolean
  type: 'liberal' | 'fascist'
  index: number
  executiveAction?: ExecutiveAction | null
}) {
  const isLib = type === 'liberal'
  const bgColor = filled
    ? (isLib ? LIBERAL_COLOR : FASCIST_COLOR)
    : 'rgba(255,255,255,0.06)'
  const borderColor = isLib ? `${LIBERAL_COLOR}60` : `${FASCIST_COLOR}60`
  const icon = filled
    ? (isLib ? '🕊' : '💀')
    : (isLib ? (index + 1).toString() : (index + 1).toString())

  return (
    <div className="flex flex-col items-center gap-1">
      <div
        className="w-12 h-16 sm:w-14 sm:h-20 rounded-lg flex items-center justify-center text-xl font-bold transition-all duration-300 border-2"
        style={{
          background: filled ? bgColor : 'rgba(255,255,255,0.04)',
          borderColor: filled ? bgColor : borderColor,
          boxShadow: filled ? `0 0 16px ${bgColor}50` : 'none',
          color: filled ? '#fff' : 'rgba(255,255,255,0.2)',
        }}
      >
        {icon}
      </div>
      {executiveAction && !isLib && (
        <span
          className="text-[9px] uppercase tracking-wider font-bold text-center leading-tight"
          style={{ color: `${FASCIST_COLOR}90`, maxWidth: '4rem' }}
        >
          {executiveAction === 'investigate' && 'Investigate'}
          {executiveAction === 'special_election' && 'Sp. Election'}
          {executiveAction === 'peek' && 'Peek'}
          {executiveAction === 'kill' && 'Execution'}
        </span>
      )}
    </div>
  )
}

/* ---- Policy Board ---- */
function PolicyBoard({
  liberalPolicies,
  fascistPolicies,
  electionTracker,
  playerCount,
  vetoUnlocked,
}: {
  liberalPolicies: number
  fascistPolicies: number
  electionTracker: number
  playerCount: number
  vetoUnlocked: boolean
}) {
  const execActions = getExecutiveActions(playerCount)

  return (
    <div className="space-y-4">
      {/* Liberal Track */}
      <div
        className="rounded-xl p-3 sm:p-4 border"
        style={{ background: `${LIBERAL_BG}15`, borderColor: `${LIBERAL_COLOR}30` }}
      >
        <div className="flex items-center justify-between mb-2">
          <h3
            className="text-sm font-bold uppercase tracking-[0.2em]"
            style={{ color: LIBERAL_COLOR, fontFamily: SERIF }}
          >
            Liberal Policies
          </h3>
          <span className="text-xs" style={{ color: `${LIBERAL_COLOR}80` }}>
            {liberalPolicies}/5
          </span>
        </div>
        <div className="flex gap-1.5 sm:gap-2 justify-center">
          {Array.from({ length: 5 }, (_, i) => (
            <PolicySlot
              key={i}
              filled={i < liberalPolicies}
              type="liberal"
              index={i}
            />
          ))}
        </div>
      </div>

      {/* Fascist Track */}
      <div
        className="rounded-xl p-3 sm:p-4 border"
        style={{ background: `${FASCIST_BG}15`, borderColor: `${FASCIST_COLOR}30` }}
      >
        <div className="flex items-center justify-between mb-2">
          <h3
            className="text-sm font-bold uppercase tracking-[0.2em]"
            style={{ color: FASCIST_COLOR, fontFamily: SERIF }}
          >
            Fascist Policies
          </h3>
          <div className="flex items-center gap-2">
            {vetoUnlocked && (
              <span className="text-[10px] px-2 py-0.5 rounded-full bg-red-900/50 text-red-300 border border-red-700/50 font-bold uppercase tracking-wider">
                Veto Power Active
              </span>
            )}
            <span className="text-xs" style={{ color: `${FASCIST_COLOR}80` }}>
              {fascistPolicies}/6
            </span>
          </div>
        </div>
        <div className="flex gap-1.5 sm:gap-2 justify-center">
          {Array.from({ length: 6 }, (_, i) => (
            <PolicySlot
              key={i}
              filled={i < fascistPolicies}
              type="fascist"
              index={i}
              executiveAction={i < 5 ? execActions[i] : null}
            />
          ))}
        </div>
      </div>

      {/* Election Tracker */}
      <div className="flex items-center justify-center gap-4">
        <span className="text-xs text-gray-500 uppercase tracking-wider font-bold">
          Election Tracker
        </span>
        <div className="flex gap-2">
          {Array.from({ length: 3 }, (_, i) => (
            <div
              key={i}
              className="w-6 h-6 rounded-full border-2 flex items-center justify-center text-xs font-bold transition-all"
              style={{
                background: i < electionTracker ? `${GOLD}` : 'transparent',
                borderColor: i < electionTracker ? GOLD : 'rgba(255,255,255,0.15)',
                color: i < electionTracker ? '#000' : 'rgba(255,255,255,0.2)',
                boxShadow: i < electionTracker ? `0 0 8px ${GOLD}50` : 'none',
              }}
            >
              {i + 1}
            </div>
          ))}
        </div>
        {electionTracker >= 2 && (
          <span className="text-[10px] text-amber-400 font-bold animate-pulse">
            CHAOS IMMINENT
          </span>
        )}
      </div>
    </div>
  )
}

/* ---- Role Card (for role reveal) ---- */
function RoleCard({
  role,
  party,
  playerName,
  teammates,
  hitlerName,
  playerCount,
}: {
  role: 'liberal' | 'fascist' | 'hitler'
  party: 'liberal' | 'fascist'
  playerName: string
  teammates: string[]
  hitlerName: string | null
  playerCount: number
}) {
  const isLib = role === 'liberal'
  const isHitler = role === 'hitler'
  const color = isLib ? LIBERAL_COLOR : FASCIST_COLOR
  const bgGrad = isLib
    ? 'from-blue-950/90 via-blue-950/60 to-gray-950'
    : 'from-red-950/90 via-red-950/60 to-gray-950'

  return (
    <div
      className="max-w-sm w-full mx-auto rounded-2xl overflow-hidden shadow-2xl"
      style={{ border: `3px solid ${color}`, boxShadow: `0 0 60px ${color}25` }}
    >
      {/* Header */}
      <div className={`px-6 py-6 text-center bg-gradient-to-b ${bgGrad}`}>
        <div className="text-5xl mb-2">
          {isLib ? '🕊' : isHitler ? '🎭' : '💀'}
        </div>
        <div
          className="text-lg font-bold uppercase tracking-[0.3em] mb-1"
          style={{ color, fontFamily: SERIF }}
        >
          {isHitler ? 'Secret Hitler' : isLib ? 'Liberal' : 'Fascist'}
        </div>
        <div className="text-sm text-gray-400">{playerName}</div>
      </div>

      {/* Decorative divider */}
      <div
        className="h-1"
        style={{ background: `linear-gradient(to right, transparent, ${color}, transparent)` }}
      />

      {/* Body */}
      <div className="bg-gray-950 px-6 py-5 space-y-4">
        <div
          className="text-center text-sm p-3 rounded-lg"
          style={{
            background: `${color}10`,
            border: `1px solid ${color}25`,
            color: `${color}cc`,
          }}
        >
          <span className="font-bold uppercase tracking-wider text-xs">
            Party Membership:
          </span>
          <br />
          <span className="text-base font-bold" style={{ color }}>
            {party === 'liberal' ? 'Liberal' : 'Fascist'}
          </span>
        </div>

        {/* Fascist team info */}
        {!isLib && (
          <div className="space-y-2">
            {isHitler ? (
              <div className="text-sm text-gray-400 text-center">
                {playerCount <= 6 ? (
                  <>
                    <p className="text-red-300 font-semibold mb-1">Your Fellow Fascist:</p>
                    {teammates.length > 0 ? (
                      teammates.map((name) => (
                        <span key={name} className="inline-block px-3 py-1 rounded-full bg-red-900/30 text-red-300 text-xs font-bold border border-red-800/30 mr-1 mb-1">
                          {name}
                        </span>
                      ))
                    ) : (
                      <p className="text-gray-500 italic">No other fascists</p>
                    )}
                  </>
                ) : (
                  <p className="text-gray-500 italic">
                    You don&apos;t know who the other Fascists are. Trust no one.
                  </p>
                )}
              </div>
            ) : (
              <div className="text-sm text-gray-400 text-center space-y-2">
                <p className="text-red-300 font-semibold">Your Fascist Team:</p>
                {teammates.map((name) => (
                  <span key={name} className="inline-block px-3 py-1 rounded-full bg-red-900/30 text-red-300 text-xs font-bold border border-red-800/30 mr-1 mb-1">
                    {name}
                  </span>
                ))}
                {hitlerName && (
                  <div className="mt-2">
                    <span className="text-[10px] uppercase tracking-wider text-gray-500">Hitler is:</span>
                    <br />
                    <span className="inline-block px-3 py-1 mt-1 rounded-full bg-red-900/50 text-red-200 text-sm font-bold border border-red-700/50">
                      🎭 {hitlerName}
                    </span>
                  </div>
                )}
              </div>
            )}
          </div>
        )}

        {isLib && (
          <p className="text-sm text-blue-300/70 text-center italic">
            Enact 5 Liberal Policies or find and kill Hitler to win.
          </p>
        )}
      </div>
    </div>
  )
}

/* ---- Policy card for legislative sessions ---- */
function PolicyCardUI({
  policy,
  onClick,
  disabled,
  selected,
  size = 'normal',
}: {
  policy: PolicyCard
  onClick?: () => void
  disabled?: boolean
  selected?: boolean
  size?: 'normal' | 'small'
}) {
  const isLib = policy === 'liberal'
  const color = isLib ? LIBERAL_COLOR : FASCIST_COLOR
  const w = size === 'small' ? 'w-20 h-28' : 'w-28 h-40 sm:w-32 sm:h-44'

  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className={`
        ${w} rounded-xl flex flex-col items-center justify-center gap-2
        transition-all duration-200 border-3
        ${disabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer hover:scale-105 hover:shadow-xl'}
        ${selected ? 'ring-4 ring-offset-2 ring-offset-gray-950' : ''}
      `}
      style={{
        background: `linear-gradient(135deg, ${color}20, ${color}05)`,
        borderColor: color,
        boxShadow: selected ? `0 0 30px ${color}40` : `0 4px 12px ${color}15`,
        borderWidth: '3px',
      }}
    >
      <span className="text-3xl">{isLib ? '🕊' : '💀'}</span>
      <span
        className="text-xs font-bold uppercase tracking-[0.2em]"
        style={{ color, fontFamily: SERIF }}
      >
        {isLib ? 'Liberal' : 'Fascist'}
      </span>
    </button>
  )
}

/* ---- Player badge ---- */
function PlayerBadge({
  player,
  isPresident,
  isChancellor,
  isDead,
  isCurrentUser,
  showRole,
  onClick,
  disabled,
  highlight,
  size = 'normal',
}: {
  player: PlayerState
  isPresident?: boolean
  isChancellor?: boolean
  isDead?: boolean
  isCurrentUser?: boolean
  showRole?: boolean
  onClick?: () => void
  disabled?: boolean
  highlight?: 'liberal' | 'fascist' | null
  size?: 'normal' | 'compact'
}) {
  const dead = isDead ?? !player.alive
  const compact = size === 'compact'

  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled || dead}
      className={`
        ${compact ? 'px-3 py-2' : 'px-4 py-3'} rounded-xl transition-all duration-200
        flex items-center gap-3 w-full text-left
        ${dead ? 'opacity-30 line-through cursor-not-allowed' : ''}
        ${!dead && onClick && !disabled ? 'hover:scale-[1.02] cursor-pointer' : ''}
        ${disabled && !dead ? 'opacity-60 cursor-not-allowed' : ''}
      `}
      style={{
        background: highlight
          ? `${highlight === 'liberal' ? LIBERAL_COLOR : FASCIST_COLOR}15`
          : isCurrentUser
            ? 'rgba(255,255,255,0.08)'
            : 'rgba(255,255,255,0.03)',
        border: `1px solid ${
          highlight
            ? (highlight === 'liberal' ? LIBERAL_COLOR : FASCIST_COLOR) + '40'
            : isCurrentUser
              ? 'rgba(255,255,255,0.15)'
              : 'rgba(255,255,255,0.06)'
        }`,
      }}
    >
      {/* Avatar */}
      <div
        className={`${compact ? 'w-8 h-8 text-xs' : 'w-10 h-10 text-sm'} rounded-full flex items-center justify-center font-bold shrink-0`}
        style={{
          background: dead
            ? 'rgba(255,255,255,0.05)'
            : showRole
              ? (player.party === 'liberal' ? LIBERAL_COLOR : FASCIST_COLOR)
              : 'rgba(255,255,255,0.1)',
          color: '#fff',
        }}
      >
        {dead ? '💀' : player.playerName.slice(0, 2).toUpperCase()}
      </div>

      {/* Info */}
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className={`${compact ? 'text-xs' : 'text-sm'} font-bold text-white truncate`}>
            {player.playerName}
          </span>
          {isCurrentUser && (
            <span className="text-[10px] px-1.5 py-0.5 rounded bg-white/10 text-gray-400">(You)</span>
          )}
        </div>
        <div className="flex items-center gap-1.5 mt-0.5">
          {isPresident && (
            <span className="text-[10px] px-1.5 py-0.5 rounded-full font-bold uppercase tracking-wider"
              style={{ background: `${GOLD}30`, color: GOLD, border: `1px solid ${GOLD}40` }}>
              President
            </span>
          )}
          {isChancellor && (
            <span className="text-[10px] px-1.5 py-0.5 rounded-full font-bold uppercase tracking-wider"
              style={{ background: `${GOLD}30`, color: GOLD, border: `1px solid ${GOLD}40` }}>
              Chancellor
            </span>
          )}
          {dead && (
            <span className="text-[10px] text-red-400 font-bold uppercase">Executed</span>
          )}
          {showRole && !dead && (
            <span
              className="text-[10px] px-1.5 py-0.5 rounded-full font-bold uppercase tracking-wider"
              style={{
                background: `${player.role === 'hitler' ? FASCIST_COLOR : player.party === 'liberal' ? LIBERAL_COLOR : FASCIST_COLOR}25`,
                color: player.role === 'hitler' ? FASCIST_COLOR : player.party === 'liberal' ? LIBERAL_COLOR : FASCIST_COLOR,
              }}
            >
              {player.role === 'hitler' ? '🎭 Hitler' : player.party === 'liberal' ? 'Liberal' : 'Fascist'}
            </span>
          )}
        </div>
      </div>
    </button>
  )
}

/* ---- Game Log ---- */
function GameLog({ log }: { log: string[] }) {
  const bottomRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [log.length])

  return (
    <div className="h-32 overflow-y-auto text-xs space-y-1 p-2 rounded-lg bg-black/40 border border-white/5">
      {log.length === 0 && (
        <p className="text-gray-600 italic">No events yet...</p>
      )}
      {log.map((entry, i) => (
        <p key={i} className="text-gray-400 leading-tight">{entry}</p>
      ))}
      <div ref={bottomRef} />
    </div>
  )
}

/* ================================================================== */
/*  MAIN GAME COMPONENT                                                */
/* ================================================================== */

export default function SecretHitlerGame() {
  const { room, myPeerId } = useConnections()
  const {
    isHost,
    gameState: rawGameState,
    dispatchGameState,
    sendPlayerAction,
    setPlayerActionHandler,
  } = useGame()

  const state = useMemo(
    () => (rawGameState ?? {}) as Partial<SecretHitlerGameState>,
    [rawGameState]
  )

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

  /* ---------------------------------------------------------------- */
  /*  Host: initialise game state                                      */
  /* ---------------------------------------------------------------- */

  const hasInit = useRef(false)
  useEffect(() => {
    if (!isHost || hasInit.current || peerIds.length < 2) return
    hasInit.current = true

    const playerCount = peerIds.length
    const { liberals: libCount, fascists: fascistCount } = getRoleDistribution(playerCount)

    // Build role array
    const roles: Array<'liberal' | 'fascist' | 'hitler'> = [
      ...Array(libCount).fill('liberal') as 'liberal'[],
      ...Array(fascistCount).fill('fascist') as 'fascist'[],
      'hitler',
    ]
    const shuffledRoles = shuffle(roles)

    // Assign roles
    const turnOrder = shuffle([...peerIds])
    const players: Record<string, PlayerState> = {}
    turnOrder.forEach((pid, i) => {
      const role = shuffledRoles[i]!
      players[pid] = {
        peerId: pid,
        playerName: playerNames[pid] ?? 'Player',
        role,
        party: role === 'liberal' ? 'liberal' : 'fascist',
        alive: true,
        ready: false,
      }
    })

    const deck = createPolicyDeck()
    const firstPresidentIdx = 0

    const initial: SecretHitlerGameState = {
      phase: 'role_reveal',
      players,
      turnOrder,
      liberalPolicies: 0,
      fascistPolicies: 0,
      electionTracker: 0,
      drawPile: deck,
      discardPile: [],
      presidentIndex: firstPresidentIdx,
      presidentPeerId: turnOrder[firstPresidentIdx]!,
      chancellorNomineePeerId: null,
      lastElectedPresidentPeerId: null,
      lastElectedChancellorPeerId: null,
      votes: {},
      lastElectionResult: null,
      presidentHand: [],
      chancellorHand: [],
      currentExecutiveAction: null,
      investigatedPlayers: [],
      investigationResult: null,
      policyPeek: null,
      specialElectionReturnIndex: null,
      lastEnactedPolicy: null,
      vetoUnlocked: false,
      vetoRequested: false,
      deadPlayers: [],
      winner: null,
      winReason: null,
      playerCount,
      log: [
        'Welcome to Secret Hitler.',
        `${playerCount} players. ${libCount} Liberals, ${fascistCount} Fascist${fascistCount > 1 ? 's' : ''}, and Hitler.`,
        'Review your secret role cards.',
      ],
    }

    dispatchGameState(initial as unknown as Record<string, unknown>)
  }, [isHost, peerIds, playerNames, dispatchGameState])

  /* ---------------------------------------------------------------- */
  /*  Host: state updater                                              */
  /* ---------------------------------------------------------------- */

  const pushState = useCallback(
    (updater: (prev: SecretHitlerGameState) => SecretHitlerGameState) => {
      if (!isHost) return
      const current = rawGameState as unknown as SecretHitlerGameState
      if (!current) return
      const next = updater(current)
      dispatchGameState(next as unknown as Record<string, unknown>)
    },
    [isHost, rawGameState, dispatchGameState]
  )

  /* ---------------------------------------------------------------- */
  /*  Host: helper - advance to next president                         */
  /* ---------------------------------------------------------------- */

  const advancePresident = useCallback(
    (gs: SecretHitlerGameState): { nextIndex: number; nextPeerId: string } => {
      // If we had a special election, return to the saved index
      if (gs.specialElectionReturnIndex !== null) {
        const idx = gs.specialElectionReturnIndex
        let peerId = gs.turnOrder[idx]!
        // Make sure this player is alive; if not, advance
        let tries = 0
        let currentIdx = idx
        while (!gs.players[peerId]?.alive && tries < gs.turnOrder.length) {
          currentIdx = (currentIdx + 1) % gs.turnOrder.length
          peerId = gs.turnOrder[currentIdx]!
          tries++
        }
        return { nextIndex: currentIdx, nextPeerId: peerId }
      }

      let nextIdx = (gs.presidentIndex + 1) % gs.turnOrder.length
      let nextPeerId = gs.turnOrder[nextIdx]!
      let tries = 0
      while (!gs.players[nextPeerId]?.alive && tries < gs.turnOrder.length) {
        nextIdx = (nextIdx + 1) % gs.turnOrder.length
        nextPeerId = gs.turnOrder[nextIdx]!
        tries++
      }
      return { nextIndex: nextIdx, nextPeerId: nextPeerId }
    },
    []
  )

  /* ---------------------------------------------------------------- */
  /*  Host: helper - enact a policy                                    */
  /* ---------------------------------------------------------------- */

  const enactPolicy = useCallback(
    (gs: SecretHitlerGameState, policy: PolicyCard, fromChaos: boolean = false): SecretHitlerGameState => {
      const next = { ...gs }

      if (policy === 'liberal') {
        next.liberalPolicies++
        next.log = [...next.log, `A Liberal Policy has been enacted! (${next.liberalPolicies}/5)`]

        // Check liberal win
        if (next.liberalPolicies >= 5) {
          next.phase = 'game_over'
          next.winner = 'liberal'
          next.winReason = 'Five Liberal Policies have been enacted!'
          next.lastEnactedPolicy = 'liberal'
          return next
        }
      } else {
        next.fascistPolicies++
        next.log = [...next.log, `A Fascist Policy has been enacted! (${next.fascistPolicies}/6)`]

        // Check fascist win
        if (next.fascistPolicies >= 6) {
          next.phase = 'game_over'
          next.winner = 'fascist'
          next.winReason = 'Six Fascist Policies have been enacted!'
          next.lastEnactedPolicy = 'fascist'
          return next
        }

        // Unlock veto after 5th fascist policy
        if (next.fascistPolicies >= 5) {
          next.vetoUnlocked = true
        }
      }

      next.lastEnactedPolicy = policy
      next.electionTracker = 0

      // Reshuffle if needed
      const { drawPile: newDraw, discardPile: newDiscard } = reshuffleDeckIfNeeded(
        next.drawPile,
        next.discardPile,
      )
      next.drawPile = newDraw
      next.discardPile = newDiscard

      // Check for executive action (only on fascist policy, not from chaos)
      if (policy === 'fascist' && !fromChaos) {
        const execActions = getExecutiveActions(next.playerCount)
        const actionIdx = next.fascistPolicies - 1 // 0-indexed
        const action = actionIdx < execActions.length ? execActions[actionIdx] : null

        if (action) {
          next.currentExecutiveAction = action
          next.phase = 'executive_action'
          next.log = [...next.log, `Presidential Power: ${getActionLabel(action)}`]
          return next
        }
      }

      // Advance to next president
      const { nextIndex, nextPeerId } = advancePresident(next)
      next.presidentIndex = nextIndex
      next.presidentPeerId = nextPeerId
      next.chancellorNomineePeerId = null
      next.specialElectionReturnIndex = null
      next.phase = 'nomination'
      next.presidentHand = []
      next.chancellorHand = []
      next.vetoRequested = false
      next.log = [...next.log, `${next.players[nextPeerId]?.playerName} is the new Presidential Candidate.`]

      return next
    },
    [advancePresident]
  )

  /* ---------------------------------------------------------------- */
  /*  Host: handle player actions                                      */
  /* ---------------------------------------------------------------- */

  useEffect(() => {
    if (!isHost) {
      setPlayerActionHandler(null)
      return
    }

    const handler = (fromPeerId: string, action: Record<string, unknown>) => {
      const gs = rawGameState as unknown as SecretHitlerGameState
      if (!gs) return

      /* ---- Role reveal: player ready ---- */
      if (action.action === 'ready') {
        pushState((prev) => {
          const updated = {
            ...prev,
            players: {
              ...prev.players,
              [fromPeerId]: { ...prev.players[fromPeerId]!, ready: true },
            },
            log: [...prev.log, `${prev.players[fromPeerId]?.playerName} is ready.`],
          }
          // Check if all ready
          const allReady = Object.values(updated.players).every((p) => p.ready)
          if (allReady) {
            updated.phase = 'nomination'
            updated.log = [
              ...updated.log,
              '━━━ All players ready! The game begins! ━━━',
              `${updated.players[updated.presidentPeerId]?.playerName} is the first Presidential Candidate.`,
            ]
          }
          return updated
        })
      }

      /* ---- Nomination: president nominates chancellor ---- */
      if (action.action === 'nominate_chancellor') {
        if (gs.presidentPeerId !== fromPeerId) return
        const nomineePeerId = action.peerId as string
        if (!nomineePeerId) return

        // Validate eligibility
        const nominee = gs.players[nomineePeerId]
        if (!nominee?.alive) return
        if (nomineePeerId === fromPeerId) return

        // Term limits
        const alivePlayers = Object.values(gs.players).filter((p) => p.alive)
        if (alivePlayers.length > 5) {
          // Both last president and chancellor are term-limited
          if (nomineePeerId === gs.lastElectedPresidentPeerId) return
          if (nomineePeerId === gs.lastElectedChancellorPeerId) return
        } else {
          // Only last chancellor is term-limited (5 or fewer players)
          if (nomineePeerId === gs.lastElectedChancellorPeerId) return
        }

        // Initialize votes
        const votes: Record<string, boolean | null> = {}
        Object.values(gs.players).forEach((p) => {
          if (p.alive) votes[p.peerId] = null
        })

        pushState((prev) => ({
          ...prev,
          chancellorNomineePeerId: nomineePeerId,
          votes,
          phase: 'election',
          lastElectionResult: null,
          log: [
            ...prev.log,
            `${prev.players[fromPeerId]?.playerName} nominates ${prev.players[nomineePeerId]?.playerName} as Chancellor.`,
            'All players: vote Ja! or Nein.',
          ],
        }))
      }

      /* ---- Election: player votes ---- */
      if (action.action === 'vote') {
        if (gs.phase !== 'election') return
        const vote = action.vote as boolean
        if (typeof vote !== 'boolean') return
        if (!gs.players[fromPeerId]?.alive) return

        pushState((prev) => {
          const updated = {
            ...prev,
            votes: { ...prev.votes, [fromPeerId]: vote },
          }

          // Check if all alive players have voted
          const allVoted = Object.values(updated.players)
            .filter((p) => p.alive)
            .every((p) => updated.votes[p.peerId] !== null && updated.votes[p.peerId] !== undefined)

          if (!allVoted) return updated

          // Tally votes
          const jaCount = Object.values(updated.votes).filter((v) => v === true).length
          const neinCount = Object.values(updated.votes).filter((v) => v === false).length
          const passed = jaCount > neinCount

          const electionResult = {
            passed,
            votes: Object.fromEntries(
              Object.entries(updated.votes).filter(([, v]) => v !== null)
            ) as Record<string, boolean>,
            presidentPeerId: updated.presidentPeerId,
            chancellorPeerId: updated.chancellorNomineePeerId!,
          }

          updated.lastElectionResult = electionResult

          if (passed) {
            updated.log = [
              ...updated.log,
              `Election passed! (${jaCount} Ja!, ${neinCount} Nein)`,
              `${updated.players[updated.presidentPeerId]?.playerName} is President, ${updated.players[updated.chancellorNomineePeerId!]?.playerName} is Chancellor.`,
            ]

            // Check if Hitler was elected chancellor after 3+ fascist policies
            if (updated.fascistPolicies >= 3) {
              const chancellor = updated.players[updated.chancellorNomineePeerId!]
              if (chancellor?.role === 'hitler') {
                updated.phase = 'game_over'
                updated.winner = 'fascist'
                updated.winReason = `Hitler (${chancellor.playerName}) was elected Chancellor!`
                return updated
              }
            }

            // Set term limits
            updated.lastElectedPresidentPeerId = updated.presidentPeerId
            updated.lastElectedChancellorPeerId = updated.chancellorNomineePeerId

            // Draw 3 cards for president
            const { drawPile: newDraw, discardPile: newDiscard } = reshuffleDeckIfNeeded(
              updated.drawPile,
              updated.discardPile,
            )
            updated.drawPile = newDraw
            updated.discardPile = newDiscard
            updated.presidentHand = updated.drawPile.splice(0, 3)
            updated.chancellorHand = []
            updated.phase = 'legislative_president'
            updated.vetoRequested = false
            updated.log = [...updated.log, 'Legislative Session: President is reviewing policy tiles.']
          } else {
            updated.log = [
              ...updated.log,
              `Election failed. (${jaCount} Ja!, ${neinCount} Nein)`,
            ]

            // Advance election tracker
            updated.electionTracker++

            if (updated.electionTracker >= 3) {
              // CHAOS: auto-enact top policy
              const { drawPile: newDraw, discardPile: newDiscard } = reshuffleDeckIfNeeded(
                updated.drawPile,
                updated.discardPile,
              )
              updated.drawPile = newDraw
              updated.discardPile = newDiscard

              const topPolicy = updated.drawPile.shift()!
              updated.log = [...updated.log, '⚡ CHAOS! The country is thrown into turmoil!', `The top policy is enacted: ${topPolicy === 'liberal' ? 'Liberal' : 'Fascist'}`]

              // Reset
              updated.electionTracker = 0
              updated.lastElectedPresidentPeerId = null
              updated.lastElectedChancellorPeerId = null

              // Enact (no executive action from chaos)
              const afterEnact = enactPolicy(updated, topPolicy, true)
              if (afterEnact.phase === 'game_over') return afterEnact

              // Advance president
              const { nextIndex, nextPeerId } = advancePresident(afterEnact)
              afterEnact.presidentIndex = nextIndex
              afterEnact.presidentPeerId = nextPeerId
              afterEnact.chancellorNomineePeerId = null
              afterEnact.specialElectionReturnIndex = null
              afterEnact.phase = 'nomination'
              afterEnact.log = [...afterEnact.log, `${afterEnact.players[nextPeerId]?.playerName} is the new Presidential Candidate.`]
              return afterEnact
            } else {
              // Advance president
              const { nextIndex, nextPeerId } = advancePresident(updated)
              updated.presidentIndex = nextIndex
              updated.presidentPeerId = nextPeerId
              updated.chancellorNomineePeerId = null
              updated.specialElectionReturnIndex = null
              updated.phase = 'nomination'
              updated.log = [...updated.log, `${updated.players[nextPeerId]?.playerName} is the new Presidential Candidate.`]
            }
          }

          return updated
        })
      }

      /* ---- Legislative: President discards ---- */
      if (action.action === 'president_discard') {
        if (gs.phase !== 'legislative_president') return
        if (gs.presidentPeerId !== fromPeerId) return
        const discardIndex = action.index as number
        if (typeof discardIndex !== 'number' || discardIndex < 0 || discardIndex >= 3) return

        pushState((prev) => {
          const hand = [...prev.presidentHand]
          const discarded = hand.splice(discardIndex, 1)
          return {
            ...prev,
            presidentHand: [],
            chancellorHand: hand,
            discardPile: [...prev.discardPile, ...discarded],
            phase: 'legislative_chancellor',
            log: [...prev.log, 'President has passed 2 policy tiles to the Chancellor.'],
          }
        })
      }

      /* ---- Legislative: Chancellor enacts ---- */
      if (action.action === 'chancellor_enact') {
        if (gs.phase !== 'legislative_chancellor') return
        if (gs.chancellorNomineePeerId !== fromPeerId) return
        const enactIndex = action.index as number
        if (typeof enactIndex !== 'number' || enactIndex < 0 || enactIndex >= 2) return

        pushState((prev) => {
          const hand = [...prev.chancellorHand]
          const enacted = hand[enactIndex]!
          const discarded = hand.filter((_, i) => i !== enactIndex)
          const next = {
            ...prev,
            chancellorHand: [],
            discardPile: [...prev.discardPile, ...discarded],
          }
          return enactPolicy(next, enacted)
        })
      }

      /* ---- Legislative: Chancellor requests veto ---- */
      if (action.action === 'chancellor_veto') {
        if (gs.phase !== 'legislative_chancellor') return
        if (gs.chancellorNomineePeerId !== fromPeerId) return
        if (!gs.vetoUnlocked) return

        pushState((prev) => ({
          ...prev,
          vetoRequested: true,
          phase: 'veto_request',
          log: [...prev.log, `${prev.players[fromPeerId]?.playerName} (Chancellor) wishes to veto this agenda!`],
        }))
      }

      /* ---- Veto: President responds ---- */
      if (action.action === 'veto_response') {
        if (gs.phase !== 'veto_request') return
        if (gs.presidentPeerId !== fromPeerId) return
        const agree = action.agree as boolean

        if (agree) {
          pushState((prev) => {
            const updated = {
              ...prev,
              discardPile: [...prev.discardPile, ...prev.chancellorHand],
              chancellorHand: [],
              presidentHand: [],
              vetoRequested: false,
              electionTracker: prev.electionTracker + 1,
              log: [...prev.log, 'The President agrees to the veto. Both policies are discarded.'],
            }

            // Check chaos
            if (updated.electionTracker >= 3) {
              const { drawPile: newDraw, discardPile: newDiscard } = reshuffleDeckIfNeeded(
                updated.drawPile,
                updated.discardPile,
              )
              updated.drawPile = newDraw
              updated.discardPile = newDiscard

              const topPolicy = updated.drawPile.shift()!
              updated.log = [...updated.log, '⚡ CHAOS! The top policy is enacted!']
              updated.electionTracker = 0
              updated.lastElectedPresidentPeerId = null
              updated.lastElectedChancellorPeerId = null

              const afterEnact = enactPolicy(updated, topPolicy, true)
              if (afterEnact.phase === 'game_over') return afterEnact

              const { nextIndex, nextPeerId } = advancePresident(afterEnact)
              afterEnact.presidentIndex = nextIndex
              afterEnact.presidentPeerId = nextPeerId
              afterEnact.chancellorNomineePeerId = null
              afterEnact.specialElectionReturnIndex = null
              afterEnact.phase = 'nomination'
              afterEnact.log = [...afterEnact.log, `${afterEnact.players[nextPeerId]?.playerName} is the new Presidential Candidate.`]
              return afterEnact
            }

            // Advance president
            const { nextIndex, nextPeerId } = advancePresident(updated)
            updated.presidentIndex = nextIndex
            updated.presidentPeerId = nextPeerId
            updated.chancellorNomineePeerId = null
            updated.specialElectionReturnIndex = null
            updated.phase = 'nomination'
            updated.log = [...updated.log, `${updated.players[nextPeerId]?.playerName} is the new Presidential Candidate.`]
            return updated
          })
        } else {
          pushState((prev) => ({
            ...prev,
            vetoRequested: false,
            phase: 'legislative_chancellor',
            log: [...prev.log, 'The President rejects the veto. The Chancellor must enact a policy.'],
          }))
        }
      }

      /* ---- Executive: Investigate ---- */
      if (action.action === 'investigate') {
        if (gs.phase !== 'executive_action') return
        if (gs.presidentPeerId !== fromPeerId) return
        if (gs.currentExecutiveAction !== 'investigate') return
        const targetPeerId = action.peerId as string

        if (!targetPeerId) return
        if (gs.investigatedPlayers.includes(targetPeerId)) return
        if (!gs.players[targetPeerId]?.alive) return
        if (targetPeerId === fromPeerId) return

        const targetParty = gs.players[targetPeerId]!.party

        pushState((prev) => ({
          ...prev,
          investigatedPlayers: [...prev.investigatedPlayers, targetPeerId],
          investigationResult: { peerId: targetPeerId, party: targetParty },
          log: [
            ...prev.log,
            `${prev.players[fromPeerId]?.playerName} investigates ${prev.players[targetPeerId]?.playerName}.`,
          ],
        }))
      }

      /* ---- Executive: Acknowledge investigation ---- */
      if (action.action === 'acknowledge_investigation') {
        if (gs.presidentPeerId !== fromPeerId) return
        if (!gs.investigationResult) return

        pushState((prev) => {
          const { nextIndex, nextPeerId } = advancePresident(prev)
          return {
            ...prev,
            investigationResult: null,
            currentExecutiveAction: null,
            presidentIndex: nextIndex,
            presidentPeerId: nextPeerId,
            chancellorNomineePeerId: null,
            specialElectionReturnIndex: null,
            phase: 'nomination',
            log: [
              ...prev.log,
              `${prev.players[nextPeerId]?.playerName} is the new Presidential Candidate.`,
            ],
          }
        })
      }

      /* ---- Executive: Policy Peek ---- */
      if (action.action === 'peek') {
        if (gs.phase !== 'executive_action') return
        if (gs.presidentPeerId !== fromPeerId) return
        if (gs.currentExecutiveAction !== 'peek') return

        pushState((prev) => ({
          ...prev,
          policyPeek: prev.drawPile.slice(0, 3),
          log: [...prev.log, `${prev.players[fromPeerId]?.playerName} peeks at the top 3 policy tiles.`],
        }))
      }

      /* ---- Executive: Acknowledge peek ---- */
      if (action.action === 'acknowledge_peek') {
        if (gs.presidentPeerId !== fromPeerId) return
        if (!gs.policyPeek) return

        pushState((prev) => {
          const { nextIndex, nextPeerId } = advancePresident(prev)
          return {
            ...prev,
            policyPeek: null,
            currentExecutiveAction: null,
            presidentIndex: nextIndex,
            presidentPeerId: nextPeerId,
            chancellorNomineePeerId: null,
            specialElectionReturnIndex: null,
            phase: 'nomination',
            log: [
              ...prev.log,
              `${prev.players[nextPeerId]?.playerName} is the new Presidential Candidate.`,
            ],
          }
        })
      }

      /* ---- Executive: Special Election ---- */
      if (action.action === 'special_election') {
        if (gs.phase !== 'executive_action') return
        if (gs.presidentPeerId !== fromPeerId) return
        if (gs.currentExecutiveAction !== 'special_election') return
        const targetPeerId = action.peerId as string

        if (!targetPeerId) return
        if (!gs.players[targetPeerId]?.alive) return
        if (targetPeerId === fromPeerId) return

        const targetIdx = gs.turnOrder.indexOf(targetPeerId)
        // The return index should be the next player after the CURRENT president in normal rotation
        const returnIdx = (gs.presidentIndex + 1) % gs.turnOrder.length

        pushState((prev) => ({
          ...prev,
          currentExecutiveAction: null,
          presidentIndex: targetIdx,
          presidentPeerId: targetPeerId,
          chancellorNomineePeerId: null,
          specialElectionReturnIndex: returnIdx,
          phase: 'nomination',
          log: [
            ...prev.log,
            `Special Election! ${prev.players[targetPeerId]?.playerName} is the new Presidential Candidate.`,
          ],
        }))
      }

      /* ---- Executive: Kill (Execution) ---- */
      if (action.action === 'execute') {
        if (gs.phase !== 'executive_action') return
        if (gs.presidentPeerId !== fromPeerId) return
        if (gs.currentExecutiveAction !== 'kill') return
        const targetPeerId = action.peerId as string

        if (!targetPeerId) return
        if (!gs.players[targetPeerId]?.alive) return
        if (targetPeerId === fromPeerId) return

        const target = gs.players[targetPeerId]!

        // Check if Hitler was killed
        if (target.role === 'hitler') {
          pushState((prev) => ({
            ...prev,
            players: {
              ...prev.players,
              [targetPeerId]: { ...prev.players[targetPeerId]!, alive: false },
            },
            deadPlayers: [...prev.deadPlayers, targetPeerId],
            currentExecutiveAction: null,
            phase: 'game_over',
            winner: 'liberal',
            winReason: `Hitler (${target.playerName}) has been assassinated!`,
            log: [
              ...prev.log,
              `${prev.players[fromPeerId]?.playerName} executes ${target.playerName}.`,
              '🕊 Hitler has been killed! The Liberals win!',
            ],
          }))
          return
        }

        pushState((prev) => {
          const { nextIndex, nextPeerId } = advancePresident({
            ...prev,
            players: {
              ...prev.players,
              [targetPeerId]: { ...prev.players[targetPeerId]!, alive: false },
            },
          })
          return {
            ...prev,
            players: {
              ...prev.players,
              [targetPeerId]: { ...prev.players[targetPeerId]!, alive: false },
            },
            deadPlayers: [...prev.deadPlayers, targetPeerId],
            currentExecutiveAction: null,
            presidentIndex: nextIndex,
            presidentPeerId: nextPeerId,
            chancellorNomineePeerId: null,
            specialElectionReturnIndex: null,
            phase: 'nomination',
            log: [
              ...prev.log,
              `${prev.players[fromPeerId]?.playerName} executes ${target.playerName}. Their role remains unknown.`,
              `${prev.players[nextPeerId]?.playerName} is the new Presidential Candidate.`,
            ],
          }
        })
      }
    }

    setPlayerActionHandler(handler)
    return () => setPlayerActionHandler(null)
  }, [isHost, rawGameState, pushState, setPlayerActionHandler, enactPolicy, advancePresident])

  /* ---------------------------------------------------------------- */
  /*  Player actions                                                   */
  /* ---------------------------------------------------------------- */

  const markReady = useCallback(() => {
    sendPlayerAction({ action: 'ready' })
  }, [sendPlayerAction])

  const nominateChancellor = useCallback(
    (peerId: string) => {
      sendPlayerAction({ action: 'nominate_chancellor', peerId })
    },
    [sendPlayerAction]
  )

  const castVote = useCallback(
    (vote: boolean) => {
      sendPlayerAction({ action: 'vote', vote })
    },
    [sendPlayerAction]
  )

  const presidentDiscard = useCallback(
    (index: number) => {
      sendPlayerAction({ action: 'president_discard', index })
    },
    [sendPlayerAction]
  )

  const chancellorEnact = useCallback(
    (index: number) => {
      sendPlayerAction({ action: 'chancellor_enact', index })
    },
    [sendPlayerAction]
  )

  const chancellorVeto = useCallback(() => {
    sendPlayerAction({ action: 'chancellor_veto' })
  }, [sendPlayerAction])

  const vetoResponse = useCallback(
    (agree: boolean) => {
      sendPlayerAction({ action: 'veto_response', agree })
    },
    [sendPlayerAction]
  )

  const investigatePlayer = useCallback(
    (peerId: string) => {
      sendPlayerAction({ action: 'investigate', peerId })
    },
    [sendPlayerAction]
  )

  const acknowledgeInvestigation = useCallback(() => {
    sendPlayerAction({ action: 'acknowledge_investigation' })
  }, [sendPlayerAction])

  const peekPolicies = useCallback(() => {
    sendPlayerAction({ action: 'peek' })
  }, [sendPlayerAction])

  const acknowledgePeek = useCallback(() => {
    sendPlayerAction({ action: 'acknowledge_peek' })
  }, [sendPlayerAction])

  const callSpecialElection = useCallback(
    (peerId: string) => {
      sendPlayerAction({ action: 'special_election', peerId })
    },
    [sendPlayerAction]
  )

  const executePlayer = useCallback(
    (peerId: string) => {
      sendPlayerAction({ action: 'execute', peerId })
    },
    [sendPlayerAction]
  )

  /* ---------------------------------------------------------------- */
  /*  Computed values                                                  */
  /* ---------------------------------------------------------------- */

  const fullState = state as SecretHitlerGameState
  const myPlayer = myPeerId ? fullState.players?.[myPeerId] : null
  const amPresident = myPeerId === fullState.presidentPeerId
  const amChancellor = myPeerId === fullState.chancellorNomineePeerId

  // Get fascist team info for role reveal
  const fascistTeam = useMemo(() => {
    if (!fullState.players) return { teammates: [] as string[], hitlerName: null as string | null }
    const fascists = Object.values(fullState.players).filter((p) => p.party === 'fascist')
    const hitlerPlayer = fascists.find((p) => p.role === 'hitler')
    return {
      teammates: fascists.filter((p) => p.peerId !== myPeerId).map((p) => p.playerName),
      hitlerName: hitlerPlayer?.peerId !== myPeerId ? (hitlerPlayer?.playerName ?? null) : null,
    }
  }, [fullState.players, myPeerId])

  // Get eligible chancellor candidates
  const eligibleChancellors = useMemo(() => {
    if (!fullState.players) return []
    const alivePlayers = Object.values(fullState.players).filter(
      (p) => p.alive && p.peerId !== fullState.presidentPeerId
    )

    return alivePlayers.filter((p) => {
      const aliveCount = Object.values(fullState.players).filter((pl) => pl.alive).length
      if (aliveCount > 5) {
        return p.peerId !== fullState.lastElectedPresidentPeerId &&
               p.peerId !== fullState.lastElectedChancellorPeerId
      } else {
        return p.peerId !== fullState.lastElectedChancellorPeerId
      }
    })
  }, [fullState.players, fullState.presidentPeerId, fullState.lastElectedPresidentPeerId, fullState.lastElectedChancellorPeerId])

  /* ---------------------------------------------------------------- */
  /*  Render loading                                                   */
  /* ---------------------------------------------------------------- */

  if (!state.phase) {
    return (
      <div className="h-full flex items-center justify-center" style={{ background: DARK_BG }}>
        <div className="animate-pulse text-muted-foreground">Setting up...</div>
      </div>
    )
  }

  /* ================================================================ */
  /*  PHASE: ROLE REVEAL                                               */
  /* ================================================================ */

  if (state.phase === 'role_reveal') {
    const readyCount = Object.values(fullState.players).filter((p) => p.ready).length
    const totalCount = Object.values(fullState.players).length
    const amReady = myPlayer?.ready ?? false

    return (
      <div className="h-full overflow-auto p-4 flex flex-col items-center justify-center gap-6"
        style={{ background: `linear-gradient(180deg, ${DARK_BG} 0%, #1a1a2e 100%)` }}>

        <div className="text-center space-y-1">
          <h2 className="text-2xl font-bold text-white uppercase tracking-[0.3em]"
            style={{ fontFamily: SERIF }}>
            Your Secret Role
          </h2>
          <p className="text-xs text-gray-500">Memorize your role. Do not reveal it to anyone.</p>
        </div>

        {myPlayer && (
          <RoleCard
            role={myPlayer.role}
            party={myPlayer.party}
            playerName={myPlayer.playerName}
            teammates={myPlayer.party === 'fascist' ? fascistTeam.teammates : []}
            hitlerName={myPlayer.role === 'fascist' ? fascistTeam.hitlerName : null}
            playerCount={fullState.playerCount}
          />
        )}

        <div className="flex flex-col items-center gap-3">
          {!amReady ? (
            <button
              type="button"
              onClick={markReady}
              className="px-8 py-3 rounded-xl text-sm font-bold uppercase tracking-wider transition-all hover:brightness-110 cursor-pointer"
              style={{
                background: `linear-gradient(to bottom, ${GOLD}, ${GOLD}cc)`,
                color: '#000',
                boxShadow: `0 4px 16px ${GOLD}40`,
              }}
            >
              I Understand My Role
            </button>
          ) : (
            <span className="text-sm text-gray-400">Waiting for other players...</span>
          )}
          <span className="text-xs text-gray-600">
            {readyCount}/{totalCount} players ready
          </span>
        </div>
      </div>
    )
  }

  /* ================================================================ */
  /*  PHASE: GAME OVER                                                 */
  /* ================================================================ */

  if (state.phase === 'game_over') {
    const isLibWin = fullState.winner === 'liberal'
    const winColor = isLibWin ? LIBERAL_COLOR : FASCIST_COLOR
    const winBg = isLibWin ? LIBERAL_BG : FASCIST_BG

    return (
      <div className="h-full overflow-auto flex items-center justify-center p-6"
        style={{ background: `linear-gradient(180deg, ${winBg}30 0%, ${DARK_BG} 100%)` }}>
        <div className="max-w-lg w-full text-center space-y-6">
          <ArtDecoDivider color={winColor} />

          <div className="text-6xl mb-2">
            {isLibWin ? '🕊' : '💀'}
          </div>

          <h2
            className="text-4xl font-bold uppercase tracking-[0.2em]"
            style={{ color: winColor, fontFamily: SERIF }}
          >
            {isLibWin ? 'Liberals Win!' : 'Fascists Win!'}
          </h2>

          <p className="text-lg text-gray-300" style={{ fontFamily: SERIF }}>
            {fullState.winReason}
          </p>

          <ArtDecoDivider color={winColor} />

          {/* Reveal all roles */}
          <div className="space-y-2">
            <h3 className="text-sm font-bold uppercase tracking-wider text-gray-500 mb-3">
              All Roles Revealed
            </h3>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
              {Object.values(fullState.players).map((p) => (
                <PlayerBadge
                  key={p.peerId}
                  player={p}
                  isCurrentUser={p.peerId === myPeerId}
                  showRole
                  isDead={!p.alive}
                />
              ))}
            </div>
          </div>

          {/* Final board state */}
          <div className="mt-4">
            <PolicyBoard
              liberalPolicies={fullState.liberalPolicies}
              fascistPolicies={fullState.fascistPolicies}
              electionTracker={fullState.electionTracker}
              playerCount={fullState.playerCount}
              vetoUnlocked={fullState.vetoUnlocked}
            />
          </div>
        </div>
      </div>
    )
  }

  /* ================================================================ */
  /*  MAIN GAME LAYOUT (nomination, election, legislative, executive)  */
  /* ================================================================ */

  const currentPhase = fullState.phase as GamePhase

  return (
    <div className="h-full flex flex-col lg:flex-row overflow-hidden" style={{ background: DARK_BG }}>
      {/* ── Left Panel: Board + Action Area ── */}
      <div className="flex-1 min-h-0 overflow-auto p-3 sm:p-4 space-y-4">
        {/* Policy Board */}
        <PolicyBoard
          liberalPolicies={fullState.liberalPolicies}
          fascistPolicies={fullState.fascistPolicies}
          electionTracker={fullState.electionTracker}
          playerCount={fullState.playerCount}
          vetoUnlocked={fullState.vetoUnlocked}
        />

        {/* Last Election Result Banner */}
        {fullState.lastElectionResult && currentPhase !== 'election' && (
          <div
            className="rounded-lg p-3 text-center text-sm"
            style={{
              background: fullState.lastElectionResult.passed
                ? 'rgba(34,197,94,0.1)'
                : 'rgba(239,68,68,0.1)',
              border: `1px solid ${fullState.lastElectionResult.passed ? 'rgba(34,197,94,0.3)' : 'rgba(239,68,68,0.3)'}`,
              color: fullState.lastElectionResult.passed ? '#86efac' : '#fca5a5',
            }}
          >
            Last election: {fullState.lastElectionResult.passed ? 'PASSED' : 'FAILED'}
            <span className="text-xs text-gray-500 ml-2">
              ({Object.values(fullState.lastElectionResult.votes).filter((v) => v).length} Ja! /
              {' '}{Object.values(fullState.lastElectionResult.votes).filter((v) => !v).length} Nein)
            </span>
          </div>
        )}

        {/* ---- ACTION AREA ---- */}
        <div
          className="rounded-xl border p-4 sm:p-6 min-h-[200px]"
          style={{
            background: 'rgba(255,255,255,0.02)',
            borderColor: 'rgba(255,255,255,0.08)',
          }}
        >
          {/* ============================================ */}
          {/* NOMINATION PHASE                             */}
          {/* ============================================ */}
          {currentPhase === 'nomination' && (
            <div className="space-y-4">
              <div className="text-center">
                <span className="text-[10px] uppercase tracking-[0.3em] font-bold" style={{ color: GOLD }}>
                  Election Round
                </span>
                <h3 className="text-xl font-bold text-white mt-1" style={{ fontFamily: SERIF }}>
                  {amPresident
                    ? 'Nominate a Chancellor'
                    : `${fullState.players[fullState.presidentPeerId]?.playerName} is choosing a Chancellor...`}
                </h3>
              </div>

              {amPresident ? (
                <div className="space-y-2">
                  <p className="text-xs text-gray-500 text-center">
                    Select an eligible player to be your Chancellor candidate.
                  </p>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 max-w-2xl mx-auto">
                    {eligibleChancellors.map((p) => (
                      <PlayerBadge
                        key={p.peerId}
                        player={p}
                        isCurrentUser={p.peerId === myPeerId}
                        onClick={() => nominateChancellor(p.peerId)}
                        highlight={null}
                      />
                    ))}
                  </div>
                  {eligibleChancellors.length === 0 && (
                    <p className="text-sm text-red-400 text-center">No eligible candidates!</p>
                  )}
                </div>
              ) : (
                <div className="flex justify-center">
                  <div className="animate-pulse flex space-x-2">
                    <div className="w-2 h-2 rounded-full" style={{ background: GOLD }} />
                    <div className="w-2 h-2 rounded-full" style={{ background: GOLD }} />
                    <div className="w-2 h-2 rounded-full" style={{ background: GOLD }} />
                  </div>
                </div>
              )}
            </div>
          )}

          {/* ============================================ */}
          {/* ELECTION PHASE                               */}
          {/* ============================================ */}
          {currentPhase === 'election' && (
            <div className="space-y-6">
              <div className="text-center">
                <span className="text-[10px] uppercase tracking-[0.3em] font-bold" style={{ color: GOLD }}>
                  Vote on the Government
                </span>
                <h3 className="text-lg font-bold text-white mt-1" style={{ fontFamily: SERIF }}>
                  Proposed Government
                </h3>
              </div>

              {/* Proposed government */}
              <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
                <div className="text-center">
                  <span className="text-[10px] uppercase tracking-wider font-bold" style={{ color: GOLD }}>
                    President
                  </span>
                  <div
                    className="mt-1 px-5 py-3 rounded-xl border-2 text-white font-bold"
                    style={{ borderColor: GOLD, background: `${GOLD}10` }}
                  >
                    {fullState.players[fullState.presidentPeerId]?.playerName}
                    {fullState.presidentPeerId === myPeerId && (
                      <span className="text-xs text-gray-400 ml-1">(You)</span>
                    )}
                  </div>
                </div>
                <span className="text-2xl text-gray-600">&amp;</span>
                <div className="text-center">
                  <span className="text-[10px] uppercase tracking-wider font-bold" style={{ color: GOLD }}>
                    Chancellor
                  </span>
                  <div
                    className="mt-1 px-5 py-3 rounded-xl border-2 text-white font-bold"
                    style={{ borderColor: GOLD, background: `${GOLD}10` }}
                  >
                    {fullState.players[fullState.chancellorNomineePeerId!]?.playerName}
                    {fullState.chancellorNomineePeerId === myPeerId && (
                      <span className="text-xs text-gray-400 ml-1">(You)</span>
                    )}
                  </div>
                </div>
              </div>

              {/* Vote buttons */}
              {myPlayer?.alive && fullState.votes[myPeerId!] === null ? (
                <div className="flex justify-center gap-4">
                  <button
                    type="button"
                    onClick={() => castVote(true)}
                    className="px-10 py-4 rounded-xl text-xl font-bold uppercase tracking-wider transition-all hover:scale-105 cursor-pointer border-3"
                    style={{
                      background: 'rgba(34,197,94,0.15)',
                      borderColor: '#22c55e',
                      borderWidth: '3px',
                      color: '#22c55e',
                      boxShadow: '0 4px 16px rgba(34,197,94,0.2)',
                    }}
                  >
                    Ja!
                  </button>
                  <button
                    type="button"
                    onClick={() => castVote(false)}
                    className="px-10 py-4 rounded-xl text-xl font-bold uppercase tracking-wider transition-all hover:scale-105 cursor-pointer border-3"
                    style={{
                      background: 'rgba(239,68,68,0.15)',
                      borderColor: '#ef4444',
                      borderWidth: '3px',
                      color: '#ef4444',
                      boxShadow: '0 4px 16px rgba(239,68,68,0.2)',
                    }}
                  >
                    Nein
                  </button>
                </div>
              ) : fullState.votes[myPeerId!] !== null && fullState.votes[myPeerId!] !== undefined ? (
                <p className="text-center text-sm text-gray-400">
                  You voted <strong>{fullState.votes[myPeerId!] ? 'Ja!' : 'Nein'}</strong>. Waiting for others...
                </p>
              ) : null}

              {/* Vote status */}
              <div className="flex flex-wrap justify-center gap-2">
                {Object.values(fullState.players)
                  .filter((p) => p.alive)
                  .map((p) => (
                    <div key={p.peerId} className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-white/5">
                      <span className="text-xs text-gray-300">{p.playerName}</span>
                      {fullState.votes[p.peerId] !== null && fullState.votes[p.peerId] !== undefined ? (
                        <span className="text-xs text-green-400">✓</span>
                      ) : (
                        <span className="text-xs text-gray-600">...</span>
                      )}
                    </div>
                  ))}
              </div>
            </div>
          )}

          {/* ============================================ */}
          {/* LEGISLATIVE: PRESIDENT                        */}
          {/* ============================================ */}
          {currentPhase === 'legislative_president' && (
            <div className="space-y-4">
              <div className="text-center">
                <span className="text-[10px] uppercase tracking-[0.3em] font-bold" style={{ color: GOLD }}>
                  Legislative Session
                </span>
                <h3 className="text-xl font-bold text-white mt-1" style={{ fontFamily: SERIF }}>
                  {amPresident
                    ? 'Discard One Policy'
                    : 'President is reviewing policy tiles...'}
                </h3>
              </div>

              {amPresident ? (
                <div className="space-y-3">
                  <p className="text-xs text-gray-400 text-center">
                    Select one policy tile to <strong className="text-red-300">discard</strong>. The other two will be passed to the Chancellor.
                  </p>
                  <div className="flex justify-center gap-3 sm:gap-4">
                    {fullState.presidentHand.map((card, i) => (
                      <PolicyCardUI
                        key={i}
                        policy={card}
                        onClick={() => presidentDiscard(i)}
                      />
                    ))}
                  </div>
                </div>
              ) : (
                <div className="flex justify-center py-8">
                  <div className="animate-pulse flex space-x-2">
                    <div className="w-2 h-2 rounded-full" style={{ background: GOLD }} />
                    <div className="w-2 h-2 rounded-full" style={{ background: GOLD }} />
                    <div className="w-2 h-2 rounded-full" style={{ background: GOLD }} />
                  </div>
                </div>
              )}
            </div>
          )}

          {/* ============================================ */}
          {/* LEGISLATIVE: CHANCELLOR                       */}
          {/* ============================================ */}
          {currentPhase === 'legislative_chancellor' && (
            <div className="space-y-4">
              <div className="text-center">
                <span className="text-[10px] uppercase tracking-[0.3em] font-bold" style={{ color: GOLD }}>
                  Legislative Session
                </span>
                <h3 className="text-xl font-bold text-white mt-1" style={{ fontFamily: SERIF }}>
                  {amChancellor
                    ? 'Enact a Policy'
                    : 'Chancellor is choosing a policy to enact...'}
                </h3>
              </div>

              {amChancellor ? (
                <div className="space-y-4">
                  <p className="text-xs text-gray-400 text-center">
                    Select one policy to <strong className="text-green-300">enact</strong>. The other will be discarded.
                  </p>
                  <div className="flex justify-center gap-4">
                    {fullState.chancellorHand.map((card, i) => (
                      <PolicyCardUI
                        key={i}
                        policy={card}
                        onClick={() => chancellorEnact(i)}
                      />
                    ))}
                  </div>
                  {fullState.vetoUnlocked && !fullState.vetoRequested && (
                    <div className="text-center">
                      <button
                        type="button"
                        onClick={chancellorVeto}
                        className="px-6 py-2 rounded-lg text-sm font-bold uppercase tracking-wider transition-all hover:brightness-110 cursor-pointer"
                        style={{
                          background: 'rgba(239,68,68,0.2)',
                          color: '#fca5a5',
                          border: '1px solid rgba(239,68,68,0.3)',
                        }}
                      >
                        Veto This Agenda
                      </button>
                    </div>
                  )}
                </div>
              ) : (
                <div className="flex justify-center py-8">
                  <div className="animate-pulse flex space-x-2">
                    <div className="w-2 h-2 rounded-full" style={{ color: GOLD }} />
                    <div className="w-2 h-2 rounded-full" style={{ color: GOLD }} />
                    <div className="w-2 h-2 rounded-full" style={{ color: GOLD }} />
                  </div>
                </div>
              )}
            </div>
          )}

          {/* ============================================ */}
          {/* VETO REQUEST                                  */}
          {/* ============================================ */}
          {currentPhase === 'veto_request' && (
            <div className="space-y-4">
              <div className="text-center">
                <span className="text-[10px] uppercase tracking-[0.3em] font-bold text-red-400">
                  Veto Requested
                </span>
                <h3 className="text-xl font-bold text-white mt-1" style={{ fontFamily: SERIF }}>
                  {amPresident
                    ? 'The Chancellor wishes to veto this agenda'
                    : 'Chancellor has requested a veto...'}
                </h3>
              </div>

              {amPresident ? (
                <div className="space-y-3 text-center">
                  <p className="text-sm text-gray-400">
                    If you agree, both policy tiles are discarded and the Election Tracker advances.
                  </p>
                  <div className="flex justify-center gap-4">
                    <button
                      type="button"
                      onClick={() => vetoResponse(true)}
                      className="px-8 py-3 rounded-xl text-sm font-bold uppercase tracking-wider transition-all hover:scale-105 cursor-pointer"
                      style={{
                        background: 'rgba(34,197,94,0.2)',
                        color: '#86efac',
                        border: '2px solid rgba(34,197,94,0.4)',
                      }}
                    >
                      Agree to Veto
                    </button>
                    <button
                      type="button"
                      onClick={() => vetoResponse(false)}
                      className="px-8 py-3 rounded-xl text-sm font-bold uppercase tracking-wider transition-all hover:scale-105 cursor-pointer"
                      style={{
                        background: 'rgba(239,68,68,0.2)',
                        color: '#fca5a5',
                        border: '2px solid rgba(239,68,68,0.4)',
                      }}
                    >
                      Reject Veto
                    </button>
                  </div>
                </div>
              ) : (
                <div className="text-center text-sm text-gray-400">
                  Waiting for the President&apos;s decision...
                </div>
              )}
            </div>
          )}

          {/* ============================================ */}
          {/* EXECUTIVE ACTION                              */}
          {/* ============================================ */}
          {currentPhase === 'executive_action' && (
            <div className="space-y-4">
              <div className="text-center">
                <span className="text-[10px] uppercase tracking-[0.3em] font-bold text-red-400">
                  Presidential Power
                </span>
                <h3 className="text-xl font-bold text-white mt-1" style={{ fontFamily: SERIF }}>
                  {getActionLabel(fullState.currentExecutiveAction)}
                </h3>
                <p className="text-xs text-gray-400 mt-1">
                  {getActionDescription(fullState.currentExecutiveAction)}
                </p>
              </div>

              {/* Investigate */}
              {fullState.currentExecutiveAction === 'investigate' && (
                <>
                  {fullState.investigationResult ? (
                    // Show result to president
                    amPresident ? (
                      <div className="text-center space-y-4">
                        <div
                          className="inline-block px-8 py-4 rounded-xl border-2"
                          style={{
                            borderColor: fullState.investigationResult.party === 'liberal' ? LIBERAL_COLOR : FASCIST_COLOR,
                            background: `${fullState.investigationResult.party === 'liberal' ? LIBERAL_COLOR : FASCIST_COLOR}15`,
                          }}
                        >
                          <p className="text-xs text-gray-500 mb-1">
                            {fullState.players[fullState.investigationResult.peerId]?.playerName}&apos;s Party Membership:
                          </p>
                          <p
                            className="text-2xl font-bold uppercase tracking-wider"
                            style={{
                              color: fullState.investigationResult.party === 'liberal' ? LIBERAL_COLOR : FASCIST_COLOR,
                              fontFamily: SERIF,
                            }}
                          >
                            {fullState.investigationResult.party === 'liberal' ? '🕊 Liberal' : '💀 Fascist'}
                          </p>
                        </div>
                        <p className="text-xs text-gray-500 italic">
                          You may share or lie about this result.
                        </p>
                        <button
                          type="button"
                          onClick={acknowledgeInvestigation}
                          className="px-6 py-2 rounded-lg text-sm font-bold uppercase tracking-wider cursor-pointer"
                          style={{
                            background: `${GOLD}20`,
                            color: GOLD,
                            border: `1px solid ${GOLD}40`,
                          }}
                        >
                          Continue
                        </button>
                      </div>
                    ) : (
                      <div className="text-center text-sm text-gray-400">
                        The President is viewing the investigation result...
                      </div>
                    )
                  ) : (
                    // Pick target
                    amPresident ? (
                      <div className="space-y-2">
                        <p className="text-xs text-gray-500 text-center">
                          Choose a player to investigate. You cannot investigate the same player twice.
                        </p>
                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 max-w-2xl mx-auto">
                          {Object.values(fullState.players)
                            .filter(
                              (p) =>
                                p.alive &&
                                p.peerId !== myPeerId &&
                                !fullState.investigatedPlayers.includes(p.peerId)
                            )
                            .map((p) => (
                              <PlayerBadge
                                key={p.peerId}
                                player={p}
                                onClick={() => investigatePlayer(p.peerId)}
                              />
                            ))}
                        </div>
                      </div>
                    ) : (
                      <div className="text-center text-sm text-gray-400">
                        The President is choosing someone to investigate...
                      </div>
                    )
                  )}
                </>
              )}

              {/* Policy Peek */}
              {fullState.currentExecutiveAction === 'peek' && (
                <>
                  {fullState.policyPeek ? (
                    amPresident ? (
                      <div className="text-center space-y-4">
                        <p className="text-sm text-gray-400">
                          The top 3 policy tiles are:
                        </p>
                        <div className="flex justify-center gap-3">
                          {fullState.policyPeek.map((card, i) => (
                            <PolicyCardUI key={i} policy={card} disabled size="small" />
                          ))}
                        </div>
                        <p className="text-xs text-gray-500 italic">
                          Remember these. You may share or lie about what you saw.
                        </p>
                        <button
                          type="button"
                          onClick={acknowledgePeek}
                          className="px-6 py-2 rounded-lg text-sm font-bold uppercase tracking-wider cursor-pointer"
                          style={{
                            background: `${GOLD}20`,
                            color: GOLD,
                            border: `1px solid ${GOLD}40`,
                          }}
                        >
                          Continue
                        </button>
                      </div>
                    ) : (
                      <div className="text-center text-sm text-gray-400">
                        The President is peeking at the policy deck...
                      </div>
                    )
                  ) : (
                    amPresident ? (
                      <div className="text-center">
                        <button
                          type="button"
                          onClick={peekPolicies}
                          className="px-8 py-3 rounded-xl text-sm font-bold uppercase tracking-wider cursor-pointer"
                          style={{
                            background: `${GOLD}20`,
                            color: GOLD,
                            border: `2px solid ${GOLD}40`,
                            boxShadow: `0 4px 16px ${GOLD}20`,
                          }}
                        >
                          Peek at Top 3 Policies
                        </button>
                      </div>
                    ) : (
                      <div className="text-center text-sm text-gray-400">
                        The President is about to peek at the policy deck...
                      </div>
                    )
                  )}
                </>
              )}

              {/* Special Election */}
              {fullState.currentExecutiveAction === 'special_election' && (
                amPresident ? (
                  <div className="space-y-2">
                    <p className="text-xs text-gray-500 text-center">
                      Choose any other player to be the next Presidential Candidate.
                    </p>
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 max-w-2xl mx-auto">
                      {Object.values(fullState.players)
                        .filter((p) => p.alive && p.peerId !== myPeerId)
                        .map((p) => (
                          <PlayerBadge
                            key={p.peerId}
                            player={p}
                            onClick={() => callSpecialElection(p.peerId)}
                          />
                        ))}
                    </div>
                  </div>
                ) : (
                  <div className="text-center text-sm text-gray-400">
                    The President is choosing the next Presidential Candidate...
                  </div>
                )
              )}

              {/* Execution */}
              {fullState.currentExecutiveAction === 'kill' && (
                amPresident ? (
                  <div className="space-y-2">
                    <p className="text-xs text-red-400 text-center font-semibold">
                      You must execute one player. If they are Hitler, the Liberals win.
                    </p>
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 max-w-2xl mx-auto">
                      {Object.values(fullState.players)
                        .filter((p) => p.alive && p.peerId !== myPeerId)
                        .map((p) => (
                          <PlayerBadge
                            key={p.peerId}
                            player={p}
                            onClick={() => executePlayer(p.peerId)}
                            highlight="fascist"
                          />
                        ))}
                    </div>
                  </div>
                ) : (
                  <div className="text-center text-sm text-gray-400">
                    The President is deciding who to execute...
                  </div>
                )
              )}
            </div>
          )}
        </div>
      </div>

      {/* ── Right Panel: Players + Log ── */}
      <div className="w-full lg:w-80 xl:w-96 shrink-0 border-t lg:border-t-0 lg:border-l border-white/10 bg-gray-900/30 flex flex-col overflow-hidden">
        {/* Your role reminder */}
        {myPlayer && (
          <div
            className="p-3 border-b text-center"
            style={{
              borderColor: 'rgba(255,255,255,0.08)',
              background: `${myPlayer.party === 'liberal' ? LIBERAL_COLOR : FASCIST_COLOR}08`,
            }}
          >
            <span className="text-[10px] uppercase tracking-wider text-gray-500">Your Secret Role</span>
            <div className="flex items-center justify-center gap-2 mt-0.5">
              <span className="text-sm">
                {myPlayer.role === 'liberal' ? '🕊' : myPlayer.role === 'hitler' ? '🎭' : '💀'}
              </span>
              <span
                className="text-sm font-bold uppercase tracking-wider"
                style={{
                  color: myPlayer.party === 'liberal' ? LIBERAL_COLOR : FASCIST_COLOR,
                  fontFamily: SERIF,
                }}
              >
                {myPlayer.role === 'hitler' ? 'Hitler' : myPlayer.party === 'liberal' ? 'Liberal' : 'Fascist'}
              </span>
            </div>
          </div>
        )}

        {/* Government */}
        <div className="p-3 border-b border-white/8">
          <span className="text-[10px] uppercase tracking-wider text-gray-500 font-bold">
            Current Government
          </span>
          <div className="flex items-center gap-4 mt-1">
            <div>
              <span className="text-[10px] text-gray-600">President</span>
              <p className="text-xs font-bold text-white">
                {fullState.players[fullState.presidentPeerId]?.playerName}
                {amPresident && <span className="text-gray-500 ml-1">(You)</span>}
              </p>
            </div>
            {fullState.chancellorNomineePeerId && (
              <div>
                <span className="text-[10px] text-gray-600">Chancellor</span>
                <p className="text-xs font-bold text-white">
                  {fullState.players[fullState.chancellorNomineePeerId]?.playerName}
                  {amChancellor && <span className="text-gray-500 ml-1">(You)</span>}
                </p>
              </div>
            )}
          </div>
        </div>

        {/* Phase indicator */}
        <div className="p-3 border-b border-white/8">
          <span className="text-[10px] uppercase tracking-wider text-gray-500 font-bold">
            Phase
          </span>
          <p className="text-xs font-bold mt-0.5" style={{ color: GOLD }}>
            {currentPhase === 'nomination' && 'Chancellor Nomination'}
            {currentPhase === 'election' && 'Election'}
            {currentPhase === 'legislative_president' && 'Legislative Session (President)'}
            {currentPhase === 'legislative_chancellor' && 'Legislative Session (Chancellor)'}
            {currentPhase === 'veto_request' && 'Veto Request'}
            {currentPhase === 'executive_action' && `Executive Action: ${getActionLabel(fullState.currentExecutiveAction)}`}
          </p>
        </div>

        {/* Player list */}
        <div className="flex-1 overflow-y-auto p-3 space-y-3">
          <div className="space-y-1.5">
            <h4 className="text-[10px] uppercase tracking-wider text-gray-500 font-bold">
              Players ({Object.values(fullState.players).filter((p) => p.alive).length} alive)
            </h4>
            {fullState.turnOrder.map((pid) => {
              const p = fullState.players[pid]!
              return (
                <PlayerBadge
                  key={pid}
                  player={p}
                  isPresident={pid === fullState.presidentPeerId}
                  isChancellor={pid === fullState.chancellorNomineePeerId}
                  isCurrentUser={pid === myPeerId}
                  isDead={!p.alive}
                  size="compact"
                />
              )
            })}
          </div>

          {/* Draw / Discard info */}
          <div className="flex items-center gap-4 text-xs text-gray-500">
            <span>Draw: {fullState.drawPile.length}</span>
            <span>Discard: {fullState.discardPile.length}</span>
          </div>

          {/* Game Log */}
          <div>
            <h4 className="text-[10px] uppercase tracking-wider text-gray-500 font-bold mb-1.5">
              Game Log
            </h4>
            <GameLog log={fullState.log} />
          </div>
        </div>
      </div>
    </div>
  )
}
