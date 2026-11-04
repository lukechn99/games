'use client'

import { Bird, Check, Crosshair, Eye, EyeOff, Search, Skull, Vote, X } from 'lucide-react'
import { useState, type CSSProperties, type ReactNode } from 'react'
import type { GameViewProps } from '@/lib/games/ui'
import type { PlayerId } from '@/lib/engine/types'
import type { Government, LogEntry, Note, Policy, Power, Role, SHAction, SHView as View } from './rules'

// Period-poster palette: aged paper, ink, and the two parties.
const PAPER: CSSProperties = {
  ['--sh-paper' as string]: '#efe3c8',
  ['--sh-paper-2' as string]: '#e4d3b0',
  ['--sh-ink' as string]: '#2b211b',
  ['--sh-ink-2' as string]: '#6b5a4a',
  ['--sh-lib' as string]: '#2e6e8e',
  ['--sh-lib-pale' as string]: '#cfe1e6',
  ['--sh-fas' as string]: '#b8402c',
  ['--sh-fas-pale' as string]: '#f0cdbf',
  ['--sh-hit' as string]: '#7c1d12',
}

const ROLE_NAME: Record<Role, string> = { liberal: 'Liberal', fascist: 'Fascist', hitler: 'Hitler' }
const POWER_ICON: Record<Power, typeof Eye> = { investigate: Search, peek: Eye, special: Vote, execute: Crosshair }
const POWER_TEXT: Record<Power, string> = {
  investigate: 'President investigates a player’s party',
  peek: 'President sees the top three policies',
  special: 'President picks the next presidential candidate',
  execute: 'President executes a player',
}

function Card({ p, size = 'md', onClick, label }: { p: Policy; size?: 'sm' | 'md'; onClick?: () => void; label?: string }) {
  const lib = p === 'L'
  const Icon = lib ? Bird : Skull
  const dims = size === 'sm' ? 'h-14 w-10 text-[9px]' : 'h-32 w-[5.5rem] text-xs'
  const body = (
    <span
      className={`flex ${dims} flex-col items-center justify-center gap-1 rounded-md border-2 font-display font-bold tracking-wide shadow-sm`}
      style={{
        background: lib ? 'var(--sh-lib-pale)' : 'var(--sh-fas-pale)',
        color: lib ? 'var(--sh-lib)' : 'var(--sh-fas)',
        borderColor: lib ? 'var(--sh-lib)' : 'var(--sh-fas)',
      }}
    >
      <Icon className={size === 'sm' ? 'size-4' : 'size-8'} aria-hidden="true" />
      {lib ? 'Liberal' : 'Fascist'}
    </span>
  )
  if (!onClick) return body
  return (
    <button type="button" onClick={onClick} aria-label={label} className="rounded-md transition-transform hover:-translate-y-1 focus-visible:-translate-y-1">
      {body}
    </button>
  )
}

