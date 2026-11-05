import { describe, expect, it } from 'vitest'
import {
  applyAction,
  createRoom,
  joinRoom,
  removePlayer,
  setConnected,
  snapshotFor,
  tickRoom,
} from '@/lib/engine/room'
import type { RoomState, RuleContext } from '@/lib/engine/types'
import { getGameModule } from '@/lib/games/modules'
import { ROUND_MS, VOTE_MS, type SpyfallState, type SpyfallView } from '@/lib/games/spyfall/rules'

function ctx(now = 1000, seq: number[] = [0]): RuleContext {
  let i = 0
  return { now, random: () => seq[i++ % seq.length]! }
}

function mustJoin(room: RoomState, id: string, name: string) {
  const r = joinRoom(room, { id, name }, 1000)
  if ('error' in r) throw new Error(r.error)
  return r
}

function ok(r: ReturnType<typeof applyAction>): RoomState {
  if ('error' in r) throw new Error(r.error)
  return r.state
}

function roomWith(n: number): RoomState {
  let room = createRoom('ABCDE', { id: 'p0', name: 'Host' }, 0)
  for (let i = 1; i < n; i++) room = mustJoin(room, `p${i}`, `P${i}`).room
  return room
}

function startSpyfall(room: RoomState, c = ctx()): RoomState {
  room = ok(applyAction(room, 'p0', { type: 'selectGame', gameId: 'spyfall' }, c, getGameModule))
  return ok(applyAction(room, 'p0', { type: 'startGame' }, c, getGameModule))
}

const sf = (room: RoomState) => room.game!.state as SpyfallState

describe('joining and rejoining', () => {
  it('gives a reconnecting player their old seat', () => {
    let room = roomWith(3)
    room = setConnected(room, 'p1', false)
    const r = mustJoin(room, 'p1', 'P1')
    expect(r.rejoined).toBe(true)
    expect(r.room.players).toHaveLength(3)
    expect(r.room.players.find((p) => p.id === 'p1')!.connected).toBe(true)
  })

  it('lets a disconnected player reclaim their seat by name from a new device', () => {
    let room = roomWith(3)
    room = setConnected(room, 'p2', false)
    const r = mustJoin(room, 'new-device', 'p2')
    expect(r.playerId).toBe('p2')
    expect(r.room.players).toHaveLength(3)
  })

  it('does not let a newcomer steal a connected player by name', () => {
    const room = roomWith(2)
    const r = mustJoin(room, 'x', 'P1')
    expect(r.playerId).toBe('x')
    expect(r.room.players.find((p) => p.id === 'x')!.name).toBe('P1 2')
  })

  it('keeps a seat in a running game across a disconnect', () => {
    let room = startSpyfall(roomWith(4))
    room = setConnected(room, 'p3', false)
    room = mustJoin(room, 'p3', 'P3').room
    expect(room.game!.seats).toContain('p3')
    const view = snapshotFor(room, 'p3', getGameModule, 0).game!.view as SpyfallView
    expect(view.isSpy).not.toBeNull()
  })

  it('makes late joiners spectators who cannot see the location', () => {
    let room = startSpyfall(roomWith(3))
    room = mustJoin(room, 'late', 'Late').room
    const view = snapshotFor(room, 'late', getGameModule, 0).game!.view as SpyfallView
    expect(view.isSpy).toBeNull()
    expect(view.location).toBeNull()
    const r = applyAction(room, 'late', { type: 'game', action: { type: 'callVote', on: true } }, ctx(), getGameModule)
    expect('error' in r).toBe(true)
  })
})

describe('host controls', () => {
  it('only lets the host start, end and kick', () => {
    const room = roomWith(3)
    for (const action of [
      { type: 'selectGame', gameId: 'spyfall' },
      { type: 'startGame' },
      { type: 'kick', playerId: 'p2' },
    ] as const) {
      expect('error' in applyAction(room, 'p1', action, ctx(), getGameModule)).toBe(true)
    }
  })

  it('refuses to start with too few connected players', () => {
    let room = roomWith(3)
    room = setConnected(room, 'p2', false)
    room = ok(applyAction(room, 'p0', { type: 'selectGame', gameId: 'spyfall' }, ctx(), getGameModule))
    const r = applyAction(room, 'p0', { type: 'startGame' }, ctx(), getGameModule)
    expect(r).toEqual({ error: 'Spyfall needs at least 3 connected players.' })
  })

  it('removes a kicked player from the room and the game', () => {
    let room = startSpyfall(roomWith(4), ctx(0, [0])) // p0 is spy
    room = ok(applyAction(room, 'p0', { type: 'kick', playerId: 'p3' }, ctx(), getGameModule))
    expect(room.players.map((p) => p.id)).not.toContain('p3')
    expect(sf(room).players).not.toContain('p3')
    expect(sf(room).phase).toBe('playing')
  })

  it('play again starts a fresh round with everyone connected', () => {
    let room = startSpyfall(roomWith(3))
    room = mustJoin(room, 'late', 'Late').room
    room = ok(applyAction(room, 'p0', { type: 'playAgain' }, ctx(), getGameModule))
    expect(room.game!.round).toBe(2)
    expect(room.game!.seats).toContain('late')
  })
})

