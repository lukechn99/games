'use client'

import { GripVertical, Maximize2, Mic, MicOff, Minimize2, Minus, PhoneOff, Video, VideoOff } from 'lucide-react'
import { useCallback, useEffect, useRef, useState, type PointerEvent as RPointerEvent } from 'react'
import { MAX_VIDEO } from '@/lib/engine/room'
import { useSession, type CallPerson } from '@/lib/session'
import { Button } from './ui/button'

const POS_KEY = 'p2pg.callDock'

function Stream({ stream, mine, label, big }: { stream: MediaStream | null; mine?: boolean; label: string; big?: boolean }) {
  const ref = useRef<HTMLVideoElement>(null)
  useEffect(() => {
    const el = ref.current
    if (el && el.srcObject !== stream) el.srcObject = stream
  }, [stream])
  return (
    <div className={`relative overflow-hidden rounded-lg border border-white/15 bg-[#1b1620] shadow-lg ${big ? 'h-full min-h-0 w-full' : 'h-[72px] w-24 shrink-0'}`}>
      <video ref={ref} autoPlay playsInline muted={mine} className="h-full w-full object-cover" style={mine ? { transform: 'scaleX(-1)' } : undefined} />
      <span className={`absolute inset-x-0 bottom-0 truncate bg-black/55 px-1.5 py-0.5 text-white ${big ? 'text-sm' : 'text-[11px]'}`}>{label}</span>
    </div>
  )
}

