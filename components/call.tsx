'use client'

import { Eye, EyeOff, GripVertical, Mic, MicOff, PhoneOff, Video, VideoOff } from 'lucide-react'
import { useCallback, useEffect, useRef, useState, type PointerEvent as RPointerEvent } from 'react'
import { useSession } from '@/lib/session'
import { Button } from './ui/button'

const POS_KEY = 'p2pg.callDock'

function Stream({ stream, muted, label, off }: { stream: MediaStream | null; muted?: boolean; label: string; off?: boolean }) {
  const ref = useRef<HTMLVideoElement>(null)
  useEffect(() => {
    const el = ref.current
    if (el && el.srcObject !== stream) el.srcObject = stream
  }, [stream])
  const hasVideo = !!stream?.getVideoTracks().length && !off
  return (
    <div className="relative h-[72px] w-24 shrink-0 overflow-hidden rounded-lg border border-white/15 bg-[#1b1620] shadow-lg">
      <video ref={ref} autoPlay playsInline muted={muted} className={`h-full w-full object-cover ${hasVideo ? '' : 'invisible'}`}
        style={muted ? { transform: 'scaleX(-1)' } : undefined} />
      {!hasVideo && (
        <span className="absolute inset-0 grid place-items-center font-display text-2xl font-bold text-white/80">
          {label.slice(0, 1).toUpperCase()}
        </span>
      )}
      <span className="absolute inset-x-0 bottom-0 truncate bg-black/55 px-1.5 py-0.5 text-[11px] text-white">{label}</span>
    </div>
  )
}

function loadPos(): { x: number; y: number } {
  try {
    const p = JSON.parse(localStorage.getItem(POS_KEY) ?? '')
    if (typeof p?.x === 'number' && typeof p?.y === 'number') return p
  } catch {
    /* storage unavailable */
  }
  return { x: 8, y: 64 }
}

/**
 * Floating, draggable call strip: a grip to move it, mic/camera/leave
 * buttons, and the video tiles. It remembers where you leave it.
 */
export function CallDock() {
  const { call, callNames, room, leaveCall, setMic, setCam, callTilesOpen } = useSession()
  const boxRef = useRef<HTMLDivElement>(null)
  const [pos, setPos] = useState<{ x: number; y: number }>({ x: 8, y: 64 })
  const drag = useRef<{ dx: number; dy: number } | null>(null)

  const clamp = useCallback((p: { x: number; y: number }) => {
    const el = boxRef.current
    const w = el?.offsetWidth ?? 120
    const h = el?.offsetHeight ?? 48
    return {
      x: Math.max(4, Math.min(window.innerWidth - w - 4, p.x)),
      y: Math.max(4, Math.min(window.innerHeight - h - 4, p.y)),
    }
  }, [])

  useEffect(() => {
    // Restore the saved position once mounted (storage is browser-only).
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setPos(clamp(loadPos()))
    const onResize = () => setPos((p) => clamp(p))
    window.addEventListener('resize', onResize)
    // The strip grows as people join; keep all of it on screen.
    const ro = typeof ResizeObserver !== 'undefined' && boxRef.current ? new ResizeObserver(onResize) : null
    if (ro && boxRef.current) ro.observe(boxRef.current)
    return () => {
      window.removeEventListener('resize', onResize)
      ro?.disconnect()
    }
  }, [clamp, call.inCall])

  if (!call.inCall || !room?.snapshot) return null
  const myName = room.snapshot.players.find((p) => p.id === room.snapshot!.you)?.name ?? 'You'
  const connected = [...callNames.entries()].filter(([peer]) => call.remotes.has(peer))
  const waiting = Math.max(0, callNames.size - 1 - connected.length)

  function onDown(e: RPointerEvent) {
    drag.current = { dx: e.clientX - pos.x, dy: e.clientY - pos.y }
    e.currentTarget.setPointerCapture(e.pointerId)
  }
  function onMove(e: RPointerEvent) {
    if (!drag.current) return
    setPos(clamp({ x: e.clientX - drag.current.dx, y: e.clientY - drag.current.dy }))
  }
  function onUp() {
    if (!drag.current) return
    drag.current = null
    try {
      localStorage.setItem(POS_KEY, JSON.stringify(pos))
    } catch {
      /* storage unavailable */
    }
  }
  function nudge(dx: number, dy: number) {
    const next = clamp({ x: pos.x + dx, y: pos.y + dy })
    setPos(next)
    try {
      localStorage.setItem(POS_KEY, JSON.stringify(next))
    } catch {
      /* storage unavailable */
    }
  }

  return (
    <div ref={boxRef} className="fixed z-30 flex flex-col items-start gap-2" style={{ left: pos.x, top: pos.y }} role="region" aria-label="Video call">
      <div className="flex items-center gap-1 rounded-full bg-[#1b1620]/95 p-1 text-white shadow-lg">
        <button
          type="button"
          aria-label="Move the call. Drag, or use the arrow keys."
          title="Drag to move"
          onPointerDown={onDown}
          onPointerMove={onMove}
          onPointerUp={onUp}
          onPointerCancel={onUp}
          onKeyDown={(e) => {
            const step = e.shiftKey ? 40 : 12
            const d = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] }[e.key]
            if (d) {
              e.preventDefault()
              nudge(d[0]!, d[1]!)
            }
          }}
          className="grid h-9 w-6 cursor-grab touch-none place-items-center rounded-full text-white/60 hover:text-white active:cursor-grabbing"
        >
          <GripVertical className="size-4" />
        </button>
        <button type="button" aria-label={call.micOn ? 'Mute microphone' : 'Unmute microphone'} onClick={() => setMic(!call.micOn)}
          className={`grid size-9 place-items-center rounded-full ${call.micOn ? 'hover:bg-white/10' : 'bg-red-500'}`}>
          {call.micOn ? <Mic className="size-4" /> : <MicOff className="size-4" />}
        </button>
        {call.video && (
          <button type="button" aria-label={call.camOn ? 'Turn camera off' : 'Turn camera on'} onClick={() => setCam(!call.camOn)}
            className={`grid size-9 place-items-center rounded-full ${call.camOn ? 'hover:bg-white/10' : 'bg-red-500'}`}>
            {call.camOn ? <Video className="size-4" /> : <VideoOff className="size-4" />}
          </button>
        )}
        <button type="button" aria-label="Leave call" onClick={leaveCall} className="grid size-9 place-items-center rounded-full bg-red-600 hover:bg-red-700">
          <PhoneOff className="size-4" />
        </button>
      </div>
      {callTilesOpen && (
        <div className="flex max-h-[60dvh] flex-col gap-2 overflow-y-auto">
          <Stream stream={call.local} muted label={`${myName} (you)`} off={!call.camOn} />
          {connected.map(([peer, name]) => (
            <Stream key={peer} stream={call.remotes.get(peer)!} label={name} />
          ))}
          {waiting > 0 && <p className="rounded bg-black/60 px-2 py-1 text-[11px] text-white/80">Connecting to {waiting}…</p>}
        </div>
      )}
    </div>
  )
}

