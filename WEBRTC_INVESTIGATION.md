# WebRTC Configuration Investigation

## Problem Statement

Client peer-to-peer connections are failing — existing users cannot see new users join, and WebRTC data channels are not being established reliably.

---

## Architecture Overview

The app uses **Supabase Realtime** (Postgres Changes) as a signaling server for WebRTC. The signaling data (offers, answers, ICE candidates) is stored in a `peer_connections` JSONB column on the `rooms` table. When a user joins:

1. The joiner creates `RTCPeerConnection` objects and SDP offers for every existing peer
2. The offers are written to the `rooms` table via a Supabase `UPDATE`
3. Existing peers receive the update via a Realtime subscription, create answers, and write them back
4. ICE candidates trickle in via `onicecandidate` and are also written to the same `rooms` row

---

## Root Causes Identified

### 1. Stale Closure in the Supabase Subscription Callback (PRIMARY ISSUE)

**File:** `lib/connections-provider.tsx`

The `subscribeToRoom` function (line 285) sets up a Supabase Realtime subscription with a callback that invokes `handleSignalingUpdate`. The problem is that this callback captures `handleSignalingUpdate` **at subscription time**, and `handleSignalingUpdate` itself closes over the `peerConnections` **React state variable** — not a ref.

```
// subscribeToRoom captures handleSignalingUpdate at subscription time
.on('postgres_changes', { ... }, (payload) => {
    handleSignalingUpdate(payload.new)  // <-- stale closure
})
```

Since `peerConnections` is a state variable (`useState`), its value is frozen at whatever it was during the render cycle when `subscribeToRoom` was called. For the **host**, this means `peerConnections` is permanently an empty `Map()`. For the **joiner**, `peerConnections` is also empty because `setPeerConnections` (called during `handleJoinRoom`) is batched by React and hasn't flushed by the time `subscribeToRoom` is called.

**Consequences:**

- **Host side:** When the host receives an offer from a new joiner, `peerConnections.get(peerId)` returns `undefined` (stale empty map). The code creates a new `RTCPeerConnection` and processes the offer correctly on the **first** signaling update. However, subsequent updates (e.g., ICE candidates) also find `peerConnections.get(peerId) === undefined` and silently skip ICE candidate processing (lines 274-281) and answer processing (lines 265-270).

- **Joiner side:** When the joiner receives the host's answer, `peerConnections.get(peerId)` returns `undefined` (stale empty map), so `setRemoteDescription` is never called (line 267-269). The WebRTC connection stalls at the offer/answer phase and never completes.

Note: The codebase already has `peerConnectionsRef` (line 40) which is updated via `useEffect` (line 424), but `handleSignalingUpdate` reads `peerConnections` (the state variable) instead of `peerConnectionsRef.current`.

### 2. Non-Idempotent Offer Processing (Causes Repeated Re-creation)

Offers stored in the database are never removed or marked as "processed." Since the Supabase subscription fires on every `UPDATE` to the row (not just the first time an offer appears), `handleSignalingUpdate` re-processes the same offer on every subsequent database change — creating a brand-new `RTCPeerConnection` each time and discarding the previous one.

**Flow:**
1. Joiner writes offer → DB update triggers host's `handleSignalingUpdate`
2. Host creates a peer connection, creates an answer, writes answer to DB
3. The answer write triggers another DB update → host's `handleSignalingUpdate` fires again
4. The offer is still in the DB → host creates ANOTHER new peer connection, discarding the one from step 2
5. This cycle repeats with every ICE candidate update

### 3. Race Conditions in `updatePeerConnections` (Non-Atomic Read-Modify-Write)

`updatePeerConnections` performs a classic non-atomic read-modify-write:

```
1. Read current peer_connections (from roomRef.current or passed in)
2. Merge updates locally
3. Write entire merged object back via supabase.update()
```

If two peers write concurrently (e.g., the host writes an answer while the joiner writes ICE candidates), the second write overwrites the first because it was based on a stale read. This causes:

- Lost ICE candidates
- Lost answers
- Lost offers (in multi-peer scenarios)

This is especially problematic because ICE candidates trickle in rapidly — multiple `onicecandidate` events can fire within milliseconds, each triggering an `updatePeerConnections` call that races against the others.

### 4. Single STUN Server, No TURN Fallback

The `RTCPeerConnection` configuration (line 61-65) uses only a single Google STUN server:

```javascript
iceServers: [
    { urls: 'stun:stun.l.google.com:19302' },
]
```

While STUN works for many network configurations, users behind symmetric NATs or restrictive firewalls cannot establish peer-to-peer connections without a TURN relay server. This is a secondary issue — it won't affect users on the same network or simple NATs, but will cause failures for some percentage of real-world users.

