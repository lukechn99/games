'use client'

import { useEffect, useRef } from 'react'
import type { GameViewProps } from '@/lib/games/ui'
import { useSession } from '@/lib/session'
import { Button } from '@/components/ui/button'
import { TRACKS, type RacingAction, type RacingView as View } from './rules'

const BASE = process.env.NEXT_PUBLIC_BASE_PATH || ''

/**
 * The race runs in the Godot game in an iframe (public/racing). This page is
 * the go-between: it hands the game the room's race state and the players'
 * names, carries the game's actions back to the room, and passes kart
 * positions between the game and the other players (the room's relay).
 *
 * Messages to the game:  { source: 'game-night', kind: 'state' | 'relay', ... }
 * Messages from the game: { source: 'racing', kind: 'ready' | 'act' | 'relay', ... }
 */
export default function RacingView(props: GameViewProps<View, RacingAction>) {
  // The host picks the track first; the game loads once it's chosen.
  if (props.view.phase === 'track') return <TrackPicker {...props} />
  return <Race {...props} />
}

function TrackPicker({ view, snapshot, me, isHost, act }: GameViewProps<View, RacingAction>) {
  const hostId = snapshot.hostId
  // The host picks; if the host is only watching, any racer can.
  const canPick = isHost || (!!me && view.seats.includes(me) && !view.seats.includes(hostId ?? ''))
  const host = snapshot.players.find((p) => p.id === hostId)?.name ?? 'The host'
  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-4 px-4 py-8">
      <h2 className="text-2xl font-semibold">{canPick ? 'Pick a track' : `${host} is picking the track`}</h2>
      <div className="grid grid-cols-2 gap-3">
        {[...TRACKS, { id: 'gp', name: 'Grand Prix' } as const].map((t) => (
          <button
            key={t.id}
            type="button"
            disabled={!canPick}
            onClick={() => act({ type: 'track', id: t.id })}
            className="group flex flex-col gap-2 rounded-xl border p-2 text-left transition-colors enabled:hover:border-foreground/40 enabled:hover:bg-muted/50 disabled:cursor-default"
          >
            {/* eslint-disable-next-line @next/next/no-img-element -- a static export, no image optimiser */}
            <img
              src={`${BASE}/tracks/${t.id}.jpg`}
              alt=""
              className="aspect-video w-full rounded-lg bg-muted object-cover"
            />
            <span className="px-1 pb-1 font-medium">{t.name}</span>
          </button>
        ))}
      </div>
    </div>
  )
}

function Race({ view, snapshot, me, isHost, act, hostNow, playAgain }: GameViewProps<View, RacingAction>) {
  const frame = useRef<HTMLIFrameElement>(null)
  const { relay, onRelay } = useSession()
  const latest = useRef({ view, snapshot, me, isHost })
  latest.current = { view, snapshot, me, isHost }

  const post = (msg: Record<string, unknown>) => {
    frame.current?.contentWindow?.postMessage({ source: 'game-night', ...msg }, '*')
  }

  const sendState = () => {
    const { view, snapshot, me, isHost } = latest.current
    post({
      kind: 'state',
      state: view,
      me,
      isHost,
      round: snapshot.game?.round ?? 0,
      // How far the host's clock is ahead of ours, so countdowns line up.
      clock: hostNow() - Date.now(),
      players: snapshot.players.map((p) => ({ id: p.id, name: p.name, bot: !!p.bot })),
    })
  }

  // Every change to the race state goes to the game.
  useEffect(sendState)

  useEffect(() => {
    const onMessage = (e: MessageEvent) => {
      if (e.source !== frame.current?.contentWindow) return
      const m = e.data as { source?: string; kind?: string; action?: unknown; data?: unknown }
      if (m?.source !== 'racing') return
      if (m.kind === 'ready') sendState()
      else if (m.kind === 'act' && m.action) act(m.action as RacingAction)
      else if (m.kind === 'room' && m.action === 'playAgain' && latest.current.isHost) playAgain()
      else if (m.kind === 'relay') relay(m.data)
    }
    window.addEventListener('message', onMessage)
    const off = onRelay((from, data) => post({ kind: 'relay', from, data }))
    return () => {
      window.removeEventListener('message', onMessage)
      off()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [act, relay, onRelay, playAgain])

  return (
    <iframe
      // A new round reloads the game, so it starts fresh with the new seats.
      key={snapshot.game?.round ?? 0}
      ref={frame}
      title="Karts & Wheels"
      src={`${BASE}/racing/index.html?room=1&track=${view.track}`}
      className="block w-full border-0 bg-[#88c6f2]"
      style={{ height: 'calc(100dvh - var(--shell-head, 0px))' }}
      allow="fullscreen; accelerometer; gyroscope; autoplay"
      allowFullScreen
    />
  )
}