function Track({ view }: { view: View }) {
  return (
    <section aria-label="Policy boards" className="flex flex-col gap-3">
      <div className="rounded-lg border-2 p-2.5" style={{ borderColor: 'var(--sh-lib)', background: 'var(--sh-lib-pale)' }}>
        <div className="mb-1.5 flex items-baseline justify-between font-display text-sm font-bold" style={{ color: 'var(--sh-lib)' }}>
          <span>Liberal</span>
          <span className="text-xs font-medium">{view.liberal} of 5</span>
        </div>
        <div className="grid grid-cols-5 gap-1.5">
          {Array.from({ length: 5 }, (_, i) => (
            <div key={i} className="grid h-14 place-items-center rounded border border-dashed" style={{ borderColor: 'var(--sh-lib)' }}>
              {i < view.liberal ? <Card p="L" size="sm" /> : i === 4 ? <span className="text-center text-[9px] leading-tight" style={{ color: 'var(--sh-lib)' }}>Liberals win</span> : null}
            </div>
          ))}
        </div>
      </div>
      <div className="rounded-lg border-2 p-2.5" style={{ borderColor: 'var(--sh-fas)', background: 'var(--sh-fas-pale)' }}>
        <div className="mb-1.5 flex items-baseline justify-between font-display text-sm font-bold" style={{ color: 'var(--sh-fas)' }}>
          <span>Fascist</span>
          <span className="text-xs font-medium">{view.fascist} of 6</span>
        </div>
        <div className="grid grid-cols-6 gap-1.5">
          {view.track.map((power, i) => {
            const Icon = power ? POWER_ICON[power] : null
            return (
              <div
                key={i}
                title={power ? POWER_TEXT[power] : i === 5 ? 'Fascists win' : 'No power'}
                className="grid h-14 place-items-center rounded border border-dashed"
                style={{ borderColor: 'var(--sh-fas)', color: 'var(--sh-fas)' }}
              >
                {i < view.fascist ? (
                  <Card p="F" size="sm" />
                ) : Icon ? (
                  <Icon className="size-4 opacity-70" aria-label={POWER_TEXT[power!]} />
                ) : i === 5 ? (
                  <span className="text-center text-[9px] leading-tight">Fascists win</span>
                ) : null}
              </div>
            )
          })}
        </div>
        <p className="mt-1.5 text-[11px] leading-snug" style={{ color: 'var(--sh-ink-2)' }}>
          {view.fascist >= 3 ? 'Hitler elected Chancellor now wins for the Fascists.' : 'After 3: electing Hitler Chancellor wins for the Fascists.'}
          {view.fascist >= 5 ? ' Veto is unlocked.' : ' After 5: veto unlocks.'}
        </p>
      </div>
      <div className="flex items-center justify-between text-xs" style={{ color: 'var(--sh-ink-2)' }}>
        <span className="flex items-center gap-1.5">
          Failed elections
          {[0, 1, 2].map((i) => (
            <span
              key={i}
              className="size-3 rounded-full border"
              style={{ borderColor: 'var(--sh-ink)', background: i < view.tracker ? 'var(--sh-ink)' : 'transparent' }}
            />
          ))}
          <span className="sr-only">{view.tracker} of 3</span>
        </span>
        <span>
          Deck {view.deckCount} · Discard {view.discardCount}
        </span>
      </div>
    </section>
  )
}

function RoleCard({ view, nameOf }: { view: View; nameOf: (id: PlayerId) => string }) {
  const [open, setOpen] = useState(false)
  if (!view.myRole) return null
  const role = view.myRole
  const mates = Object.entries(view.known).filter(([id]) => id !== view.me)
  const color = role === 'liberal' ? 'var(--sh-lib)' : role === 'hitler' ? 'var(--sh-hit)' : 'var(--sh-fas)'
  return (
    <button
      type="button"
      onClick={() => setOpen((o) => !o)}
      aria-expanded={open}
      className="flex w-full items-center gap-3 rounded-lg border-2 px-3 py-2.5 text-left"
      style={{ borderColor: 'var(--sh-ink)', background: open ? 'var(--sh-paper-2)' : 'transparent' }}
    >
      {open ? <EyeOff className="size-5 shrink-0" /> : <Eye className="size-5 shrink-0" />}
      {open ? (
        <span className="min-w-0">
          <span className="block font-display text-lg font-extrabold" style={{ color }}>
            You are {role === 'hitler' ? 'Hitler' : `a ${ROLE_NAME[role]}`}
          </span>
          <span className="block text-sm" style={{ color: 'var(--sh-ink-2)' }}>
            {role === 'liberal' && 'Pass five Liberal policies, or execute Hitler.'}
            {role !== 'liberal' && mates.length > 0 &&
              `Your team: ${mates.map(([id, r]) => `${nameOf(id)}${r === 'hitler' ? ' (Hitler)' : ''}`).join(', ')}. `}
            {role === 'hitler' && mates.length === 0 && "You don't know who the Fascists are, but they know you. "}
            {role !== 'liberal' && 'Pass six Fascist policies, or get Hitler elected Chancellor after three.'}
          </span>
        </span>
      ) : (
        <span className="font-medium">Tap to see your secret role</span>
      )}
    </button>
  )
}

