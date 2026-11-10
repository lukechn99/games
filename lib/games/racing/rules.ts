import type { GameModule, PlayerId, RuleResult } from '@/lib/engine/types'

/**
 * Animal Karts (docs/racing/DESIGN.md, section 13).
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
  { id: 'frost', name: 'Frosty Pass' },
] as const
export type TrackId = (typeof TRACKS)[number]['id']

/** A Grand Prix runs every track in turn, with points for each finish. */
export const GP_TRACKS: TrackId[] = ['meadow', 'mine', 'frost']
/** Points for 1st, 2nd, 3rd... (as in Mario Kart); nothing for not finishing. */
export const GP_POINTS = [15, 12, 10, 8, 6, 4, 2, 1]

export interface CupResult {
  track: TrackId
  finish: Record<PlayerId, number>
  places: Record<PlayerId, number>
  points: Record<PlayerId, number>
  laps: Record<PlayerId, number[]>
}

export interface Cup {
  tracks: TrackId[]
  /** Which race of the cup this is (0-based). */
  race: number
  /** Points so far, per racer. */
  points: Record<PlayerId, number>
  /** Points each racer got in the last finished race. */
  last: Record<PlayerId, number>
  /** Completed races, retained when moving to the next track. */
  results: CupResult[]
}

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
  lapTimes: Record<PlayerId, number[]>
  /** When the first racer finished: everyone else gets a little longer. */
  firstFinishAt: number | null
  /** A Grand Prix in progress, or null for a single race. */
  cup: Cup | null
}

export type RacingAction =
  | { type: 'track'; id: TrackId | 'gp' }
  | { type: 'next' }
  | { type: 'pick'; chassis: string; tires: string; driver: string; bot?: boolean }
  | { type: 'ready' }
  | { type: 'finish'; time: number; who?: PlayerId; laps?: number[] }

export type RacingView = RacingState & { me: PlayerId | null }

const CHASSIS = ['frame', 'soapbox', 'hauler', 'racer']
const TIRES = ['slicks', 'knobby', 'balloon', 'studded']
const DRIVERS = ['fox', 'frog', 'rhino', 'deer']

const COUNTDOWN_MS = 11500   // 8 s fly-in round the map, then 3, 2, 1
/** After the first racer finishes, how long the others get before results. */
const FINISH_GRACE_MS = 30000

function allReady(s: RacingState) {
  return s.seats.every((id) => s.picks[id]?.ready)
}

/** The race is over: in a Grand Prix, hand out the points. */
function done(s: RacingState): RacingState {
  if (s.phase === 'done') return s
  if (!s.cup) return { ...s, phase: 'done' }
  const order = Object.keys(s.finish).sort((a, b) => s.finish[a]! - s.finish[b]!)
  const last: Record<PlayerId, number> = {}
  const points = { ...s.cup.points }
  const places: Record<PlayerId, number> = {}
  for (const id of s.seats) {
    const place = order.indexOf(id)
    const got = place >= 0 ? GP_POINTS[place] ?? 0 : 0
    last[id] = got
    points[id] = (points[id] ?? 0) + got
    if (place >= 0) places[id] = place + 1
  }
  const result: CupResult = {
    track: s.track, finish: { ...s.finish }, places, points: { ...last },
    laps: Object.fromEntries(Object.entries(s.lapTimes ?? {}).map(([id, laps]) => [id, [...laps]])),
  }
  return { ...s, phase: 'done', cup: { ...s.cup, points, last, results: [...(s.cup.results ?? []), result] } }
}

export const racing: GameModule<RacingState, RacingAction, RacingView> = {
  id: 'racing',
  name: 'Animal Karts',
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
    return { phase: 'track', track: 'meadow', laps: 3, seats: [...players], picks, startAt: null, finish: {}, lapTimes: {}, firstFinishAt: null, cup: null }
  },

  action(s, pid, a, ctx): RuleResult<RacingState> {
    if (!s.seats.includes(pid)) return { error: "You're watching this race." }
    switch (a?.type) {
      case 'track': {
        // Picked before anyone builds a kart. The page offers it to the room's
        // host; the rules only check it comes from someone in the race.
        if (s.phase !== 'track') return { error: 'The track is already picked.' }
        if (!s.seats.includes(pid)) return { error: 'Only racers can pick the track.' }
        if (a.id === 'gp') {
          const points: Record<PlayerId, number> = {}
          for (const id of s.seats) points[id] = 0
          return { state: { ...s, track: GP_TRACKS[0]!, phase: 'pick', cup: { tracks: GP_TRACKS, race: 0, points, last: {}, results: [] } } }
        }
        if (!TRACKS.some((t) => t.id === a.id)) return { error: 'Unknown track.' }
        return { state: { ...s, track: a.id, phase: 'pick', cup: null } }
      }
      case 'next': {
        // The next race of a Grand Prix: back to the kart builder (builds
        // kept, everyone readies up again), on the next track.
        if (s.phase !== 'done' || !s.cup) return { error: 'No next race.' }
        if (s.cup.race + 1 >= s.cup.tracks.length) return { error: 'That was the last race.' }
        const race = s.cup.race + 1
        const picks: Record<PlayerId, Pick> = {}
        for (const id of s.seats) picks[id] = { ...s.picks[id]!, ready: false }
        return {
          state: { ...s, phase: 'pick', track: s.cup.tracks[race]!, picks, startAt: null, finish: {}, lapTimes: {}, firstFinishAt: null, cup: { ...s.cup, race, last: {} } },
        }
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
        if (a.laps !== undefined && (!Array.isArray(a.laps) || a.laps.length !== s.laps ||
          a.laps.some(t => typeof t !== 'number' || !Number.isFinite(t) || t <= 0) ||
          Math.abs(a.laps.reduce((total, t) => total + t, 0) - a.time) > 0.05)) return { error: 'Bad lap times.' }
        const finish = { ...s.finish, [who]: Math.round(a.time * 1000) / 1000 }
        const lapTimes = { ...(s.lapTimes ?? {}) }
        if (a.laps) lapTimes[who] = a.laps.map(t => Math.round(t * 1000) / 1000)
        const next = { ...s, finish, lapTimes, firstFinishAt: s.firstFinishAt ?? ctx.now }
        if (next.seats.every((id) => next.finish[id] !== undefined)) return { state: done(next) }
        return { state: next }
      }
      default:
        return { error: 'Unknown action.' }
    }
  },

  tick(s, ctx) {
    if (s.phase === 'race' && s.firstFinishAt !== null && ctx.now - s.firstFinishAt > FINISH_GRACE_MS) {
      return done(s)
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
    if (next.phase === 'race' && seats.every((id) => next.finish[id] !== undefined)) return done(next)
    return next
  },

  // (Between Grand Prix races the cup isn't over: computer drivers still
  // need to ready up for the next one.)
  isOver: (s) => s.phase === 'done' && (!s.cup || s.cup.race + 1 >= s.cup.tracks.length),

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
