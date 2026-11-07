import type { GameModule, PlayerId, RuleResult } from '@/lib/engine/types'

/**
 * Karts & Wheels (docs/racing/DESIGN.md, section 13).
 *
 * The race itself runs in the Godot game, embedded in the room page. These
 * rules only hold what everyone must agree on: the track, each racer's kart,
 * who is ready, when the countdown ends, and the finishing times. Kart
 * positions are too fast for the rules: they go player to player through the
 * room's relay instead.
 */

export const TRACKS = [
  { id: 'meadow', name: 'Meadow Loop' },
  { id: 'mine', name: 'Mining Mountain' },
] as const
export type TrackId = (typeof TRACKS)[number]['id']

export interface Pick {
  chassis: string
  tires: string
  driver: string
  ready: boolean
  /** A computer driver. Its kart is driven by the host's game. */
  bot: boolean
}

export interface RacingState {
  /** 'track': the host picks the track; 'pick': everyone builds a kart. */
  phase: 'track' | 'pick' | 'race' | 'done'
  track: TrackId
  laps: number
  seats: PlayerId[]
  picks: Record<PlayerId, Pick>
  /** Host clock time the lights go green (phase 'race'). */
  startAt: number | null
  /** Race time in seconds, per racer who has finished. */
  finish: Record<PlayerId, number>
  /** When the first racer finished: everyone else gets a little longer. */
  firstFinishAt: number | null
}

export type RacingAction =
  | { type: 'track'; id: TrackId }
  | { type: 'pick'; chassis: string; tires: string; driver: string; bot?: boolean }
  | { type: 'ready' }
  | { type: 'finish'; time: number; who?: PlayerId }

export type RacingView = RacingState & { me: PlayerId | null }

const CHASSIS = ['frame', 'soapbox', 'hauler', 'racer']
const TIRES = ['slicks', 'knobby', 'balloon', 'studded']
const DRIVERS = ['fox', 'frog', 'rhino', 'deer']

const COUNTDOWN_MS = 5000
/** After the first racer finishes, how long the others get before results. */
const FINISH_GRACE_MS = 30000

function allReady(s: RacingState) {
  return s.seats.every((id) => s.picks[id]?.ready)
}

export const racing: GameModule<RacingState, RacingAction, RacingView> = {
  id: 'racing',
  name: 'Karts & Wheels',
  description: 'Build a kart, pick an animal and race your friends round the track. Steer by tilting your phone, or use the buttons.',
  minPlayers: 1,
  maxPlayers: 8,
  botDelayMs: 600,

  setup(players, ctx) {
    const picks: Record<PlayerId, Pick> = {}
    players.forEach((id, i) => {
      picks[id] = { chassis: 'frame', tires: 'slicks', driver: DRIVERS[i % DRIVERS.length]!, ready: false, bot: false }
    })
    void ctx
    return { phase: 'track', track: 'meadow', laps: 3, seats: [...players], picks, startAt: null, finish: {}, firstFinishAt: null }
  },

  action(s, pid, a, ctx): RuleResult<RacingState> {
    if (!s.seats.includes(pid)) return { error: "You're watching this race." }
    switch (a?.type) {
      case 'track': {
        // Picked before anyone builds a kart. The page offers it to the room's
        // host; the rules only check it comes from someone in the race.
        if (s.phase !== 'track') return { error: 'The track is already picked.' }
        if (!s.seats.includes(pid)) return { error: 'Only racers can pick the track.' }
        if (!TRACKS.some((t) => t.id === a.id)) return { error: 'Unknown track.' }
        return { state: { ...s, track: a.id, phase: 'pick' } }
      }
      case 'pick': {
        if (s.phase !== 'pick') return { error: 'The race has started.' }
        if (!CHASSIS.includes(a.chassis) || !TIRES.includes(a.tires) || !DRIVERS.includes(a.driver)) return { error: 'Unknown kart part.' }
        const prev = s.picks[pid]!
        const picks = { ...s.picks, [pid]: { ...prev, chassis: a.chassis, tires: a.tires, driver: a.driver, bot: !!a.bot } }
        return { state: { ...s, picks } }
      }
      case 'ready': {
        if (s.phase !== 'pick') return { state: s }
        const picks = { ...s.picks, [pid]: { ...s.picks[pid]!, ready: true } }
        const next = { ...s, picks }
        if (allReady(next)) return { state: { ...next, phase: 'race', startAt: ctx.now + COUNTDOWN_MS } }
        return { state: next }
      }
      case 'finish': {
        if (s.phase !== 'race') return { state: s }
        // You report your own finish; computer drivers' finishes come from
        // whoever is racing alongside them (the host's game drives them).
        const who = a.who ?? pid
        if (!s.seats.includes(who)) return { error: 'Unknown racer.' }
        if (who !== pid && !s.picks[who]?.bot) return { error: "You can't finish for someone else." }
        if (s.finish[who] !== undefined) return { state: s }
        if (typeof a.time !== 'number' || !(a.time > 0) || a.time > 3600) return { error: 'Bad time.' }
        const finish = { ...s.finish, [who]: Math.round(a.time * 1000) / 1000 }
        const next = { ...s, finish, firstFinishAt: s.firstFinishAt ?? ctx.now }
        if (next.seats.every((id) => next.finish[id] !== undefined)) return { state: { ...next, phase: 'done' } }
        return { state: next }
      }
      default:
        return { error: 'Unknown action.' }
    }
  },

  tick(s, ctx) {
    if (s.phase === 'race' && s.firstFinishAt !== null && ctx.now - s.firstFinishAt > FINISH_GRACE_MS) {
      return { ...s, phase: 'done' }
    }
    return s
  },

  playerLeft(s, pid) {
    if (!s.seats.includes(pid)) return s
    const seats = s.seats.filter((id) => id !== pid)
    const picks = { ...s.picks }
    delete picks[pid]
    const next = { ...s, seats, picks }
    if (next.phase === 'pick' && seats.length > 0 && allReady(next)) return { ...next, phase: 'race' }
    if (next.phase === 'race' && seats.every((id) => next.finish[id] !== undefined)) return { ...next, phase: 'done' }
    return next
  },

  isOver: (s) => s.phase === 'done',

  view: (s, pid) => ({ ...s, me: pid }),

  /** Computer drivers pick a random kart and are ready at once. */
  bot(view, ctx) {
    const me = view.me
    if (!me || view.phase !== 'pick') return null
    const p = view.picks[me]
    if (!p) return null
    if (!p.bot) {
      const r = (list: string[]) => list[Math.floor(ctx.random() * list.length)]!
      return { type: 'pick', chassis: r(CHASSIS), tires: r(TIRES), driver: p.driver, bot: true }
    }
    if (!p.ready) return { type: 'ready' }
    return null
  },
}