function Panel({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="rounded-lg border-2 p-4" style={{ borderColor: 'var(--sh-ink)', background: 'var(--sh-paper-2)' }} aria-live="polite">
      <h2 className="mb-3 font-display text-lg font-extrabold leading-tight">{title}</h2>
      {children}
    </section>
  )
}

function InkButton({ children, onClick, tone = 'ink', disabled }: { children: ReactNode; onClick: () => void; tone?: 'ink' | 'lib' | 'fas' | 'ghost'; disabled?: boolean }) {
  const bg = tone === 'lib' ? 'var(--sh-lib)' : tone === 'fas' ? 'var(--sh-fas)' : tone === 'ghost' ? 'transparent' : 'var(--sh-ink)'
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className="inline-flex min-h-11 items-center justify-center gap-1.5 rounded-md border-2 px-4 py-2 font-display font-bold disabled:opacity-50"
      style={{ background: bg, color: tone === 'ghost' ? 'var(--sh-ink)' : 'var(--sh-paper)', borderColor: tone === 'ghost' ? 'var(--sh-ink)' : bg }}
    >
      {children}
    </button>
  )
}

const cardsText = (f: number, n: number) =>
  f === 0 ? `${n} Liberal` : f === n ? `${n} Fascist` : `${f} Fascist, ${n - f} Liberal`

function ClaimPrompt({ view, act }: { view: View; act: (a: SHAction) => void }) {
  const me = view.me
  if (!me) return null
  const g = [...view.govs].reverse().find((x) => x.enacted && ((x.president === me && x.presClaim === null) || (x.chancellor === me && x.chanClaim === null)))
  const inv = view.notes.find(
    (n): n is Extract<Note, { kind: 'investigation' }> =>
      n.kind === 'investigation' && !view.log.some((e) => e.kind === 'claimInvestigation' && e.president === me && e.target === n.target),
  )
  if (!g && !inv) return null
  return (
    <div className="flex flex-col gap-3">
      {g && (
        <div>
          <p className="mb-2 text-sm font-medium">
            Tell the table what you {g.president === me ? 'drew as President' : 'were handed as Chancellor'}. You can lie.
          </p>
          <div className="flex flex-wrap gap-2">
            {Array.from({ length: g.president === me ? 4 : 3 }, (_, f) => (
              <InkButton key={f} tone="ghost" onClick={() => act({ type: 'claim', govId: g.id, fascists: f })}>
                {cardsText(f, g.president === me ? 3 : 2)}
              </InkButton>
            ))}
          </div>
        </div>
      )}
      {inv && (
        <div>
          <p className="mb-2 text-sm font-medium">What will you say about the player you investigated?</p>
          <div className="flex gap-2">
            <InkButton tone="lib" onClick={() => act({ type: 'claimInvestigation', target: inv.target, party: 'liberal' })}>Say Liberal</InkButton>
            <InkButton tone="fas" onClick={() => act({ type: 'claimInvestigation', target: inv.target, party: 'fascist' })}>Say Fascist</InkButton>
          </div>
        </div>
      )}
    </div>
  )
}

function lastElection(view: View) {
  for (let i = view.log.length - 1; i >= 0; i--) {
    const e = view.log[i]!
    if (e.kind === 'election') return e
  }
  return null
}

