/**
 * Secret Hitler, by Mike Boxleiter, Tommy Maranges and Max Temkin
 * (secrethitler.com), adapted under CC BY-NC-SA 4.0. Rules follow the
 * published rulebook: 5–10 players, 6 Liberal + 11 Fascist policies,
 * term limits, election tracker, presidential powers by player count, veto
 * after five Fascist policies.
 *
 * Talking happens out loud (or on the video call). The only extra here is
 * "claims": after a government, its President and Chancellor can say what
 * cards they saw, which gives computer players something to reason about.
 */
import type { GameModule, PlayerId, RuleContext, RuleResult } from '@/lib/engine/types'
import { secretHitlerBot } from './bot'

export type Policy = 'L' | 'F'
export type Role = 'liberal' | 'fascist' | 'hitler'
export type Party = 'liberal' | 'fascist'
export type Power = 'investigate' | 'peek' | 'special' | 'execute'
export type Phase = 'nominate' | 'vote' | 'president' | 'chancellor' | 'veto' | 'power' | 'over'

export const ROLE_COUNTS: Record<number, { liberal: number; fascist: number }> = {
  5: { liberal: 3, fascist: 1 },
  6: { liberal: 4, fascist: 1 },
  7: { liberal: 4, fascist: 2 },
  8: { liberal: 5, fascist: 2 },
  9: { liberal: 5, fascist: 3 },
  10: { liberal: 6, fascist: 3 },
}

/** Power granted when the Nth Fascist policy (index N-1) is enacted. */
export function fascistTrack(players: number): (Power | null)[] {
  if (players <= 6) return [null, null, 'peek', 'execute', 'execute', null]
  if (players <= 8) return [null, 'investigate', 'special', 'execute', 'execute', null]
  return ['investigate', 'investigate', 'special', 'execute', 'execute', null]
}

export interface Election {
  president: PlayerId
  chancellor: PlayerId
  votes: Record<PlayerId, boolean>
  passed: boolean
}

export interface Government {
  id: number
  president: PlayerId
  chancellor: PlayerId
  /** What became law: a policy, or 'veto'. */
  enacted: Policy | 'veto' | null
  /** Claimed Fascist cards: President of the 3 drawn, Chancellor of the 2 received. */
  presClaim: number | null
  chanClaim: number | null
}

export type LogEntry =
  | { kind: 'election'; e: Election; tracker: number }
  | { kind: 'gov'; govId: number }
  | { kind: 'chaos'; policy: Policy }
  | { kind: 'power'; power: Power; president: PlayerId; target: PlayerId | null }
  | { kind: 'claimInvestigation'; president: PlayerId; target: PlayerId; party: Party }
  | { kind: 'reshuffle' }

export type Note =
  | { kind: 'investigation'; target: PlayerId; party: Party }
  | { kind: 'peek'; cards: Policy[] }
  | { kind: 'drew'; govId: number; cards: Policy[]; passed: Policy[] }
  | { kind: 'received'; govId: number; cards: Policy[]; enacted: Policy | null }

export interface SHState {
  seats: PlayerId[]
  roles: Record<PlayerId, Role>
  dead: PlayerId[]
  deck: Policy[]
  discard: Policy[]
  liberal: number
  fascist: number
  tracker: number
  phase: Phase
  /** Seat index of the current presidential candidate. */
  presIdx: number
  /** After a special election, the regular order resumes after this seat. */
  resumeIdx: number | null
  president: PlayerId
  nominee: PlayerId | null
  lastPresident: PlayerId | null
  lastChancellor: PlayerId | null
  votes: Record<PlayerId, boolean>
  hand: Policy[]
  vetoAsked: boolean
  power: Power | null
  investigated: PlayerId[]
  notes: Record<PlayerId, Note[]>
  govs: Government[]
  log: LogEntry[]
  winner: Party | null
  winReason: string | null
}

export type SHAction =
  | { type: 'nominate'; target: PlayerId }
  | { type: 'vote'; ja: boolean }
  | { type: 'discard'; index: number }
  | { type: 'enact'; index: number }
  | { type: 'veto' }
  | { type: 'vetoAnswer'; agree: boolean }
  | { type: 'power'; target?: PlayerId }
  | { type: 'claim'; govId: number; fascists: number }
  | { type: 'claimInvestigation'; target: PlayerId; party: Party }