/** Plays a remote stream that has no tile (audio-only people, or while minimized). */
function Audio({ stream }: { stream: MediaStream }) {
  const ref = useRef<HTMLAudioElement>(null)
  useEffect(() => {
    const el = ref.current
    if (el && el.srcObject !== stream) el.srcObject = stream
  }, [stream])
  return <audio ref={ref} autoPlay />
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

function savePos(p: { x: number; y: number }) {
  try {
    localStorage.setItem(POS_KEY, JSON.stringify(p))
  } catch {
    /* storage unavailable */
  }
}

const round = 'grid size-9 shrink-0 place-items-center rounded-full'

/** Mic, camera, size and leave: the same controls in the panel and full screen. */
function Controls({ big }: { big?: boolean }) {
  const { call, videoFull, leaveCall, setMic, toggleCamera, callView, setCallView } = useSession()
  const camLabel = call.video ? 'Turn camera off' : videoFull ? `Video full (${MAX_VIDEO}/${MAX_VIDEO})` : 'Turn camera on'
  return (
    <>
      <button type="button" aria-label={call.micOn ? 'Mute microphone' : 'Unmute microphone'} title={call.micOn ? 'Mute' : 'Unmute'}
        onClick={() => setMic(!call.micOn)} className={`${round} ${call.micOn ? 'hover:bg-white/10' : 'bg-red-500'}`}>
        {call.micOn ? <Mic className="size-4" /> : <MicOff className="size-4" />}
      </button>
      <button type="button" aria-label={camLabel} title={camLabel} onClick={toggleCamera} disabled={call.switching}
        className={`${round} ${call.video ? 'hover:bg-white/10' : videoFull ? 'opacity-50' : 'bg-white/15 hover:bg-white/25'}`}>
        {call.video ? <Video className="size-4" /> : <VideoOff className="size-4" />}
      </button>
      {callView === 'full' ? (
        <button type="button" aria-label="Exit full screen" title="Exit full screen" onClick={() => setCallView('panel')} className={`${round} hover:bg-white/10`}>
          <Minimize2 className="size-4" />
        </button>
      ) : (
        <button type="button" aria-label="Full screen" title="Full screen" onClick={() => setCallView('full')} className={`${round} hover:bg-white/10`}>
          <Maximize2 className="size-4" />
        </button>
      )}
      <button type="button" aria-label="Minimize call" title="Minimize (stay in the call)" onClick={() => setCallView('min')} className={`${round} hover:bg-white/10`}>
        <Minus className="size-4" />
      </button>
      <button type="button" aria-label="Leave call" title="Leave call" onClick={leaveCall}
        className={`${big ? 'flex h-9 items-center gap-1.5 rounded-full px-3 text-sm font-medium' : round} bg-red-600 hover:bg-red-700`}>
        <PhoneOff className="size-4" />
        {big && 'Leave'}
      </button>
    </>
  )
}

function useCallMembers() {
  const { call, callPeople, room } = useSession()
  const you = room?.snapshot?.you
  const myName = room?.snapshot?.players.find((p) => p.id === you)?.name ?? 'You'
  const others = [...callPeople.entries()].filter(([, p]) => p.id !== you)
  const onVideo = others.filter(([peer, p]) => p.video && call.remotes.has(peer))
  const onAudio = others.filter(([peer, p]) => !(p.video && call.remotes.has(peer)))
  const waiting = others.filter(([peer]) => !call.remotes.has(peer)).length
  return { myName, onVideo, onAudio, waiting }
}

function AudioList({ people, me, big }: { people: [string, CallPerson][]; me?: string; big?: boolean }) {
  const names = [...(me ? [me] : []), ...people.map(([, p]) => p.name)]
  if (!names.length) return null
  return (
    <p className={`flex items-center gap-1.5 rounded-lg bg-black/60 px-2 py-1 text-white/90 ${big ? 'text-sm' : 'max-w-48 text-[11px]'}`}>
      <Mic className="size-3 shrink-0" aria-hidden="true" />
      <span className="min-w-0 truncate">Audio: {names.join(', ')}</span>
    </p>
  )
}

/**
 * The call, whenever you're in one: a draggable floating panel, a full-screen
 * grid, or (minimized) nothing but the Call button in the header. Audio keeps
 * playing in every view.
 */
export function CallDock() {
  const { call, room, callView, videoFull } = useSession()
  const { myName, onVideo, onAudio, waiting } = useCallMembers()
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

  const showPanel = call.inCall && callView === 'panel'
  useEffect(() => {
    if (!showPanel) return
    // Restore the saved position once the panel is on screen (storage is browser-only).
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setPos(clamp(loadPos()))
    const onResize = () => setPos((p) => clamp(p))
    window.addEventListener('resize', onResize)
    // The panel grows as people join; keep all of it on screen.
    const ro = typeof ResizeObserver !== 'undefined' && boxRef.current ? new ResizeObserver(onResize) : null
    if (ro && boxRef.current) ro.observe(boxRef.current)
    return () => {
      window.removeEventListener('resize', onResize)
      ro?.disconnect()
    }
  }, [clamp, showPanel])

  if (!call.inCall || !room?.snapshot) return null

  // Audio for anyone without a visible tile.
  const tiled = new Set(callView === 'min' ? [] : onVideo.map(([peer]) => peer))
  const audio = [...call.remotes.entries()].filter(([peer]) => !tiled.has(peer)).map(([peer, s]) => <Audio key={peer} stream={s} />)
  const fullNote = !call.video && videoFull ? `Video is full (${MAX_VIDEO}/${MAX_VIDEO}). You can turn on your camera once someone turns theirs off.` : null

  if (callView === 'min') return <div hidden>{audio}</div>

  if (callView === 'full') {
    const tiles = [
      ...(call.video ? [<Stream key="me" stream={call.local} mine label={`${myName} (you)`} big />] : []),
      ...onVideo.map(([peer, p]) => <Stream key={peer} stream={call.remotes.get(peer)!} label={p.name} big />),
    ]
    const cols = tiles.length <= 1 ? 'grid-cols-1' : 'grid-cols-1 min-[560px]:grid-cols-2'
    return (
      <div className="fixed inset-0 z-50 flex flex-col gap-3 bg-[#0e0c12] p-3 text-white" role="dialog" aria-label="Video call, full screen">
        {audio}
        {tiles.length ? (
          <div className={`grid min-h-0 flex-1 auto-rows-fr gap-2 ${cols}`}>{tiles}</div>
        ) : (
          <p className="grid flex-1 place-items-center text-center text-white/70">Nobody has their camera on.</p>
        )}
        <div className="flex flex-col items-center gap-2">
          <AudioList people={onAudio} me={call.video ? undefined : `${myName} (you)`} big />
          {waiting > 0 && <p className="text-sm text-white/60">Connecting to {waiting}…</p>}
          {fullNote && <p className="text-center text-sm text-white/70">{fullNote}</p>}
          <div className="flex items-center gap-2 rounded-full bg-white/10 p-1.5">
            <Controls big />
          </div>
        </div>
      </div>
    )
  }

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
    savePos(pos)
  }
  function nudge(dx: number, dy: number) {
    const next = clamp({ x: pos.x + dx, y: pos.y + dy })
    setPos(next)
    savePos(next)
  }

  return (
    <div ref={boxRef} className="fixed z-30 flex flex-col items-start gap-2" style={{ left: pos.x, top: pos.y }} role="region" aria-label="Video call">
      {audio}
      <div className="flex items-center gap-0.5 rounded-full bg-[#1b1620]/95 p-1 text-white shadow-lg">
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
        <Controls />
      </div>
      {fullNote && <p className="max-w-56 rounded-lg bg-black/70 px-2 py-1 text-[11px] text-white/90">{fullNote}</p>}
      <div className="flex max-h-[60dvh] flex-col items-start gap-2 overflow-y-auto">
        {call.video && <Stream stream={call.local} mine label={`${myName} (you)`} />}
        {onVideo.map(([peer, p]) => (
          <Stream key={peer} stream={call.remotes.get(peer)!} label={p.name} />
        ))}
        <AudioList people={onAudio} me={call.video ? undefined : `${myName} (you)`} />
        {waiting > 0 && <p className="rounded bg-black/60 px-2 py-1 text-[11px] text-white/80">Connecting to {waiting}…</p>}
      </div>
    </div>
  )
}

