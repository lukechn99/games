/**
 * Computer players for Secret Hitler. A bot sees exactly its seat's view:
 * the public record (governments, votes, claims) plus its own cards,
 * investigations and, for Fascists, who its teammates are.
 *
 * Liberals keep a suspicion score for everyone and steer away from the
 * worst. Fascists hide among them: they push Fascist policies, cover with
 * plausible claims, and try to get Hitler elected once three Fascist
 * policies are down. Hitler plays like a Liberal to stay trusted.
 */
import type { BotLevel, PlayerId, RuleContext } from '@/lib/engine/types'
import type { Government, Note, Policy, SHAction, SHView } from './rules'

const NOISE: Record<BotLevel, number> = { easy: 1.6, medium: 0.5, hard: 0.15 }
const countF = (cards: Policy[]) => cards.filter((c) => c === 'F').length

/** Higher means more likely Fascist. `notes` = this seat's private knowledge (omit for the public view). */
export function suspicion(v: SHView, notes: Note[] = v.notes): Map<PlayerId, number> {
  const s = new Map<PlayerId, number>(v.seats.map((id) => [id, 0]))
  const add = (id: PlayerId, n: number) => s.set(id, (s.get(id) ?? 0) + n)

  for (const g of v.govs) {
    if (g.enacted === 'F') {
      add(g.president, 1)
      add(g.chancellor, 1.3)
      if (g.chanClaim !== null && g.chanClaim < 2) add(g.chancellor, 3) // admits an L was in hand
    } else if (g.enacted === 'L') {
      add(g.president, -0.8)
      add(g.chancellor, -0.8)
      if (g.presClaim === 3) add(g.president, 3)
      if (g.chanClaim === 2) add(g.chancellor, 3)
    }
    if (g.presClaim !== null && g.chanClaim !== null && g.chanClaim !== Math.max(0, g.presClaim - 1)) {
      add(g.president, 1.5)
      add(g.chancellor, 1.5)
    }
  }

  // Votes for governments that went on to pass a Fascist policy.
  let pending: Government | undefined
  for (const e of v.log) {
    if (e.kind !== 'election' || !e.e.passed) continue
    pending = v.govs.find((g) => g.president === e.e.president && g.chancellor === e.e.chancellor && g.enacted)
    if (!pending) continue
    for (const [id, ja] of Object.entries(e.e.votes)) {
      if (!ja || id === e.e.president || id === e.e.chancellor) continue
      add(id, pending.enacted === 'F' ? 0.25 : pending.enacted === 'L' ? -0.15 : 0)
    }
  }

  // Private knowledge.
  const truth = new Map<PlayerId, 'liberal' | 'fascist'>()
  for (const n of notes) {
    if (n.kind === 'investigation') {
      truth.set(n.target, n.party)
      add(n.target, n.party === 'fascist' ? 10 : -10)
    }
    const g = 'govId' in n ? v.govs.find((x) => x.id === n.govId) : undefined
    if (!g) continue
    if (n.kind === 'drew') {
      // I was President: I know what the Chancellor really got.
      if (n.passed.includes('L') && g.enacted === 'F') add(g.chancellor, 5)
      if (g.chanClaim !== null && g.chanClaim !== countF(n.passed)) add(g.chancellor, 3)
    } else if (n.kind === 'received') {
      // I was Chancellor: I know what the President really passed.
      const got = countF(n.cards)
      if (g.presClaim !== null && Math.max(0, g.presClaim - 1) !== got) add(g.president, 4)
      if (got === 2 && g.presClaim === null) add(g.president, 1)
    }
  }

  for (const e of v.log) {
    if (e.kind !== 'claimInvestigation') continue
    const known = truth.get(e.target)
    if (known && known !== e.party) add(e.president, 6)
    else if ((s.get(e.president) ?? 0) < 1.5) add(e.target, e.party === 'fascist' ? 2.5 : -1.5)
  }

  for (const [id, role] of Object.entries(v.known)) s.set(id, role === 'liberal' ? -50 : 50)
  if (v.me) s.set(v.me, -100)
  return s
}