function Action({ view, act, nameOf }: { view: View; act: (a: SHAction) => void; nameOf: (id: PlayerId) => string }) {
  const me = view.me
  const pres = nameOf(view.president)
  const isPres = me === view.president
  const isChan = me === view.nominee
  const dead = !!me && view.dead.includes(me)
  const [target, setTarget] = useState<PlayerId | null>(null)

  if (view.phase === 'over') {
    const libWin = view.winner === 'liberal'
    return (
      <section className="rounded-lg border-2 p-4 text-center" style={{ borderColor: 'var(--sh-ink)', background: view.winner ? (libWin ? 'var(--sh-lib)' : 'var(--sh-fas)') : 'var(--sh-ink)', color: 'var(--sh-paper)' }}>
        <h2 className="font-display text-2xl font-extrabold">{view.winner ? (libWin ? 'Liberals win' : 'Fascists win') : 'Game over'}</h2>
        <p className="mt-1">{view.winReason}</p>
      </section>
    )
  }

  switch (view.phase) {
    case 'nominate':
      if (!isPres)
        return (
          <Panel title={`${pres} is choosing a Chancellor`}>
            <p className="text-sm" style={{ color: 'var(--sh-ink-2)' }}>Talk it over. Everyone will vote on the pair.</p>
          </Panel>
        )
      return (
        <Panel title="You're the presidential candidate. Nominate a Chancellor.">
          <div className="flex flex-wrap gap-2">
            {view.eligible.map((id) => (
              <InkButton key={id} tone="ghost" onClick={() => act({ type: 'nominate', target: id })}>{nameOf(id)}</InkButton>
            ))}
          </div>
          <p className="mt-2 text-xs" style={{ color: 'var(--sh-ink-2)' }}>The last elected {view.seats.length - view.dead.length > 5 ? 'President and Chancellor are' : 'Chancellor is'} term-limited.</p>
        </Panel>
      )

    case 'vote': {
      const waiting = view.seats.filter((id) => !view.dead.includes(id) && !view.voted.includes(id))
      return (
        <Panel title={`Vote: ${pres} as President, ${nameOf(view.nominee!)} as Chancellor`}>
          {!dead && view.myVote === null ? (
            <div className="grid grid-cols-2 gap-3">
              <InkButton onClick={() => act({ type: 'vote', ja: true })}><Check className="size-5" /> Ja!</InkButton>
              <InkButton tone="ghost" onClick={() => act({ type: 'vote', ja: false })}><X className="size-5" /> Nein</InkButton>
            </div>
          ) : (
            <p className="font-medium">{dead ? 'You were executed and can’t vote.' : `You voted ${view.myVote ? 'Ja' : 'Nein'}.`}</p>
          )}
          <p className="mt-2 text-xs" style={{ color: 'var(--sh-ink-2)' }}>
            Votes are secret until everyone has voted. Waiting on {waiting.map(nameOf).join(', ')}.
            {view.tracker === 2 && ' If this fails, the top policy is enacted automatically.'}
          </p>
        </Panel>
      )
    }

    case 'president':
      if (!isPres || !view.hand) return <Panel title={`${pres} is looking at three policies`}><p className="text-sm">They’ll discard one and pass two to {nameOf(view.nominee!)}.</p></Panel>
      return (
        <Panel title="Discard one policy. The other two go to your Chancellor.">
          <div className="flex justify-center gap-3">
            {view.hand.map((p, i) => <Card key={i} p={p} onClick={() => act({ type: 'discard', index: i })} label={`Discard ${p === 'L' ? 'Liberal' : 'Fascist'}`} />)}
          </div>
          <p className="mt-2 text-center text-xs" style={{ color: 'var(--sh-ink-2)' }}>Tap the card to throw away.</p>
        </Panel>
      )

    case 'chancellor':
      if (!isChan || !view.hand) return <Panel title={`Chancellor ${nameOf(view.nominee!)} is choosing a policy`}><p className="text-sm">One of two cards becomes law.</p></Panel>
      return (
        <Panel title="Enact one policy.">
          <div className="flex justify-center gap-3">
            {view.hand.map((p, i) => <Card key={i} p={p} onClick={() => act({ type: 'enact', index: i })} label={`Enact ${p === 'L' ? 'Liberal' : 'Fascist'}`} />)}
          </div>
          {view.vetoUnlocked && !view.vetoAsked && (
            <div className="mt-3 text-center">
              <InkButton tone="ghost" onClick={() => act({ type: 'veto' })}>Propose a veto</InkButton>
            </div>
          )}
          {view.vetoAsked && <p className="mt-2 text-center text-xs">The President refused the veto. You must enact one.</p>}
        </Panel>
      )

    case 'veto':
      if (!isPres) return <Panel title="The Chancellor proposed a veto"><p className="text-sm">Waiting for {pres} to agree or refuse.</p></Panel>
      return (
        <Panel title="Your Chancellor wants to veto this agenda">
          <p className="mb-3 text-sm">If you agree, both cards are discarded and the election tracker moves up one.</p>
          <div className="grid grid-cols-2 gap-3">
            <InkButton onClick={() => act({ type: 'vetoAnswer', agree: true })}>Agree</InkButton>
            <InkButton tone="ghost" onClick={() => act({ type: 'vetoAnswer', agree: false })}>Refuse</InkButton>
          </div>
        </Panel>
      )

    case 'power': {
      const power = view.power!
      if (!isPres) return <Panel title={`${pres} is using a power`}><p className="text-sm">{POWER_TEXT[power]}.</p></Panel>
      if (power === 'peek') {
        const peek = [...view.notes].reverse().find((n): n is Extract<Note, { kind: 'peek' }> => n.kind === 'peek')
        return (
          <Panel title="The next three policies">
            <div className="flex justify-center gap-2">{peek?.cards.map((p, i) => <Card key={i} p={p} size="sm" />)}</div>
            <div className="mt-3 text-center"><InkButton onClick={() => act({ type: 'power' })}>Done</InkButton></div>
          </Panel>
        )
      }
      const verb = power === 'investigate' ? 'Investigate' : power === 'special' ? 'Make President' : 'Execute'
      return (
        <Panel title={power === 'investigate' ? 'Pick a player to investigate' : power === 'special' ? 'Pick the next presidential candidate' : 'Pick a player to execute'}>
          <div className="flex flex-wrap gap-2">
            {view.powerTargets.map((id) => (
              <InkButton key={id} tone={target === id ? 'ink' : 'ghost'} onClick={() => setTarget(id)}>{nameOf(id)}</InkButton>
            ))}
          </div>
          <div className="mt-3">
            <InkButton tone={power === 'execute' ? 'fas' : 'ink'} disabled={!target} onClick={() => target && act({ type: 'power', target })}>
              {target ? `${verb} ${nameOf(target)}` : verb}
            </InkButton>
          </div>
        </Panel>
      )
    }
  }
  return null
}

