/* ------------------------------------------------------------------ */
/*  Secret Hitler – Type definitions & game constants                  */
/* ------------------------------------------------------------------ */

export type PolicyCard = 'liberal' | 'fascist'
export type Role = 'liberal' | 'fascist' | 'hitler'
export type Party = 'liberal' | 'fascist'
export type ExecutiveAction = 'investigate' | 'special_election' | 'peek' | 'kill'

export type GamePhase =
  | 'role_reveal'
  | 'nomination'
  | 'election'
  | 'legislative_president'
  | 'legislative_chancellor'
  | 'veto_request'
  | 'executive_action'
  | 'game_over'

/* ---- Player ---- */

export interface PlayerState {
  peerId: string
  playerName: string
  role: Role
  party: Party
  alive: boolean
  ready: boolean
}

/* ---- Full Game State ---- */

export interface SecretHitlerGameState {
  phase: GamePhase

  /* Players */
  players: Record<string, PlayerState>
  turnOrder: string[]          // peer IDs in clockwise order

  /* Board */
  liberalPolicies: number      // 0–5
  fascistPolicies: number      // 0–6
  electionTracker: number      // 0–3
  drawPile: PolicyCard[]
  discardPile: PolicyCard[]

  /* Election */
  presidentIndex: number
  presidentPeerId: string
  chancellorNomineePeerId: string | null
  lastElectedPresidentPeerId: string | null
  lastElectedChancellorPeerId: string | null
  votes: Record<string, boolean | null>
  lastElectionResult: {
    passed: boolean
    votes: Record<string, boolean>
    presidentPeerId: string
    chancellorPeerId: string
  } | null

  /* Legislative session */
  presidentHand: PolicyCard[]
  chancellorHand: PolicyCard[]

  /* Executive action */
  currentExecutiveAction: ExecutiveAction | null
  investigatedPlayers: string[]
  investigationResult: { peerId: string; party: Party } | null
  policyPeek: PolicyCard[] | null

  /* Special election */
  specialElectionReturnIndex: number | null

  /* Last enacted policy (for display) */
  lastEnactedPolicy: PolicyCard | null

  /* Veto */
  vetoUnlocked: boolean
  vetoRequested: boolean

  /* Dead */
  deadPlayers: string[]

  /* Game over */
  winner: 'liberal' | 'fascist' | null
  winReason: string | null

  /* Config */
  playerCount: number

  /* Log */
  log: string[]
}

/* ------------------------------------------------------------------ */
/*  Constants & helpers                                                */
/* ------------------------------------------------------------------ */

/** Executive actions per fascist policy slot (index 0 = 1st fascist policy) */
export function getExecutiveActions(playerCount: number): (ExecutiveAction | null)[] {
  if (playerCount <= 6) {
    return [null, null, 'peek', 'kill', 'kill']
  } else if (playerCount <= 8) {
    return [null, 'investigate', 'special_election', 'kill', 'kill']
  } else {
    return ['investigate', 'investigate', 'special_election', 'kill', 'kill']
  }
}

/** Role distribution (fascists does NOT include Hitler) */
export function getRoleDistribution(playerCount: number): { liberals: number; fascists: number } {
  const map: Record<number, { liberals: number; fascists: number }> = {
    5:  { liberals: 3, fascists: 1 },
    6:  { liberals: 4, fascists: 1 },
    7:  { liberals: 4, fascists: 2 },
    8:  { liberals: 5, fascists: 2 },
    9:  { liberals: 5, fascists: 3 },
    10: { liberals: 6, fascists: 3 },
  }
  return map[playerCount] ?? map[5]!
}

/** Create the initial 17-card policy deck and shuffle */
export function createPolicyDeck(): PolicyCard[] {
  const deck: PolicyCard[] = [
    ...Array(6).fill('liberal') as PolicyCard[],
    ...Array(11).fill('fascist') as PolicyCard[],
  ]
  return shuffle(deck)
}

/** Fisher-Yates shuffle */
export function shuffle<T>(arr: T[]): T[] {
  const a = [...arr]
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1))
    ;[a[i], a[j]] = [a[j]!, a[i]!]
  }
  return a
}

/** Reshuffle discard into draw pile when < 3 cards remain */
export function reshuffleDeckIfNeeded(
  drawPile: PolicyCard[],
  discardPile: PolicyCard[],
): { drawPile: PolicyCard[]; discardPile: PolicyCard[] } {
  if (drawPile.length < 3) {
    return {
      drawPile: shuffle([...drawPile, ...discardPile]),
      discardPile: [],
    }
  }
  return { drawPile, discardPile }
}

/** Label for an executive action */
export function getActionLabel(action: ExecutiveAction | null): string {
  switch (action) {
    case 'investigate': return 'Investigate Loyalty'
    case 'special_election': return 'Call Special Election'
    case 'peek': return 'Policy Peek'
    case 'kill': return 'Execution'
    default: return ''
  }
}

/** Description for an executive action */
export function getActionDescription(action: ExecutiveAction | null): string {
  switch (action) {
    case 'investigate':
      return 'The President investigates a player\'s Party Membership card.'
    case 'special_election':
      return 'The President chooses the next Presidential Candidate.'
    case 'peek':
      return 'The President secretly looks at the top 3 policy tiles.'
    case 'kill':
      return 'The President must execute one player.'
    default:
      return ''
  }
}