export interface SHView {
  me: PlayerId | null
  myRole: Role | null
  /** Roles this player knows (themselves, plus teammates for Fascists). */
  known: Record<PlayerId, Role>
  seats: PlayerId[]
  dead: PlayerId[]
  phase: Phase
  president: PlayerId
  nominee: PlayerId | null
  lastPresident: PlayerId | null
  lastChancellor: PlayerId | null
  /** Who could be nominated right now. */
  eligible: PlayerId[]
  voted: PlayerId[]
  myVote: boolean | null
  liberal: number
  fascist: number
  tracker: number
  deckCount: number
  discardCount: number
  track: (Power | null)[]
  /** Cards in this player's hand right now (President or Chancellor). */
  hand: Policy[] | null
  vetoUnlocked: boolean
  vetoAsked: boolean
  power: Power | null
  powerTargets: PlayerId[]
  investigated: PlayerId[]
  notes: Note[]
  govs: Government[]
  log: LogEntry[]
  winner: Party | null
  winReason: string | null
  /** Everyone's role, once the game is over. */
  roles: Record<PlayerId, Role> | null
}

// ---------------------------------------------------------------------------

export function partyOf(role: Role): Party {
  return role === 'liberal' ? 'liberal' : 'fascist'
}

function shuffle<T>(items: T[], random: () => number): T[] {
  const a = [...items]
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1))
    ;[a[i], a[j]] = [a[j]!, a[i]!]
  }
  return a
}

const alive = (s: SHState, id: PlayerId) => s.seats.includes(id) && !s.dead.includes(id)
const living = (s: SHState) => s.seats.filter((id) => !s.dead.includes(id))

function eligibleChancellors(s: SHState): PlayerId[] {
  const many = living(s).length > 5
  return living(s).filter(
    (id) => id !== s.president && id !== s.lastChancellor && !(many && id === s.lastPresident),
  )
}

function powerTargets(s: SHState): PlayerId[] {
  if (s.phase !== 'power') return []
  const others = living(s).filter((id) => id !== s.president)
  if (s.power === 'investigate') return others.filter((id) => !s.investigated.includes(id))
  if (s.power === 'peek') return []
  return others
}

/** Make sure at least `n` cards can be drawn, reshuffling the discard pile in if needed. */
function ensure(s: SHState, n: number, ctx: RuleContext) {
  if (s.deck.length >= n) return
  s.deck = shuffle([...s.deck, ...s.discard], ctx.random)
  s.discard = []
  s.log.push({ kind: 'reshuffle' })
}

function win(s: SHState, party: Party, reason: string) {
  s.phase = 'over'
  s.winner = party
  s.winReason = reason
  s.nominee = null
  s.hand = []
}

function nextPresident(s: SHState) {
  let idx = s.resumeIdx ?? s.presIdx
  s.resumeIdx = null
  for (let i = 0; i < s.seats.length; i++) {
    idx = (idx + 1) % s.seats.length
    if (!s.dead.includes(s.seats[idx]!)) break
  }
  s.presIdx = idx
  s.president = s.seats[idx]!
  s.nominee = null
  s.votes = {}
  s.hand = []
  s.vetoAsked = false
  s.power = null
  s.phase = 'nominate'
}

/** Put a policy on the board. Returns the power it grants, if any. */
function place(s: SHState, p: Policy): Power | null {
  s.tracker = 0
  if (p === 'L') {
    s.liberal++
    if (s.liberal >= 5) win(s, 'liberal', 'Five Liberal policies were enacted.')
    return null
  }
  s.fascist++
  if (s.fascist >= 6) {
    win(s, 'fascist', 'Six Fascist policies were enacted.')
    return null
  }
  return fascistTrack(s.seats.length)[s.fascist - 1] ?? null
}

