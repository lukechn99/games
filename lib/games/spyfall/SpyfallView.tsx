'use client'

import { Eye, EyeOff } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Button } from '@/components/ui/button'
import type { GameViewProps } from '@/lib/games/ui'
import type { SpyfallAction, SpyfallView as View } from './rules'

function useCountdown(deadline: number | null, hostNow: () => number) {
  const [left, setLeft] = useState(0)
  useEffect(() => {
    if (deadline === null) return
    const update = () => setLeft(Math.max(0, deadline - hostNow()))
    update()
    const id = setInterval(update, 250)
    return () => clearInterval(id)
  }, [deadline, hostNow])
  return left
}

function formatTime(ms: number) {
  const s = Math.ceil(ms / 1000)
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`
}

export default function SpyfallView(props: GameViewProps<View, SpyfallAction>) {
  const { view } = props
  if (view.phase === 'ended') return <Results {...props} />
  if (view.phase === 'voting') return <Voting {...props} />
  return <Playing {...props} />
}

function RoleCard({ view }: { view: View }) {
  const [shown, setShown] = useState(false)
  if (view.isSpy === null) {
    return (
      <div className="rounded-xl border-2 border-dashed p-6 text-center text-muted-foreground">
        You&apos;re watching. Roles are hidden until the round ends.
      </div>
    )
  }
  return (
    <button
      type="button"
      onClick={() => setShown((s) => !s)}
      aria-pressed={shown}
      className={`w-full rounded-xl p-6 text-center transition-colors ${
        shown ? (view.isSpy ? 'bg-destructive text-white' : 'bg-primary text-primary-foreground') : 'bg-foreground text-background'
      }`}
    >
      {shown ? (
        view.isSpy ? (
          <>
            <span className="block font-display text-4xl font-extrabold">You&apos;re the spy</span>
            <span className="mt-2 block opacity-90">Blend in and work out the location.</span>
          </>
        ) : (
          <>
            <span className="block text-sm opacity-80">The location is</span>
            <span className="block font-display text-4xl font-extrabold">{view.location}</span>
            <span className="mt-2 block opacity-90">One of you is the spy. Find them.</span>
          </>
        )
      ) : (
        <span className="block font-display text-2xl font-bold">Tap to see your role</span>
      )}
      <span className="mt-3 inline-flex items-center gap-1.5 text-sm opacity-80">
        {shown ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
        {shown ? 'Tap to hide' : 'Keep your screen to yourself'}
      </span>
    </button>
  )
}

function Playing({ view, me, act, hostNow, nameOf }: GameViewProps<View, SpyfallAction>) {
  const left = useCountdown(view.endsAt, hostNow)
  const [crossed, setCrossed] = useState<Set<string>>(new Set())
  const [guessing, setGuessing] = useState<string | null>(null)
  const seated = view.isSpy !== null
  const wantsVote = view.callingVote.includes(me)
  const needed = Math.floor(view.players.length / 2) + 1

  function toggleCross(loc: string) {
    setCrossed((prev) => {
      const next = new Set(prev)
      if (next.has(loc)) next.delete(loc)
      else next.add(loc)
      return next
    })
  }

  return (
    <div className="mx-auto flex max-w-md flex-col gap-6 px-6 py-6">
      <div className="text-center">
        <p className="font-display text-6xl font-extrabold tabular-nums" aria-label={`${formatTime(left)} left`}>
          {formatTime(left)}
        </p>
        <p className="mt-1 text-muted-foreground">
          {view.firstAsker === me ? 'You ask' : `${nameOf(view.firstAsker)} asks`} the first question
        </p>
      </div>

      <RoleCard view={view} />

      {seated && (
        <div className="flex flex-col gap-2">
          <Button
            variant={wantsVote ? 'default' : 'outline'}
            size="lg"
            className="h-12"
            onClick={() => act({ type: 'callVote', on: !wantsVote })}
          >
            {wantsVote ? 'Waiting for others to call a vote' : 'Call a vote'}
          </Button>
          <p className="text-center text-sm text-muted-foreground">
            {view.callingVote.length} of {needed} needed to start voting early
          </p>
        </div>
      )}

      <section aria-labelledby="locations-heading">
        <h2 id="locations-heading" className="font-display text-lg font-bold">
          Possible locations
        </h2>
        <p className="mb-3 text-sm text-muted-foreground">
          {view.isSpy ? 'Tap to rule places out. When you know it, make your guess.' : 'Tap to cross off places, just for you.'}
        </p>
        <div className="grid grid-cols-2 gap-2">
          {view.locations.map((loc) => {
            const isCrossed = crossed.has(loc)
            const isHere = loc === view.location
            return (
              <button
                key={loc}
                type="button"
                onClick={() => toggleCross(loc)}
                aria-pressed={isCrossed}
                className={`rounded-md border px-3 py-2 text-left text-sm ${
                  isHere ? 'border-primary font-semibold text-primary' : ''
                } ${isCrossed ? 'text-muted-foreground line-through opacity-60' : 'bg-card'}`}
              >
                {loc}
              </button>
            )
          })}
        </div>
      </section>

      {view.isSpy && (
        <section className="rounded-lg border-2 border-destructive/40 p-4">
          <h2 className="font-display text-lg font-bold">Guess the location</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Right and you win on the spot. Wrong and the agents win. You only get one try.
          </p>
          <select
            className="mt-3 h-11 w-full rounded-md border bg-card px-3"
            value={guessing ?? ''}
            onChange={(e) => setGuessing(e.target.value || null)}
            aria-label="Location to guess"
          >
            <option value="">Choose a location…</option>
            {view.locations.map((loc) => (
              <option key={loc} value={loc}>
                {loc}
              </option>
            ))}
          </select>
          <Button
            variant="destructive"
            className="mt-3 w-full"
            disabled={!guessing}
            onClick={() => {
              if (guessing && window.confirm(`Guess "${guessing}"? This ends the round.`)) {
                act({ type: 'guessLocation', location: guessing })
              }
            }}
          >
            Make my guess
          </Button>
        </section>
      )}
    </div>
  )
}

function Voting({ view, me, act, hostNow, nameOf }: GameViewProps<View, SpyfallAction>) {
  const left = useCountdown(view.voteEndsAt, hostNow)
  const seated = view.isSpy !== null

  return (
    <div className="mx-auto flex max-w-md flex-col gap-6 px-6 py-6">
      <div className="text-center">
        <h2 className="font-display text-3xl font-extrabold">Who is the spy?</h2>
        <p className="mt-1 text-muted-foreground">
          {view.voted.length} of {view.players.length} voted, {formatTime(left)} left
        </p>
      </div>

      {seated ? (
        <div className="flex flex-col gap-2" role="radiogroup" aria-label="Vote for the spy">
          {view.players
            .filter((id) => id !== me)
            .map((id) => {
              const chosen = view.myVote === id
              return (
                <button
                  key={id}
                  type="button"
                  role="radio"
                  aria-checked={chosen}
                  onClick={() => act({ type: 'vote', target: id })}
                  className={`flex items-center justify-between rounded-lg border-2 bg-card px-4 py-4 text-left text-lg ${
                    chosen ? 'border-primary' : 'border-border'
                  }`}
                >
                  <span className="font-medium">{nameOf(id)}</span>
                  {view.voted.includes(id) && <span className="text-sm text-muted-foreground">voted</span>}
                </button>
              )
            })}
          <p className="mt-2 text-center text-sm text-muted-foreground">
            {view.myVote
              ? 'You can change your vote until everyone has voted.'
              : 'Most votes is accused. A tie means the spy gets away.'}
          </p>
        </div>
      ) : (
        <p className="text-center text-muted-foreground">The players are voting.</p>
      )}

      {view.isSpy && (
        <p className="rounded-lg bg-secondary p-3 text-center text-sm">
          You&apos;re the spy. Vote for someone else to throw them off.
        </p>
      )}
    </div>
  )
}

function Results({ view, isHost, playAgain, backToLobby, nameOf }: GameViewProps<View, SpyfallAction>) {
  const result = view.result!
  const headline =
    result.winner === 'spy' ? 'The spy wins' : result.winner === 'agents' ? 'The agents win' : 'Round over'

  const tally = new Map<string, string[]>()
  for (const [voter, target] of Object.entries(view.votes ?? {})) {
    tally.set(target, [...(tally.get(target) ?? []), voter])
  }

  return (
    <div className="mx-auto flex max-w-md flex-col gap-6 px-6 py-8">
      <div
        className={`rounded-xl p-6 text-center ${
          result.winner === 'spy'
            ? 'bg-destructive text-white'
            : result.winner === 'agents'
              ? 'bg-primary text-primary-foreground'
              : 'bg-secondary'
        }`}
      >
        <p className="font-display text-4xl font-extrabold">{headline}</p>
        <p className="mt-2 opacity-90">{result.reason}</p>
      </div>

      <dl className="grid grid-cols-2 gap-3">
        <div className="rounded-lg border bg-card p-4">
          <dt className="text-sm text-muted-foreground">The spy was</dt>
          <dd className="font-display text-xl font-bold">{view.spy ? nameOf(view.spy) : '—'}</dd>
        </div>
        <div className="rounded-lg border bg-card p-4">
          <dt className="text-sm text-muted-foreground">The location was</dt>
          <dd className="font-display text-xl font-bold">{view.location}</dd>
        </div>
        {result.spyGuess && (
          <div className="col-span-2 rounded-lg border bg-card p-4">
            <dt className="text-sm text-muted-foreground">The spy guessed</dt>
            <dd className="font-display text-xl font-bold">{result.spyGuess}</dd>
          </div>
        )}
      </dl>

      {tally.size > 0 && (
        <section>
          <h2 className="mb-2 font-display text-lg font-bold">Votes</h2>
          <ul className="divide-y rounded-lg border bg-card">
            {[...tally.entries()]
              .sort((a, b) => b[1].length - a[1].length)
              .map(([target, voters]) => (
                <li key={target} className="px-4 py-3">
                  <span className="font-medium">{nameOf(target)}</span>
                  <span className="text-muted-foreground">
                    {' '}
                    ← {voters.map(nameOf).join(', ')}
                  </span>
                </li>
              ))}
          </ul>
        </section>
      )}

      {isHost ? (
        <div className="flex flex-col gap-2">
          <Button size="lg" className="h-12 text-base" onClick={playAgain}>
            Play another round
          </Button>
          <Button size="lg" variant="outline" className="h-12 text-base" onClick={backToLobby}>
            Back to lobby
          </Button>
        </div>
      ) : (
        <p className="text-center text-muted-foreground">Waiting for the host to start the next round.</p>
      )}
    </div>
  )
}