function Players({ view, nameOf }: { view: View; nameOf: (id: PlayerId) => string }) {
  const known = view.roles ?? view.known
  const many = view.seats.length - view.dead.length > 5
  return (
    <section aria-labelledby="sh-players">
      <h2 id="sh-players" className="mb-2 font-display text-base font-extrabold">Seating</h2>
      <ul className="divide-y rounded-lg border-2" style={{ borderColor: 'var(--sh-ink)' }}>
        {view.seats.map((id) => {
          const dead = view.dead.includes(id)
          const role = known[id]
          const tags: string[] = []
          if (id === view.president && view.phase !== 'over') tags.push('President')
          if (id === view.nominee && view.phase !== 'over') tags.push(view.phase === 'vote' ? 'Nominee' : 'Chancellor')
          if (view.phase === 'nominate' && (id === view.lastChancellor || (many && id === view.lastPresident))) tags.push('Term-limited')
          return (
            <li key={id} className={`flex items-center gap-2 px-3 py-2 ${dead ? 'line-through opacity-50' : ''}`} style={{ borderColor: 'var(--sh-ink-2)' }}>
              <span className="min-w-0 flex-1 truncate font-medium">
                {nameOf(id)}
                {id === view.me && <span style={{ color: 'var(--sh-ink-2)' }}> (you)</span>}
              </span>
              {tags.map((t) => (
                <span key={t} className="rounded px-1.5 py-0.5 text-[11px] font-bold" style={{ background: t === 'Term-limited' ? 'transparent' : 'var(--sh-ink)', color: t === 'Term-limited' ? 'var(--sh-ink-2)' : 'var(--sh-paper)' }}>{t}</span>
              ))}
              {view.phase === 'vote' && !dead && (view.voted.includes(id) ? <Check className="size-4" aria-label="voted" /> : <span className="size-4" />)}
              {role && id !== view.me && (
                <span className="text-xs font-bold" style={{ color: role === 'liberal' ? 'var(--sh-lib)' : 'var(--sh-fas)' }}>{ROLE_NAME[role]}</span>
              )}
              {dead && <span className="text-xs no-underline">executed</span>}
            </li>
          )
        })}
      </ul>
    </section>
  )
}