function failedElection(s: SHState, ctx: RuleContext) {
  s.tracker++
  if (s.tracker < 3) return nextPresident(s)
  // Chaos: the top policy is enacted, its power ignored, and term limits reset.
  ensure(s, 1, ctx)
  const top = s.deck.shift()!
  s.log.push({ kind: 'chaos', policy: top })
  place(s, top)
  s.tracker = 0
  s.lastPresident = null
  s.lastChancellor = null
  ensure(s, 3, ctx)
  if (s.phase !== 'over') nextPresident(s)
}

function afterEnact(s: SHState, policy: Policy, ctx: RuleContext) {
  const gov = s.govs[s.govs.length - 1]!
  gov.enacted = policy
  const power = place(s, policy)
  ensure(s, 3, ctx)
  if (s.phase === 'over') return
  if (power) {
    s.power = power
    s.phase = 'power'
    s.hand = []
    if (power === 'peek') {
      s.notes[s.president]!.push({ kind: 'peek', cards: s.deck.slice(0, 3) })
    }
  } else nextPresident(s)
}

/** Count the vote once every living player has voted. */
function resolveVote(s: SHState, ctx: RuleContext) {
  const voters = living(s)
  if (s.phase !== 'vote' || !voters.every((id) => id in s.votes)) return
  const ja = voters.filter((id) => s.votes[id]).length
  const passed = ja > voters.length / 2
  const e: Election = { president: s.president, chancellor: s.nominee!, votes: { ...s.votes }, passed }
  s.log.push({ kind: 'election', e, tracker: passed ? s.tracker : s.tracker + 1 })
  if (!passed) return failedElection(s, ctx)
  s.lastPresident = s.president
  s.lastChancellor = s.nominee
  if (s.fascist >= 3 && s.roles[s.nominee!] === 'hitler') {
    return win(s, 'fascist', 'Hitler was elected Chancellor after three Fascist policies.')
  }
  ensure(s, 3, ctx)
  s.hand = s.deck.splice(0, 3)
  const id = s.govs.length + 1
  s.govs.push({ id, president: s.president, chancellor: s.nominee!, enacted: null, presClaim: null, chanClaim: null })
  s.log.push({ kind: 'gov', govId: id })
  s.phase = 'president'
}

function rolesFor(n: number, random: () => number): Role[] {
  const c = ROLE_COUNTS[n]!
  return shuffle(
    [...Array<Role>(c.liberal).fill('liberal'), ...Array<Role>(c.fascist).fill('fascist'), 'hitler' as Role],
    random,
  )
}

export function setupGame(players: PlayerId[], ctx: RuleContext): SHState {
  const roles = rolesFor(players.length, ctx.random)
  const presIdx = Math.floor(ctx.random() * players.length)
  return {
    seats: [...players],
    roles: Object.fromEntries(players.map((id, i) => [id, roles[i]!])),
    dead: [],
    deck: shuffle([...Array<Policy>(6).fill('L'), ...Array<Policy>(11).fill('F')], ctx.random),
    discard: [],
    liberal: 0,
    fascist: 0,
    tracker: 0,
    phase: 'nominate',
    presIdx,
    resumeIdx: null,
    president: players[presIdx]!,
    nominee: null,
    lastPresident: null,
    lastChancellor: null,
    votes: {},
    hand: [],
    vetoAsked: false,
    power: null,
    investigated: [],
    notes: Object.fromEntries(players.map((id) => [id, []])),
    govs: [],
    log: [],
    winner: null,
    winReason: null,
  }
}

