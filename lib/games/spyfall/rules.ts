import type { GameModule, PlayerId, RuleContext, RuleResult } from '@/lib/engine/types'
import { SPYFALL_LOCATIONS } from './locations'

export const ROUND_MS = 8 * 60 * 1000
export const VOTE_MS = 60 * 1000

export type SpyfallPhase = 'playing' | 'voting' | 'ended'

export interface SpyfallResult {
  winner: 'spy' | 'agents' | 'none'
  reason: string
  accused: PlayerId | null
  spyGuess: string | null
}

export interface SpyfallState {
  phase: SpyfallPhase
  players: PlayerId[]
  spy: PlayerId
  location: string
  firstAsker: PlayerId
  endsAt: number
  voteEndsAt: number | null
  /** Players who want to stop questioning and vote now. */
  callingVote: PlayerId[]
  votes: Record<PlayerId, PlayerId>
  result: SpyfallResult | null
}

export type SpyfallAction =
  | { type: 'callVote'; on: boolean }
  | { type: 'vote'; target: PlayerId }
  | { type: 'guessLocation'; location: string }

export interface SpyfallView {
  phase: SpyfallPhase
  players: PlayerId[]
  /** null for spectators. */
  isSpy: boolean | null
  /** Hidden from the spy and spectators until the round ends. */
  location: string | null
  locations: readonly string[]
  firstAsker: PlayerId
  endsAt: number
  voteEndsAt: number | null
  callingVote: PlayerId[]
  /** Who has voted (not who they voted for). */
  voted: PlayerId[]
  myVote: PlayerId | null
  /** Revealed only once the round is over. */
  spy: PlayerId | null
  votes: Record<PlayerId, PlayerId> | null
  result: SpyfallResult | null
}

function pick<T>(items: readonly T[], random: () => number): T {
  return items[Math.floor(random() * items.length)]!
}

function startVoting(state: SpyfallState, ctx: RuleContext): SpyfallState {
  return { ...state, phase: 'voting', voteEndsAt: ctx.now + VOTE_MS, votes: {}, callingVote: [] }
}

function end(state: SpyfallState, result: SpyfallResult): SpyfallState {
  return { ...state, phase: 'ended', voteEndsAt: null, result }
}

/** Plurality wins. A tie or no votes means the agents failed to agree. */
function resolveVotes(state: SpyfallState): SpyfallState {
  const tally = new Map<PlayerId, number>()
  for (const target of Object.values(state.votes)) {
    tally.set(target, (tally.get(target) ?? 0) + 1)
  }
  const ranked = [...tally.entries()].sort((a, b) => b[1] - a[1])
  const top = ranked[0]
  const tied = ranked.length > 1 && ranked[1]![1] === top?.[1]

  if (!top || tied) {
    return end(state, {
      winner: 'spy',
      reason: top ? 'The vote was tied, so nobody was accused.' : 'Nobody voted.',
      accused: null,
      spyGuess: null,
    })
  }
  const accused = top[0]
  return end(state, {
    winner: accused === state.spy ? 'agents' : 'spy',
    reason: accused === state.spy ? 'The agents caught the spy.' : 'The agents accused an innocent player.',
    accused,
    spyGuess: null,
  })
}

function allVoted(state: SpyfallState): boolean {
  return state.players.every((id) => state.votes[id] !== undefined)
}

export const spyfall: GameModule<SpyfallState, SpyfallAction, SpyfallView> = {
  id: 'spyfall',
  name: 'Spyfall',
  description:
    'Everyone but the spy knows the secret location. Take turns asking each other questions. Agents try to find the spy; the spy tries to work out the location.',
  minPlayers: 3,
  maxPlayers: 12,

  setup(players, ctx) {
    return {
      phase: 'playing',
      players,
      spy: pick(players, ctx.random),
      location: pick(SPYFALL_LOCATIONS, ctx.random),
      firstAsker: pick(players, ctx.random),
      endsAt: ctx.now + ROUND_MS,
      voteEndsAt: null,
      callingVote: [],
      votes: {},
      result: null,
    }
  },

  action(state, playerId, action, ctx): RuleResult<SpyfallState> {
    if (state.phase === 'ended') return { error: 'The round is over.' }

    switch (action.type) {
      case 'callVote': {
        if (state.phase !== 'playing') return { error: 'Voting has already started.' }
        const others = state.callingVote.filter((id) => id !== playerId)
        const callingVote = action.on ? [...others, playerId] : others
        const next = { ...state, callingVote }
        // More than half the table wants to vote → start voting.
        if (callingVote.length * 2 > state.players.length) return { state: startVoting(next, ctx) }
        return { state: next }
      }
      case 'vote': {
        if (state.phase !== 'voting') return { error: 'It is not time to vote yet.' }
        if (action.target === playerId) return { error: "You can't vote for yourself." }
        if (!state.players.includes(action.target)) return { error: 'That player is not in this round.' }
        const next = { ...state, votes: { ...state.votes, [playerId]: action.target } }
        return { state: allVoted(next) ? resolveVotes(next) : next }
      }
      case 'guessLocation': {
        if (playerId !== state.spy) return { error: 'Only the spy can guess the location.' }
        const correct = action.location === state.location
        return {
          state: end(state, {
            winner: correct ? 'spy' : 'agents',
            reason: correct ? 'The spy guessed the location.' : 'The spy guessed the wrong location.',
            accused: null,
            spyGuess: action.location,
          }),
        }
      }
      default:
        return { error: 'Unknown action.' }
    }
  },

  tick(state, ctx) {
    if (state.phase === 'playing' && ctx.now >= state.endsAt) return startVoting(state, ctx)
    if (state.phase === 'voting' && state.voteEndsAt !== null && ctx.now >= state.voteEndsAt) {
      return resolveVotes(state)
    }
    return state
  },

  playerLeft(state, playerId) {
    if (state.phase === 'ended') return state
    if (playerId === state.spy) {
      return end(state, { winner: 'none', reason: 'The spy left the game.', accused: null, spyGuess: null })
    }
    const players = state.players.filter((id) => id !== playerId)
    const votes = Object.fromEntries(
      Object.entries(state.votes).filter(([voter, target]) => voter !== playerId && target !== playerId),
    )
    const next: SpyfallState = {
      ...state,
      players,
      votes,
      callingVote: state.callingVote.filter((id) => id !== playerId),
      firstAsker: state.firstAsker === playerId ? state.spy : state.firstAsker,
    }
    if (players.length < 3) {
      return end(next, { winner: 'none', reason: 'Too few players left to continue.', accused: null, spyGuess: null })
    }
    if (next.phase === 'voting' && allVoted(next)) return resolveVotes(next)
    return next
  },

  isOver(state) {
    return state.phase === 'ended'
  },

  view(state, playerId) {
    const ended = state.phase === 'ended'
    const seated = playerId !== null && state.players.includes(playerId)
    const isSpy = seated ? playerId === state.spy : null
    return {
      phase: state.phase,
      players: state.players,
      isSpy,
      location: ended || isSpy === false ? state.location : null,
      locations: SPYFALL_LOCATIONS,
      firstAsker: state.firstAsker,
      endsAt: state.endsAt,
      voteEndsAt: state.voteEndsAt,
      callingVote: state.callingVote,
      voted: Object.keys(state.votes),
      myVote: playerId ? state.votes[playerId] ?? null : null,
      spy: ended ? state.spy : null,
      votes: ended ? state.votes : null,
      result: state.result,
    }
  },
}