function Record({ view, nameOf }: { view: View; nameOf: (id: PlayerId) => string }) {
  const govById = new Map(view.govs.map((g) => [g.id, g]))
  const items: ReactNode[] = []
  view.log.forEach((e: LogEntry, i) => {
    if (e.kind === 'election') {
      const ja = Object.entries(e.e.votes).filter(([, v]) => v).map(([id]) => nameOf(id))
      const nein = Object.entries(e.e.votes).filter(([, v]) => !v).map(([id]) => nameOf(id))
      items.push(
        <li key={i}>
          <span className="font-bold">{nameOf(e.e.president)} + {nameOf(e.e.chancellor)}</span> {e.e.passed ? 'elected' : 'voted down'}
          <span className="block text-xs" style={{ color: 'var(--sh-ink-2)' }}>Ja: {ja.join(', ') || 'nobody'} · Nein: {nein.join(', ') || 'nobody'}</span>
        </li>,
      )
    } else if (e.kind === 'gov') {
      const g: Government | undefined = govById.get(e.govId)
      if (!g?.enacted) return
      items.push(
        <li key={i} className="flex items-start gap-2">
          {g.enacted === 'veto' ? <span className="font-bold">Agenda vetoed</span> : <Card p={g.enacted} size="sm" />}
          <span className="text-xs leading-snug">
            {g.enacted !== 'veto' && <span className="block font-bold">{g.enacted === 'L' ? 'Liberal' : 'Fascist'} policy enacted</span>}
            {nameOf(g.president)}: {g.presClaim === null ? 'no claim yet' : `drew ${cardsText(g.presClaim, 3)}`}
            <br />
            {nameOf(g.chancellor)}: {g.chanClaim === null ? 'no claim yet' : `got ${cardsText(g.chanClaim, 2)}`}
          </span>
        </li>,
      )
    } else if (e.kind === 'chaos') {
      items.push(<li key={i}>Three failed elections: the top policy, <b>{e.policy === 'L' ? 'Liberal' : 'Fascist'}</b>, was enacted.</li>)
    } else if (e.kind === 'power') {
      const t = e.target ? nameOf(e.target) : ''
      const text = { investigate: `investigated ${t}`, peek: 'peeked at the top three policies', special: `chose ${t} as the next President`, execute: `executed ${t}` }[e.power]
      items.push(<li key={i}><b>{nameOf(e.president)}</b> {text}.</li>)
    } else if (e.kind === 'claimInvestigation') {
      items.push(<li key={i}><b>{nameOf(e.president)}</b> says {nameOf(e.target)} is {e.party === 'liberal' ? 'a Liberal' : 'a Fascist'}.</li>)
    } else if (e.kind === 'reshuffle') {
      items.push(<li key={i} className="text-xs" style={{ color: 'var(--sh-ink-2)' }}>The discard pile was shuffled back into the deck.</li>)
    }
  })
  const mine = view.notes.filter((n) => n.kind !== 'peek')
  return (
    <section aria-labelledby="sh-record" className="flex flex-col gap-3">
      {mine.length > 0 && (
        <div className="rounded-lg border-2 border-dashed p-3" style={{ borderColor: 'var(--sh-ink-2)' }}>
          <h2 className="mb-1 font-display text-sm font-extrabold">Only you know</h2>
          <ul className="flex flex-col gap-1 text-sm">
            {mine.map((n, i) => (
              <li key={i}>
                {n.kind === 'investigation' && <>{nameOf(n.target)} is a <b>{n.party === 'liberal' ? 'Liberal' : 'Fascist'}</b>.</>}
                {n.kind === 'drew' && <>Government {n.govId}: you drew {cardsText(n.cards.filter((c) => c === 'F').length, 3)} and passed {cardsText(n.passed.filter((c) => c === 'F').length, 2)}.</>}
                {n.kind === 'received' && <>Government {n.govId}: you were handed {cardsText(n.cards.filter((c) => c === 'F').length, 2)}.</>}
              </li>
            ))}
          </ul>
        </div>
      )}
      <div>
        <h2 id="sh-record" className="mb-2 font-display text-base font-extrabold">The record</h2>
        {items.length ? (
          <ol className="flex flex-col-reverse gap-2.5 text-sm">{items}</ol>
        ) : (
          <p className="text-sm" style={{ color: 'var(--sh-ink-2)' }}>Nothing yet. Elections, laws and claims show up here.</p>
        )}
      </div>
    </section>
  )
}