describe('spyfall', () => {
  // random() always 0 → spy = p0, location = first, firstAsker = p0
  const start = () => startSpyfall(roomWith(4), ctx(0, [0]))
  const act = (room: RoomState, who: string, action: object, now = 1000) =>
    ok(applyAction(room, who, { type: 'game', action }, ctx(now), getGameModule))

  it('hides the location from the spy only', () => {
    const room = start()
    const spyView = snapshotFor(room, 'p0', getGameModule, 0).game!.view as SpyfallView
    const agentView = snapshotFor(room, 'p1', getGameModule, 0).game!.view as SpyfallView
    expect(spyView.isSpy).toBe(true)
    expect(spyView.location).toBeNull()
    expect(agentView.location).toBe('Airplane')
    expect(agentView.spy).toBeNull()
  })

  it('starts voting when a majority calls for it, and agents win by catching the spy', () => {
    let room = start()
    room = act(room, 'p1', { type: 'callVote', on: true })
    room = act(room, 'p2', { type: 'callVote', on: true })
    expect(sf(room).phase).toBe('playing')
    room = act(room, 'p3', { type: 'callVote', on: true })
    expect(sf(room).phase).toBe('voting')
    room = act(room, 'p0', { type: 'vote', target: 'p1' })
    room = act(room, 'p1', { type: 'vote', target: 'p0' })
    room = act(room, 'p2', { type: 'vote', target: 'p0' })
    room = act(room, 'p3', { type: 'vote', target: 'p0' })
    expect(sf(room).result).toMatchObject({ winner: 'agents', accused: 'p0' })
  })

  it('treats a tied vote as a spy win', () => {
    let room = start()
    room = { ...room, game: { ...room.game!, state: { ...sf(room), phase: 'voting', voteEndsAt: 99999 } } }
    room = act(room, 'p0', { type: 'vote', target: 'p1' })
    room = act(room, 'p1', { type: 'vote', target: 'p0' })
    room = act(room, 'p2', { type: 'vote', target: 'p1' })
    room = act(room, 'p3', { type: 'vote', target: 'p0' })
    expect(sf(room).result?.winner).toBe('spy')
  })

  it('lets the spy win by guessing the location', () => {
    const room = act(start(), 'p0', { type: 'guessLocation', location: 'Airplane' })
    expect(sf(room).result).toMatchObject({ winner: 'spy', spyGuess: 'Airplane' })
  })

  it('rejects location guesses from agents', () => {
    const r = applyAction(start(), 'p1', { type: 'game', action: { type: 'guessLocation', location: 'Bank' } }, ctx(), getGameModule)
    expect('error' in r).toBe(true)
  })

  it('moves to voting when the clock runs out, then resolves when voting times out', () => {
    let room = start()
    room = tickRoom(room, ctx(ROUND_MS + 1), getGameModule)
    expect(sf(room).phase).toBe('voting')
    room = act(room, 'p1', { type: 'vote', target: 'p0' }, ROUND_MS + 2)
    room = tickRoom(room, ctx(ROUND_MS + 2 + VOTE_MS), getGameModule)
    expect(sf(room).result).toMatchObject({ winner: 'agents', accused: 'p0' })
  })

  it('tick returns the same room when nothing changes', () => {
    const room = start()
    expect(tickRoom(room, ctx(5), getGameModule)).toBe(room)
  })

  it('ends the round if the spy leaves', () => {
    let room = start()
    room = { ...room, game: { ...room.game!, state: { ...sf(room), spy: 'p2' } } }
    room = removePlayer(room, 'p2', ctx(), getGameModule)
    expect(sf(room).result?.winner).toBe('none')
  })
})

describe('video call membership', () => {
  it('tracks who is in the call and drops people who disconnect', () => {
    let room = roomWith(3)
    room = ok(applyAction(room, 'p1', { type: 'call', peer: 'peer-1', video: true }, ctx(), getGameModule))
    room = ok(applyAction(room, 'p2', { type: 'call', peer: 'peer-2', video: false }, ctx(), getGameModule))
    expect(room.players.find((p) => p.id === 'p2')!.call).toEqual({ peer: 'peer-2', video: false })
    room = ok(applyAction(room, 'p1', { type: 'call', peer: null }, ctx(), getGameModule))
    expect(room.players.find((p) => p.id === 'p1')!.call).toBeUndefined()
    room = setConnected(room, 'p2', false)
    expect(room.players.find((p) => p.id === 'p2')!.call).toBeUndefined()
  })

  it('allows four cameras; later joiners come in on audio and can turn video on once a slot frees', () => {
    let room = roomWith(6)
    const call = (id: string, video: boolean, peer: string | null = `peer-${id}`) =>
      applyAction(room, id, { type: 'call', peer, video }, ctx(), getGameModule)
    for (const id of ['p1', 'p2', 'p3', 'p4']) room = ok(call(id, true))
    room = ok(call('p5', true))
    expect(room.players.find((p) => p.id === 'p5')!.call).toEqual({ peer: 'peer-p5', video: false })
    expect(call('p5', true)).toHaveProperty('error')
    room = ok(call('p2', false))
    room = ok(call('p5', true))
    expect(room.players.filter((p) => p.call?.video).map((p) => p.id).sort()).toEqual(['p1', 'p3', 'p4', 'p5'])
    // Re-announcing an existing camera is always fine.
    room = ok(call('p1', true))
  })
})