---

## Investigation Routes

### Route A: Fix Stale Closures with Refs

**Effort:** Low  
**Impact:** High — directly addresses the primary failure mode

Replace all reads of the `peerConnections` state variable inside `handleSignalingUpdate` (and any other functions captured by the subscription closure) with reads from `peerConnectionsRef.current`. The ref is already maintained (lines 40, 424).

**Changes required:**
- In `handleSignalingUpdate`: replace `peerConnections.get(peerId)` with `peerConnectionsRef.current.get(peerId)` (3 occurrences at lines 242, 266, 276)
- Add idempotency checks so offers/answers are not re-processed (e.g., track processed offer IDs, or check `pc.signalingState` before re-processing)
- Ensure `setPeerConnections` updates are also reflected in `peerConnectionsRef` immediately (not just via the `useEffect` which runs after render)

**Pros:**
- Minimal code change, directly fixes the most impactful bug
- Keeps the existing architecture intact

**Cons:**
- Does not fix the race condition in `updatePeerConnections`
- The signaling-via-database approach remains fragile for multi-peer scenarios

### Route B: Replace DB-Based Signaling with Supabase Realtime Broadcast

**Effort:** Medium  
**Impact:** High — eliminates race conditions and stale state issues entirely

Instead of storing signaling data (offers, answers, ICE candidates) in the `peer_connections` JSONB column and relying on Postgres Change events, use **Supabase Realtime Broadcast** to send signaling messages directly between peers. The `rooms` table would only store room metadata and the player list.

**Changes required:**
- Use `supabase.channel('room-XXX').send({ type: 'broadcast', event: 'signal', payload: { from, to, offer/answer/candidate } })` for all signaling
- Listen with `.on('broadcast', { event: 'signal' }, callback)` instead of `postgres_changes`
- Keep the `rooms` table for room creation/lookup and player presence, but remove signaling data from it
- The `peer_connections` column would only store `{ peerId: { playerName, isHost } }` — no offers/answers/ICE

**Pros:**
- No race conditions — messages are ephemeral, not stored
- No stale data — each signaling message is processed exactly once
- Much lower latency (broadcast is faster than DB write → Postgres change → Realtime push)
- Simpler merge logic — no need for `mergePeerConnections`, `mergeIceCandidates`, etc.
- Scales better to many peers

**Cons:**
- Requires more significant refactoring
- Signaling messages can be lost if a peer isn't subscribed yet (need a "ready" handshake)
- Slightly different failure modes to handle

### Route C: Add TURN Server Configuration

**Effort:** Low  
**Impact:** Medium — addresses connectivity for restrictive networks but doesn't fix the signaling bugs

Add TURN server credentials to the `RTCPeerConnection` configuration. Free/paid TURN options include Twilio, Metered.ca, or self-hosted coturn.

```javascript
iceServers: [
    { urls: 'stun:stun.l.google.com:19302' },
    {
        urls: 'turn:your-turn-server.com:3478',
        username: 'user',
        credential: 'pass'
    }
]
```

**Pros:**
- Quick to implement
- Fixes connectivity for users behind symmetric NATs

**Cons:**
- Does NOT fix the signaling bugs (Routes A/B) — connections will still fail regardless of TURN
- TURN servers have ongoing cost
- Should be done AFTER the signaling bugs are fixed

---

## Recommendation

**Start with Route A (fix stale closures), then migrate to Route B (Realtime Broadcast) as a follow-up.**

### Rationale

Route A is the fastest path to getting connections working. The stale closure is the single biggest reason existing users can't see new users — the answer/ICE processing is silently skipped because `peerConnections.get()` always returns `undefined` from the stale empty map. Fixing this with refs and adding idempotency guards should take minimal effort and immediately unblock peer-to-peer connections.

However, Route A is a patch on a fundamentally fragile architecture. Storing mutable signaling state in a single JSONB column and relying on non-atomic read-modify-write is inherently race-prone, and it will cause intermittent failures in rooms with 3+ peers. Route B (Supabase Realtime Broadcast) is the correct long-term architecture — it eliminates the entire class of race conditions and makes signaling both simpler and faster.

Route C (TURN servers) should be added eventually but is orthogonal to the current failures. The connections are failing at the signaling layer, not the ICE/NAT traversal layer.

### Suggested Implementation Order

1. **Immediate fix (Route A):** Use `peerConnectionsRef.current` in `handleSignalingUpdate`, add idempotency checks
2. **Short-term follow-up (Route B):** Migrate signaling to Supabase Broadcast
3. **Later (Route C):** Add TURN server for production reliability
