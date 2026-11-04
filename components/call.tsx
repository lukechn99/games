'use client'

import { ChevronDown, ChevronUp, Mic, MicOff, PhoneOff, Video, VideoOff } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'
import { useSession } from '@/lib/session'
import { Button } from './ui/button'

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

/** Floating strip of call tiles, shown while you're in the call. */
export function CallDock() {
  const { call, callNames, room, leaveCall, setMic, setCam } = useSession()
  const [open, setOpen] = useState(true)
  if (!call.inCall || !room?.snapshot) return null
  const myName = room.snapshot.players.find((p) => p.id === room.snapshot!.you)?.name ?? 'You'
  const remotes = [...callNames.entries()].filter(([peer]) => peer !== undefined)
  const others = remotes.filter(([peer]) => call.remotes.has(peer) || !callNames.has(peer))
  const waiting = remotes.length - 1 - others.length

  return (
    <div className="fixed left-2 top-16 z-30 flex max-h-[70dvh] flex-col items-start gap-2" role="region" aria-label="Video call">
      <div className="flex items-center gap-1 rounded-full bg-[#1b1620]/95 p-1 text-white shadow-lg">
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
        <button type="button" aria-label={open ? 'Hide video' : 'Show video'} onClick={() => setOpen((o) => !o)}
          className="flex h-9 items-center gap-1 rounded-full px-2 text-xs hover:bg-white/10">
          {remotes.length} {open ? <ChevronUp className="size-4" /> : <ChevronDown className="size-4" />}
        </button>
      </div>
      {open && (
        <div className="flex max-h-[60dvh] flex-col gap-2 overflow-y-auto">
          <Stream stream={call.local} muted label={`${myName} (you)`} off={!call.camOn} />
          {[...callNames.entries()]
            .filter(([peer]) => call.remotes.has(peer))
            .map(([peer, name]) => (
              <Stream key={peer} stream={call.remotes.get(peer)!} label={name} />
            ))}
          {waiting > 0 && <p className="rounded bg-black/60 px-2 py-1 text-[11px] text-white/80">Connecting to {waiting}…</p>}
        </div>
      )}
    </div>
  )
}

/** Compact header control: join the call, or show how many are in it. */
export function CallButton() {
  const { call, callNames, joinCall } = useSession()
  const [menu, setMenu] = useState(false)
  if (call.inCall) {
    return (
      <span className="inline-flex items-center gap-1 rounded-md px-2 py-1 text-sm text-ok">
        <Video className="size-4" aria-hidden="true" /> {callNames.size}
      </span>
    )
  }
  return (
    <span className="relative">
      <button type="button" onClick={() => setMenu((m) => !m)} aria-expanded={menu} disabled={call.joining}
        className="inline-flex items-center gap-1 rounded-md px-2 py-1 text-sm text-muted-foreground hover:bg-secondary">
        <Video className="size-4" aria-hidden="true" />
        {call.joining ? 'Joining…' : callNames.size ? `Call (${callNames.size})` : 'Call'}
      </button>
      {menu && (
        <span className="absolute right-0 top-full z-40 mt-1 flex w-48 flex-col gap-1 rounded-lg border bg-card p-1.5 shadow-lg">
          <Button size="sm" onClick={() => { setMenu(false); joinCall(true) }}>Join with video</Button>
          <Button size="sm" variant="outline" onClick={() => { setMenu(false); joinCall(false) }}>Join with audio only</Button>
        </span>
      )}
    </span>
  )
}

/** Lobby card for the call. */
export function CallCard() {
  const { call, callNames, joinCall, leaveCall } = useSession()
  return (
    <section aria-labelledby="call-heading" className="rounded-lg border bg-card p-4">
      <h2 id="call-heading" className="font-display text-xl font-bold">Video call</h2>
      <p className="mt-1 text-sm text-muted-foreground">
        {callNames.size
          ? `In the call: ${[...callNames.values()].join(', ')}.`
          : 'Playing apart? See and hear each other while you play. Video goes straight between phones.'}
      </p>
      <div className="mt-3 flex flex-wrap gap-2">
        {call.inCall ? (
          <Button variant="outline" onClick={leaveCall}>Leave call</Button>
        ) : (
          <>
            <Button disabled={call.joining} onClick={() => joinCall(true)}>{call.joining ? 'Joining…' : 'Join with video'}</Button>
            <Button variant="outline" disabled={call.joining} onClick={() => joinCall(false)}>Audio only</Button>
          </>
        )}
      </div>
    </section>
  )
}
