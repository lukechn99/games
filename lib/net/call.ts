/**
 * Video call: a small mesh. Everyone in the call opens a direct media
 * connection to everyone else, reusing the PeerJS peer their session already
 * has. The room only tracks who's in the call, their peer address and
 * whether they hold one of the camera slots; audio and video never pass
 * through the host.
 *
 * To avoid two people calling each other at once, the one whose peer id
 * sorts first places the call and the other answers.
 *
 * Cameras switch on and off mid-call. Where a connection already sends
 * video, the track is swapped in place; otherwise that one connection is
 * re-dialled with the new stream, so nobody's audio drops.
 */
import type { MediaConnection, Peer } from 'peerjs'

export interface CallSnapshot {
  inCall: boolean
  joining: boolean
  /** Our camera is on and sending. */
  video: boolean
  /** A camera change is in progress. */
  switching: boolean
  micOn: boolean
  local: MediaStream | null
  /** Remote streams by peer id. */
  remotes: Map<string, MediaStream>
  error: string | null
}

const CAMERA: MediaTrackConstraints = { facingMode: 'user', width: { ideal: 320 }, height: { ideal: 240 }, frameRate: { ideal: 15 } }
// Offer to receive video even when we aren't sending any, so other
// people's cameras reach audio-only participants.
const CALL_OPTIONS = { constraints: { offerToReceiveAudio: true, offerToReceiveVideo: true } }

function mediaError(err: unknown): string {
  const name = (err as { name?: string })?.name
  if (name === 'NotAllowedError') return 'Camera or microphone access was blocked. Allow it in your browser settings, then try again.'
  if (name === 'NotFoundError') return 'No camera or microphone was found.'
  return "Couldn't start your camera or microphone."
}

export class CallManager {
  private peer: Peer | null = null
  private bound = new WeakSet<Peer>()
  private local: MediaStream | null = null
  private calls = new Map<string, MediaConnection>()
  private remotes = new Map<string, MediaStream>()
  private want: string[] = []
  private state: Omit<CallSnapshot, 'local' | 'remotes' | 'video'> = {
    inCall: false, joining: false, switching: false, micOn: true, error: null,
  }

  constructor(private onChange: () => void) {}

  snapshot(): CallSnapshot {
    const video = !!this.local?.getVideoTracks().some((t) => t.readyState === 'live')
    return { ...this.state, video, local: this.local, remotes: new Map(this.remotes) }
  }

  get peerId(): string | null {
    return this.peer?.open ? this.peer.id : null
  }

  /** Called whenever the session's peer (re)connects. */
  setPeer(peer: Peer | null) {
    if (peer === this.peer) return
    for (const c of this.calls.values()) c.close()
    this.calls.clear()
    this.remotes.clear()
    this.peer = peer
    if (peer && !this.bound.has(peer)) {
      this.bound.add(peer)
      peer.on('call', (call) => {
        if (peer !== this.peer || !this.local) {
          call.close()
          return
        }
        this.calls.get(call.peer)?.close()
        call.answer(this.local)
        this.track(call)
      })
    }
    this.sync(this.want)
    this.onChange()
  }

  async join(video: boolean): Promise<boolean> {
    if (this.state.inCall || this.state.joining) return this.state.inCall
    this.state = { ...this.state, joining: true, error: null }
    this.onChange()
    try {
      const audio = { echoCancellation: true, noiseSuppression: true }
      try {
        this.local = await navigator.mediaDevices.getUserMedia({ audio, video: video ? CAMERA : false })
      } catch (err) {
        // No camera (or it's blocked)? Still join on audio.
        if (!video) throw err
        this.local = await navigator.mediaDevices.getUserMedia({ audio, video: false })
        this.state = { ...this.state, error: mediaError(err) }
      }
      this.state = { ...this.state, inCall: true, joining: false, micOn: true }
      this.onChange()
      this.sync(this.want)
      return true
    } catch (err) {
      this.state = { ...this.state, joining: false, error: mediaError(err) }
      this.onChange()
      return false
    }
  }

  leave() {
    for (const c of this.calls.values()) c.close()
    this.calls.clear()
    this.remotes.clear()
    this.local?.getTracks().forEach((t) => t.stop())
    this.local = null
    this.state = { ...this.state, inCall: false, joining: false, switching: false }
    this.onChange()
  }

  setMic(on: boolean) {
    this.local?.getAudioTracks().forEach((t) => (t.enabled = on))
    this.state = { ...this.state, micOn: on }
    this.onChange()
  }

  /** Turn the camera on or off. Resolves false if the camera couldn't start. */
  async setVideo(on: boolean): Promise<boolean> {
    const local = this.local
    if (!local || this.state.switching || this.snapshot().video === on) return true
    if (!on) {
      for (const t of local.getVideoTracks()) {
        t.stop()
        local.removeTrack(t)
      }
      for (const c of this.calls.values()) void this.videoSender(c)?.replaceTrack(null)
      this.onChange()
      return true
    }
    this.state = { ...this.state, switching: true, error: null }
    this.onChange()
    try {
      const cam = await navigator.mediaDevices.getUserMedia({ video: CAMERA })
      const track = cam.getVideoTracks()[0]!
      if (this.local !== local) {
        track.stop()
        return false
      }
      local.addTrack(track)
      for (const [id, c] of [...this.calls]) {
        const sender = this.videoSender(c)
        if (sender) void sender.replaceTrack(track)
        else this.redial(id)
      }
      return true
    } catch (err) {
      this.state = { ...this.state, error: mediaError(err) }
      return false
    } finally {
      this.state = { ...this.state, switching: false }
      this.onChange()
    }
  }

  /** The sender for our video, if this connection already negotiated sending it. */
  private videoSender(c: MediaConnection): RTCRtpSender | null {
    const pc = c.peerConnection
    if (!pc) return null
    const tx = pc.getTransceivers().find((t) => t.receiver.track?.kind === 'video')
    const dir = tx?.currentDirection
    return tx && (dir === 'sendrecv' || dir === 'sendonly') ? tx.sender : null
  }

  /** Replace one connection with a fresh one carrying our current tracks. */
  private redial(id: string) {
    if (!this.peer || !this.local) return
    const old = this.calls.get(id)
    const call = this.peer.call(id, this.local, CALL_OPTIONS as never)
    if (call) this.track(call)
    old?.close()
  }

  /** Bring connections in line with who the room says is in the call. */
  sync(participants: string[]) {
    this.want = participants
    const me = this.peerId
    if (!this.state.inCall || !this.local || !this.peer || !me) return
    const others = new Set(participants.filter((p) => p !== me))
    for (const [id, c] of this.calls) {
      if (!others.has(id)) {
        c.close()
        this.calls.delete(id)
        this.remotes.delete(id)
      }
    }
    for (const id of others) {
      if (this.calls.has(id) || me > id) continue
      const call = this.peer.call(id, this.local, CALL_OPTIONS as never)
      if (call) this.track(call)
    }
    this.onChange()
  }

  private track(call: MediaConnection) {
    this.calls.set(call.peer, call)
    call.on('stream', (stream) => {
      if (this.calls.get(call.peer) !== call) return
      this.remotes.set(call.peer, stream)
      this.onChange()
    })
    const gone = () => {
      if (this.calls.get(call.peer) !== call) return
      this.calls.delete(call.peer)
      this.remotes.delete(call.peer)
      this.onChange()
      // If they're still in the call, try again shortly (e.g. after a network blip).
      setTimeout(() => this.sync(this.want), 2000)
    }
    call.on('close', gone)
    call.on('error', gone)
  }
}
