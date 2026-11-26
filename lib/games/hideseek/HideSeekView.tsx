'use client'

import { useEffect, useRef } from 'react'
import type { GameViewProps } from '@/lib/games/ui'
import { useSession } from '@/lib/session'
import type { HideSeekAction, HideSeekView as View } from './rules'

const BASE = process.env.NEXT_PUBLIC_BASE_PATH || ''

/**
 * The round runs in the Godot game in an iframe (public/hideseek), as the
 * racer does (RacingView, whose bridge this follows): this page hands the
 * game the room's round state and the players, carries the game's actions
 * back to the room, and passes positions and paintball shots between the
 * game and the other players (the room's relay).
 *
 * Messages to the game:  { source: 'game-night', kind: 'state' | 'relay', ... }
 * Messages from the game: { source: 'hideseek', kind: 'ready' | 'act' | 'relay', ... }
 */
export default function HideSeekView({ view, snapshot, me, isHost, act, hostNow }: GameViewProps<View, HideSeekAction>) {
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
      // How far the host's clock is ahead of ours, so timers line up.
      clock: hostNow() - Date.now(),
      players: snapshot.players.map((p) => ({ id: p.id, name: p.name, bot: !!p.bot, level: p.bot?.level ?? null })),
    })
  }

  useEffect(sendState)

  useEffect(() => {
    const onMessage = (e: MessageEvent) => {
      if (e.source !== frame.current?.contentWindow) return
      const m = e.data as { source?: string; kind?: string; action?: unknown; data?: unknown }
      if (m?.source !== 'hideseek') return
      if (m.kind === 'ready') sendState()
      else if (m.kind === 'act' && m.action) act(m.action as HideSeekAction)
      else if (m.kind === 'relay') relay(m.data)
    }
    window.addEventListener('message', onMessage)
    const off = onRelay((from, data) => post({ kind: 'relay', from, data }))
    // The host's clock drifts against ours: resend now and then.
    const timer = window.setInterval(sendState, 5000)
    return () => {
      window.removeEventListener('message', onMessage)
      off()
      window.clearInterval(timer)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [act, relay, onRelay])

  return (
    <iframe
      ref={frame}
      title="Hide and Seek"
      src={`${BASE}/hideseek/index.html?room=1`}
      className="block w-full border-0 bg-[#88c6f2]"
      style={{ height: 'calc(100dvh - var(--shell-head, 0px))' }}
      allow="fullscreen; autoplay"
      allowFullScreen
    />
  )
}
