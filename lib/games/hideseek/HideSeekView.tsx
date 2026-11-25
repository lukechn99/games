'use client'

import type { GameViewProps } from '@/lib/games/ui'
import type { HideSeekAction, HideSeekView as View } from './rules'

const BASE = process.env.NEXT_PUBLIC_BASE_PATH || ''

/**
 * Hide and Seek runs in the Godot game in an iframe (public/hideseek). For
 * now it's the solo practice barn, so the room only opens it; nothing is
 * passed back and forth yet.
 */
export default function HideSeekView({ snapshot }: GameViewProps<View, HideSeekAction>) {
  return (
    <iframe
      key={snapshot.game?.round ?? 0}
      title="Hide and Seek"
      src={`${BASE}/hideseek/index.html`}
      className="block w-full border-0 bg-[#88c6f2]"
      style={{ height: 'calc(100dvh - var(--shell-head, 0px))' }}
      allow="fullscreen; autoplay"
      allowFullScreen
    />
  )
}