function act(s0: SHState, pid: PlayerId, a: SHAction, ctx: RuleContext): RuleResult<SHState> {
  if (s0.phase === 'over') return { error: 'The game is over.' }
  if (!s0.seats.includes(pid)) return { error: "You're watching this game." }
  if (!a || typeof a !== 'object') return { error: 'Unknown action.' }
  if (!alive(s0, pid)) return { error: 'Executed players can no longer act.' }
  const s: SHState = structuredClone(s0)

  switch (a.type) {
    case 'nominate': {
      if (s.phase !== 'nominate') return { error: 'Not the time to nominate.' }
      if (pid !== s.president) return { error: 'Only the presidential candidate nominates.' }
      if (!eligibleChancellors(s).includes(a.target)) return { error: "That player can't be Chancellor this round." }
      s.nominee = a.target
      s.votes = {}
      s.phase = 'vote'
      return { state: s }
    }
    case 'vote': {
      if (s.phase !== 'vote') return { error: 'There is no vote right now.' }
      if (typeof a.ja !== 'boolean') return { error: 'Vote Ja or Nein.' }
      s.votes[pid] = a.ja
      resolveVote(s, ctx)
      return { state: s }
    }
    case 'discard': {
      if (s.phase !== 'president') return { error: 'Not the time to discard.' }
      if (pid !== s.president) return { error: 'Only the President discards now.' }
      if (!Number.isInteger(a.index) || !s.hand[a.index]) return { error: 'Pick a card.' }
      const drawn = [...s.hand]
      s.discard.push(s.hand.splice(a.index, 1)[0]!)
      const govId = s.govs[s.govs.length - 1]!.id
      s.notes[pid]!.push({ kind: 'drew', govId, cards: drawn, passed: [...s.hand] })
      s.phase = 'chancellor'
      return { state: s }
    }
    case 'enact': {
      if (s.phase !== 'chancellor') return { error: 'Not the time to enact.' }
      if (pid !== s.nominee) return { error: 'Only the Chancellor enacts.' }
      if (!Number.isInteger(a.index) || !s.hand[a.index]) return { error: 'Pick a card.' }
      const got = [...s.hand]
      const [policy] = s.hand.splice(a.index, 1)
      s.discard.push(...s.hand)
      s.hand = []
      s.notes[pid]!.push({ kind: 'received', govId: s.govs[s.govs.length - 1]!.id, cards: got, enacted: policy! })
      afterEnact(s, policy!, ctx)
      return { state: s }
    }
    case 'veto': {
      if (s.phase !== 'chancellor' || pid !== s.nominee) return { error: 'Only the Chancellor can ask for a veto.' }
      if (s.fascist < 5) return { error: 'Veto unlocks after five Fascist policies.' }
      if (s.vetoAsked) return { error: 'The President already refused a veto.' }
      s.vetoAsked = true
      s.phase = 'veto'
      return { state: s }
    }
    case 'vetoAnswer': {
      if (s.phase !== 'veto' || pid !== s.president) return { error: 'Only the President answers the veto.' }
      if (!a.agree) {
        s.phase = 'chancellor'
        return { state: s }
      }
      const gov = s.govs[s.govs.length - 1]!
      gov.enacted = 'veto'
      s.notes[s.nominee!]!.push({ kind: 'received', govId: gov.id, cards: [...s.hand], enacted: null })
      s.discard.push(...s.hand)
      s.hand = []
      ensure(s, 3, ctx)
      failedElection(s, ctx)
      return { state: s }
    }
    case 'power': {
      if (s.phase !== 'power' || pid !== s.president) return { error: 'Only the President uses this power.' }
      const power = s.power!
      if (power === 'peek') {
        s.log.push({ kind: 'power', power, president: pid, target: null })
        nextPresident(s)
        return { state: s }
      }
      const target = a.target
      if (!target || !powerTargets(s).includes(target)) return { error: "You can't pick that player." }
      s.log.push({ kind: 'power', power, president: pid, target })
      if (power === 'investigate') {
        s.investigated.push(target)
        s.notes[pid]!.push({ kind: 'investigation', target, party: partyOf(s.roles[target]!) })
        nextPresident(s)
      } else if (power === 'special') {
        const callerIdx = s.presIdx
        nextPresident(s)
        // nextPresident moved on one seat; override with the chosen player.
        s.resumeIdx = callerIdx
        s.presIdx = s.seats.indexOf(target)
        s.president = target
      } else {
        s.dead.push(target)
        if (s.roles[target] === 'hitler') win(s, 'liberal', 'Hitler was executed.')
        else nextPresident(s)
      }
      return { state: s }
    }
    case 'claim': {
      const gov = s.govs.find((g) => g.id === a.govId)
      if (!gov || !gov.enacted) return { error: 'Nothing to claim for that government.' }
      const n = a.fascists
      if (pid === gov.president) {
        if (!Number.isInteger(n) || n < 0 || n > 3) return { error: 'Claim 0–3 Fascist cards.' }
        gov.presClaim = n
      } else if (pid === gov.chancellor) {
        if (!Number.isInteger(n) || n < 0 || n > 2) return { error: 'Claim 0–2 Fascist cards.' }
        gov.chanClaim = n
      } else return { error: "You weren't in that government." }
      return { state: s }
    }
    case 'claimInvestigation': {
      const did = s.log.some((e) => e.kind === 'power' && e.power === 'investigate' && e.president === pid && e.target === a.target)
      if (!did) return { error: "You didn't investigate that player." }
      if (a.party !== 'liberal' && a.party !== 'fascist') return { error: 'Say Liberal or Fascist.' }
      if (s.log.some((e) => e.kind === 'claimInvestigation' && e.president === pid && e.target === a.target)) {
        return { error: 'You already said.' }
      }
      s.log.push({ kind: 'claimInvestigation', president: pid, target: a.target, party: a.party })
      return { state: s }
    }
    default:
      return { error: 'Unknown action.' }
  }
}

