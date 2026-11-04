/**
 * Video call: a small mesh. Everyone in the call opens a direct media
 * connection to everyone else, reusing the PeerJS peer their session already
 * has. The room only tracks who's in the call and their peer address;
 * audio and video never pass through the host.
 *
 * To avoid two people calling each other at once, the one whose peer id
 * sorts first places the call and the other answers.
 */
import type { MediaConnection, Peer } from 'peerjs'

export interface CallSnapshot {
  inCall: boolean
  joining: boolean
  video: boolean
  micOn: boolean
  camOn: boolean
  local: MediaStream | null
  /** Remote streams by peer id. */
  remotes: Map<string, MediaStream>
  error: string | null
}

export class CallManager {
  private peer: Peer | null = null
  private bound = new WeakSet<Peer>()
  private local: MediaStream | null = null
  private calls = new Map<string, MediaConnection>()
  private remotes = new Map<string, MediaStream>()
  private want: string[] = []
  private state: Omit<CallSnapshot, 'local' | 'remotes'> = {
    inCall: false, joining: false, video: true, micOn: true, camOn: true, error: null,
  }

  constructor(private onChange: () => void) {}

  snapshot(): CallSnapshot {
    return { ...this.state, local: this.local, remotes: new Map(this.remotes) }
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
      this.local = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: true, noiseSuppression: true },
        video: video ? { facingMode: 'user', width: { ideal: 320 }, height: { ideal: 240 }, frameRate: { ideal: 15 } } : false,
      })
      this.state = { ...this.state, inCall: true, joining: false, video, micOn: true, camOn: video }
      this.onChange()
      this.sync(this.want)
      return true
    } catch (err) {
      const name = (err as { name?: string })?.name
      const msg =
        name === 'NotAllowedError'
          ? 'Camera or microphone access was blocked. Allow it in your browser settings, then try again.'
          : name === 'NotFoundError'
            ? 'No camera or microphone was found.'
            : "Couldn't start your camera or microphone."
      this.state = { ...this.state, joining: false, error: msg }
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
    this.state = { ...this.state, inCall: false, joining: false }
    this.onChange()
  }

  setMic(on: boolean) {
    this.local?.getAudioTracks().forEach((t) => (t.enabled = on))
    this.state = { ...this.state, micOn: on }
    this.onChange()
  }

  setCam(on: boolean) {
    this.local?.getVideoTracks().forEach((t) => (t.enabled = on))
    this.state = { ...this.state, camOn: on }
    this.onChange()
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
      const call = this.peer.call(id, this.local)
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