/**
 * The Call button in the lobby and game header. Before you join it offers
 * video or audio. Once you're in, it just shows or minimizes the call:
 * every call control lives in the call panel itself.
 */
export function CallButton({ className = '' }: { className?: string }) {
  const { call, callPeople, joinCall, callView, setCallView, videoFull } = useSession()
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

  const people = [...callPeople.values()]
  const cams = people.filter((p) => p.video).length

  if (call.inCall) {
    const minimized = callView === 'min'
    return (
      <button
        type="button"
        onClick={() => setCallView(minimized ? 'panel' : 'min')}
        aria-label={minimized ? `Show call (${callPeople.size} in call)` : 'Minimize call'}
        aria-pressed={!minimized}
        className={`inline-flex items-center gap-1 rounded-md px-2 py-1 text-sm text-ok hover:bg-secondary ${minimized ? 'bg-ok/10' : ''} ${className}`}
      >
        {call.micOn ? <Video className="size-4" aria-hidden="true" /> : <MicOff className="size-4 text-destructive" aria-label="muted" />}
        In call ({callPeople.size})
      </button>
    )
  }

  const pick = (video: boolean) => () => {
    setMenu(false)
    joinCall(video)
  }

  return (
    <span ref={ref} className={`relative ${className}`}>
      <button
        type="button"
        onClick={() => setMenu((m) => !m)}
        aria-expanded={menu}
        aria-haspopup="menu"
        disabled={call.joining}
        className="inline-flex items-center gap-1 rounded-md px-2 py-1 text-sm text-muted-foreground hover:bg-secondary"
      >
        <Video className="size-4" aria-hidden="true" />
        {call.joining ? 'Joining…' : people.length ? `Call (${people.length})` : 'Call'}
      </button>
      {menu && (
        <span role="menu" className="absolute right-0 top-full z-40 mt-1 flex w-60 flex-col gap-1 rounded-lg border bg-card p-1.5 text-left text-foreground shadow-lg">
          <span className="px-2 pb-1 pt-0.5 text-xs text-muted-foreground">
            {people.length ? `In the call: ${people.map((p) => p.name).join(', ')}. ` : 'See and hear each other while you play. '}
            Cameras: {cams}/{MAX_VIDEO}.
          </span>
          <Button role="menuitem" size="sm" onClick={pick(true)} disabled={videoFull}>
            {videoFull ? `Video full (${MAX_VIDEO}/${MAX_VIDEO})` : 'Join with video'}
          </Button>
          <Button role="menuitem" size="sm" variant={videoFull ? 'default' : 'outline'} onClick={pick(false)}>Join with audio only</Button>
          {videoFull && <span className="px-2 text-xs text-muted-foreground">You can turn on your camera once someone turns theirs off.</span>}
        </span>
      )}
    </span>
  )
}