export function viewFor(s: SHState, pid: PlayerId | null): SHView {
  const seated = pid !== null && s.seats.includes(pid)
  const myRole = seated ? s.roles[pid]! : null
  const known: Record<PlayerId, Role> = {}
  if (seated) {
    known[pid] = myRole!
    const fascistsKnowAll = myRole === 'fascist' || (myRole === 'hitler' && s.seats.length <= 6)
    if (fascistsKnowAll) for (const id of s.seats) if (s.roles[id] !== 'liberal') known[id] = s.roles[id]!
  }
  const over = s.phase === 'over'
  const holding =
    (s.phase === 'president' && pid === s.president) || ((s.phase === 'chancellor' || s.phase === 'veto') && pid === s.nominee)
  return {
    me: seated ? pid : null,
    myRole,
    known: over ? { ...s.roles } : known,
    seats: s.seats,
    dead: s.dead,
    phase: s.phase,
    president: s.president,
    nominee: s.nominee,
    lastPresident: s.lastPresident,
    lastChancellor: s.lastChancellor,
    eligible: s.phase === 'nominate' ? eligibleChancellors(s) : [],
    voted: s.phase === 'vote' ? Object.keys(s.votes) : [],
    myVote: s.phase === 'vote' && seated && pid in s.votes ? s.votes[pid]! : null,
    liberal: s.liberal,
    fascist: s.fascist,
    tracker: s.tracker,
    deckCount: s.deck.length,
    discardCount: s.discard.length,
    track: fascistTrack(s.seats.length),
    hand: holding ? [...s.hand] : null,
    vetoUnlocked: s.fascist >= 5,
    vetoAsked: s.vetoAsked,
    power: s.power,
    powerTargets: powerTargets(s),
    investigated: s.investigated,
    notes: seated ? s.notes[pid] ?? [] : [],
    govs: s.govs,
    log: s.log,
    winner: s.winner,
    winReason: s.winReason,
    roles: over ? { ...s.roles } : null,
  }
}

export const secretHitler: GameModule<SHState, SHAction, SHView> = {
  id: 'secrethitler',
  name: 'Secret Hitler',
  description:
    'Liberals try to pass five Liberal policies or find and stop Hitler. The Fascists, who know each other, try to sneak Hitler into power.',
  minPlayers: 5,
  maxPlayers: 10,
  botDelayMs: 1300,
  setup: setupGame,
  action: act,
  view: viewFor,
  isOver: (s) => s.phase === 'over',
  playerLeft(s0, pid, ctx) {
    if (!s0.seats.includes(pid) || s0.phase === 'over') return s0
    const s: SHState = structuredClone(s0)
    if (s.roles[pid] === 'hitler') {
      s.phase = 'over'
      s.winner = null
      s.winReason = 'Hitler left the game.'
      return s
    }
    if (!s.dead.includes(pid)) s.dead.push(pid)
    // Anyone who leaves mid-government ends that government.
    if (pid === s.president || (pid === s.nominee && s.phase !== 'nominate')) {
      s.discard.push(...s.hand)
      nextPresident(s)
    } else if (s.phase === 'vote') {
      delete s.votes[pid]
      resolveVote(s, ctx)
    }
    return s
  },
  bot: secretHitlerBot,
}