function HowTo() {
  return (
    <details className="rounded-lg border-2 p-3 text-sm" style={{ borderColor: 'var(--sh-ink-2)' }}>
      <summary className="cursor-pointer font-display font-extrabold">How to play</summary>
      <ul className="mt-2 flex list-disc flex-col gap-1.5 pl-5 leading-snug">
        <li>Each round the presidential candidate nominates a Chancellor and everyone votes Ja or Nein. A majority of Ja elects them.</li>
        <li>The President draws three policies, discards one, and passes two. The Chancellor enacts one. Nobody else sees the cards, so claims can be lies.</li>
        <li>Three failed elections in a row enact the top policy automatically.</li>
        <li>Some Fascist policies give the President a power: investigate, peek, special election or execution.</li>
        <li>Liberals win with five Liberal policies or by executing Hitler. Fascists win with six Fascist policies or by electing Hitler Chancellor after three.</li>
      </ul>
      <p className="mt-2 text-xs" style={{ color: 'var(--sh-ink-2)' }}>
        Secret Hitler by Mike Boxleiter, Tommy Maranges and Max Temkin, used under CC BY-NC-SA 4.0 (secrethitler.com).
      </p>
    </details>
  )
}

export default function SHView({ view, act, isHost, playAgain, backToLobby, nameOf }: GameViewProps<View, SHAction>) {
  const last = lastElection(view)
  const showVote = last && view.phase !== 'vote'
  return (
    <div style={PAPER} className="min-h-[calc(100dvh-3.25rem)] bg-[var(--sh-paper)] text-[var(--sh-ink)]">
      <div className="mx-auto flex max-w-lg flex-col gap-4 px-4 py-5">
        <RoleCard view={view} nameOf={nameOf} />
        <Action key={view.log.length} view={view} act={act} nameOf={nameOf} />
        <ClaimPrompt view={view} act={act} />
        {showVote && last && (
          <p className="rounded-md px-3 py-2 text-sm" style={{ background: 'var(--sh-paper-2)' }} role="status">
            Last vote: {nameOf(last.e.president)} + {nameOf(last.e.chancellor)} {last.e.passed ? 'passed' : 'failed'},{' '}
            {Object.values(last.e.votes).filter(Boolean).length} Ja to {Object.values(last.e.votes).filter((v) => !v).length} Nein.
          </p>
        )}
        {view.phase === 'over' &&
          (isHost ? (
            <div className="flex flex-col gap-2">
              <InkButton onClick={playAgain}>Play again</InkButton>
              <InkButton tone="ghost" onClick={backToLobby}>Back to lobby</InkButton>
            </div>
          ) : (
            <p className="text-center text-sm">Waiting for the host to start another game.</p>
          ))}
        <Track view={view} />
        <Players view={view} nameOf={nameOf} />
        <Record view={view} nameOf={nameOf} />
        <HowTo />
      </div>
    </div>
  )
}