function pickBy(ids: PlayerId[], score: (id: PlayerId) => number, ctx: RuleContext, level: BotLevel, lowest: boolean) {
  let best: PlayerId | null = null
  let bestScore = Infinity
  for (const id of ids) {
    const n = (lowest ? score(id) : -score(id)) + (ctx.random() - 0.5) * NOISE[level] * 2
    if (n < bestScore) {
      bestScore = n
      best = id
    }
  }
  return best
}

function claimFor(v: SHView, g: Government, teamFascist: boolean): number {
  const me = v.me!
  if (me === g.president) {
    const n = v.notes.find((x): x is Extract<Note, { kind: 'drew' }> => x.kind === 'drew' && x.govId === g.id)
    if (!n) return 1
    if (!teamFascist) return countF(n.cards)
    // A Fascist President claims as if they'd discarded a Fascist card.
    return countF(n.cards) === 0 ? 0 : Math.min(3, countF(n.passed) + 1)
  }
  const n = v.notes.find((x): x is Extract<Note, { kind: 'received' }> => x.kind === 'received' && x.govId === g.id)
  if (!n) return 1
  if (teamFascist && g.enacted === 'F' && n.cards.includes('L')) return 2
  return countF(n.cards)
}

export function secretHitlerBot(v: SHView, ctx: RuleContext, level: BotLevel, attempt: number): SHAction | null {
  const me = v.me
  if (!me || v.phase === 'over' || v.dead.includes(me)) return null
  const role = v.myRole!
  // Fascists, and Hitler when he knows his team, play as a team.
  const knowsTeam = role === 'fascist' || (role === 'hitler' && Object.keys(v.known).length > 1)
  const fascistMind = role === 'fascist'
  const team = new Set(Object.keys(v.known).filter((id) => v.known[id] !== 'liberal'))
  const hitler = Object.keys(v.known).find((id) => v.known[id] === 'hitler') ?? null
  const r = ctx.random

  // Fallback after a rejection: the simplest legal move.
  if (attempt > 0) {
    if (attempt > 1) return null
    if (v.phase === 'vote' && v.myVote === null && !v.voted.includes(me)) return { type: 'vote', ja: true }
    if (v.phase === 'nominate' && v.president === me && v.eligible[0]) return { type: 'nominate', target: v.eligible[0] }
    if (v.phase === 'president' && v.president === me) return { type: 'discard', index: 0 }
    if (v.phase === 'chancellor' && v.nominee === me) return { type: 'enact', index: 0 }
    if (v.phase === 'veto' && v.president === me) return { type: 'vetoAnswer', agree: false }
    if (v.phase === 'power' && v.president === me) return { type: 'power', target: v.powerTargets[0] }
    return null
  }

  // Say what we saw, as soon as a government we were in finishes.
  for (const g of v.govs) {
    if (!g.enacted) continue
    if ((g.president === me && g.presClaim === null) || (g.chancellor === me && g.chanClaim === null)) {
      return { type: 'claim', govId: g.id, fascists: claimFor(v, g, fascistMind) }
    }
  }
  for (const n of v.notes) {
    if (n.kind !== 'investigation') continue
    const said = v.log.some((e) => e.kind === 'claimInvestigation' && e.president === me && e.target === n.target)
    if (said) continue
    let party = n.party
    if (fascistMind && n.party === 'liberal' && r() < (level === 'hard' ? 0.45 : 0.25)) party = 'fascist' // frame them
    if (fascistMind && team.has(n.target)) party = 'liberal'
    return { type: 'claimInvestigation', target: n.target, party }
  }

  const sus = suspicion(v)
  const pub = suspicion(v, []) // what the table can see
  const S = (id: PlayerId) => sus.get(id) ?? 0
  const P = (id: PlayerId) => pub.get(id) ?? 0

  switch (v.phase) {
    case 'nominate': {
      if (v.president !== me) return null
      if (knowsTeam) {
        if (v.fascist >= 3 && hitler && v.eligible.includes(hitler) && (level !== 'easy' || r() < 0.5)) {
          return { type: 'nominate', target: hitler }
        }
        const mates = v.eligible.filter((id) => team.has(id) && id !== hitler && P(id) < 2)
        if (fascistMind && mates.length && r() < (level === 'hard' ? 0.45 : 0.35)) {
          return { type: 'nominate', target: mates[Math.floor(r() * mates.length)]! }
        }
        const libs = v.eligible.filter((id) => !team.has(id))
        const pick = pickBy(libs.length ? libs : v.eligible, P, ctx, level, true)
        return pick ? { type: 'nominate', target: pick } : null
      }
      const pick = pickBy(v.eligible, S, ctx, level, true)
      return pick ? { type: 'nominate', target: pick } : null
    }

    case 'vote': {
      if (v.voted.includes(me)) return null
      const pres = v.president
      const chan = v.nominee!
      if (pres === me || chan === me) return { type: 'vote', ja: true }
      if (level === 'easy' && r() < 0.35) return { type: 'vote', ja: r() < 0.7 }
      if (knowsTeam) {
        if (chan === hitler && v.fascist >= 3) return { type: 'vote', ja: true }
        if (team.has(pres) || team.has(chan)) return { type: 'vote', ja: true }
        // Blend in: vote like a cautious Liberal would, using only public info.
        const risk = P(pres) + P(chan)
        return { type: 'vote', ja: fascistMind ? risk < 0.6 && r() < 0.6 : risk < 1.5 }
      }
      let threshold = 1.4
      if (v.tracker === 2) threshold += 1.6 // a chaos policy is worse than a risky government
      if (v.fascist >= 3 && S(chan) > 0.6) threshold -= 1 // Hitler could win right now
      const risk = Math.max(S(pres), 0) + Math.max(S(chan), 0) * 1.2
      return { type: 'vote', ja: risk + (r() - 0.5) * NOISE[level] < threshold }
    }

    case 'president': {
      if (v.president !== me || !v.hand) return null
      const hand = v.hand
      const iF = hand.indexOf('F')
      const iL = hand.indexOf('L')
      if (fascistMind) {
        const early = v.fascist <= 1 && v.liberal <= 1
        const trust = early && !team.has(v.nominee!) && r() < (level === 'easy' ? 0.1 : 0.3)
        if (trust && iF >= 0) return { type: 'discard', index: iF }
        return { type: 'discard', index: iL >= 0 ? iL : 0 } // push Fascist cards through
      }
      return { type: 'discard', index: iF >= 0 ? iF : 0 }
    }

    case 'chancellor': {
      if (v.nominee !== me || !v.hand) return null
      const iF = v.hand.indexOf('F')
      const iL = v.hand.indexOf('L')
      if (fascistMind) {
        const early = v.fascist <= 1 && v.liberal <= 1
        if (iL >= 0 && early && r() < 0.2) return { type: 'enact', index: iL }
        return { type: 'enact', index: iF >= 0 ? iF : 0 }
      }
      if (iL < 0 && v.vetoUnlocked && !v.vetoAsked && level !== 'easy') return { type: 'veto' }
      return { type: 'enact', index: iL >= 0 ? iL : 0 }
    }

    case 'veto': {
      if (v.president !== me) return null
      if (fascistMind) return { type: 'vetoAnswer', agree: false }
      const g = v.govs[v.govs.length - 1]
      const drew = v.notes.find((n): n is Extract<Note, { kind: 'drew' }> => n.kind === 'drew' && n.govId === g?.id)
      const passedFF = drew ? countF(drew.passed) === 2 : false
      return { type: 'vetoAnswer', agree: passedFF || S(v.nominee!) < 1 }
    }

    case 'power': {
      if (v.president !== me) return null
      if (v.power === 'peek') return { type: 'power' }
      const targets = v.powerTargets
      if (!targets.length) return { type: 'power' }
      let pick: PlayerId | null
      if (knowsTeam) {
        const libs = targets.filter((id) => !team.has(id))
        const mates = targets.filter((id) => team.has(id))
        if (v.power === 'special') pick = mates.length ? mates[0]! : pickBy(targets, P, ctx, level, true)
        else if (v.power === 'execute') pick = pickBy(libs.length ? libs : targets, P, ctx, level, true) // the most trusted Liberal
        else pick = pickBy(libs.length ? libs : targets, P, ctx, level, true)
      } else if (v.power === 'special') {
        pick = pickBy(targets, S, ctx, level, true)
      } else {
        pick = pickBy(targets, S, ctx, level, false)
      }
      return { type: 'power', target: pick ?? targets[0] }
    }
  }
  return null
}