/**
 * The call menu, used in the lobby and the game header. Before you join it
 * offers video or audio; once you're in, it has every call control.
 */
export function CallButton({ className = '' }: { className?: string }) {
  const { call, callNames, joinCall, leaveCall, setMic, setCam, callTilesOpen, setCallTilesOpen } = useSession()
  const [menu, setMenu] = useState(false)
  const ref = useRef<HTMLSpanElement>(null)

  useEffect(() => {
    if (!menu) return
    const close = (e: PointerEvent) => {
      if (!ref.current?.contains(e.target as Node)) setMenu(false)
    }
    const esc = (e: KeyboardEvent) => e.key === 'Escape' && setMenu(false)
    document.addEventListener('pointerdown', close)
    document.addEventListener('keydown', esc)
    return () => {
      document.removeEventListener('pointerdown', close)
      document.removeEventListener('keydown', esc)
    }
  }, [menu])

  const others = [...callNames.values()]
  const label = call.joining ? 'Joining…' : call.inCall ? `In call (${callNames.size})` : callNames.size ? `Call (${callNames.size})` : 'Call'
  const pick = (fn: () => void) => () => {
    setMenu(false)
    fn()
  }

  return (
    <span ref={ref} className={`relative ${className}`}>
      <button
        type="button"
        onClick={() => setMenu((m) => !m)}
        aria-expanded={menu}
        aria-haspopup="menu"
        disabled={call.joining}
        className={`inline-flex items-center gap-1 rounded-md px-2 py-1 text-sm hover:bg-secondary ${call.inCall ? 'text-ok' : 'text-muted-foreground'}`}
      >
        <Video className="size-4" aria-hidden="true" />
        {label}
      </button>
      {menu && (
        <span role="menu" className="absolute right-0 top-full z-40 mt-1 flex w-56 flex-col gap-1 rounded-lg border bg-card p-1.5 text-left text-foreground shadow-lg">
          {others.length > 0 && (
            <span className="px-2 pb-1 pt-0.5 text-xs text-muted-foreground">In the call: {others.join(', ')}</span>
          )}
          {call.inCall ? (
            <>
              <Button role="menuitem" size="sm" variant="ghost" className="justify-start" onClick={pick(() => setMic(!call.micOn))}>
                {call.micOn ? <MicOff /> : <Mic />} {call.micOn ? 'Mute microphone' : 'Unmute microphone'}
              </Button>
              {call.video && (
                <Button role="menuitem" size="sm" variant="ghost" className="justify-start" onClick={pick(() => setCam(!call.camOn))}>
                  {call.camOn ? <VideoOff /> : <Video />} {call.camOn ? 'Turn camera off' : 'Turn camera on'}
                </Button>
              )}
              <Button role="menuitem" size="sm" variant="ghost" className="justify-start" onClick={pick(() => setCallTilesOpen(!callTilesOpen))}>
                {callTilesOpen ? <EyeOff /> : <Eye />} {callTilesOpen ? 'Hide video tiles' : 'Show video tiles'}
              </Button>
              <Button role="menuitem" size="sm" variant="destructive" className="justify-start" onClick={pick(leaveCall)}>
                <PhoneOff /> Leave call
              </Button>
            </>
          ) : (
            <>
              <span className="px-2 pb-1 text-xs text-muted-foreground">See and hear each other while you play. Video goes straight between phones.</span>
              <Button role="menuitem" size="sm" onClick={pick(() => joinCall(true))}>Join with video</Button>
              <Button role="menuitem" size="sm" variant="outline" onClick={pick(() => joinCall(false))}>Join with audio only</Button>
            </>
          )}
        </span>
      )}
    </span>
  )
}
