'use client'

import { useEffect, useState, type FormEvent } from 'react'
import type { RoomState } from '@/lib/engine/types'
import { COMING_SOON, GAME_MODULES } from '@/lib/games/modules'
import { CODE_LENGTH, isValidCode, normalizeCode } from '@/lib/net/config'
import { clearHostedRoom, getResumableHostedRoom, getSavedName } from '@/lib/net/storage'
import { useSession } from '@/lib/session'
import { playerRange } from '@/lib/utils'
import { Button } from './ui/button'
import { Input } from './ui/input'

export default function Home() {
  const { createRoom, joinRoom, resumeHosting, linkCode } = useSession()
  const [name, setName] = useState('')
  const [code, setCode] = useState(linkCode ?? '')
  const [nameError, setNameError] = useState<string | null>(null)
  const [codeError, setCodeError] = useState<string | null>(null)
  const [resumable, setResumable] = useState<RoomState | null>(null)

  useEffect(() => {
    // Storage is only available in the browser, so read it after mount.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setName(getSavedName())
    setResumable(getResumableHostedRoom())
  }, [])

  const trimmed = name.trim()

  function requireName(): boolean {
    if (trimmed) return true
    setNameError('Enter your name first.')
    document.getElementById('name')?.focus()
    return false
  }

  function onJoin(e: FormEvent) {
    e.preventDefault()
    if (!requireName()) return
    if (!isValidCode(code)) {
      setCodeError(`Room codes are ${CODE_LENGTH} letters and numbers.`)
      document.getElementById('code')?.focus()
      return
    }
    joinRoom(code, trimmed)
  }

  function onCreate() {
    if (!requireName()) return
    createRoom(trimmed)
  }

  return (
    <main className="mx-auto flex min-h-dvh max-w-md flex-col px-6 pb-10 pt-14">
      <h1 className="font-display text-5xl font-extrabold leading-none tracking-tight">Game Night</h1>
      <p className="mt-3 text-lg text-muted-foreground">
        Party games for the people in the room. Everyone joins from their own phone.
      </p>

      <label className="mt-10 flex flex-col gap-2">
        <span className="font-display text-lg font-bold">Your name</span>
        <Input
          id="name"
          value={name}
          autoComplete="nickname"
          maxLength={20}
          placeholder="e.g. Sam"
          aria-invalid={!!nameError}
          onChange={(e) => {
            setName(e.target.value)
            setNameError(null)
          }}
          className="h-12 text-base"
        />
        {nameError && (
          <span className="text-sm text-destructive" role="alert">
            {nameError}
          </span>
        )}
      </label>

      <div className="mt-8 flex flex-col gap-4">
        {linkCode ? null : (
          <section className="rounded-xl border bg-card p-5">
            <h2 className="font-display text-lg font-bold">Host a game</h2>
            <p className="mt-1 text-sm text-muted-foreground">Get a room code to share with everyone else.</p>
            <Button size="lg" className="mt-4 h-12 w-full text-base" onClick={onCreate}>
              Create a room
            </Button>
          </section>
        )}

        <form onSubmit={onJoin} noValidate className="rounded-xl border bg-card p-5">
          <h2 className="font-display text-lg font-bold">{linkCode ? `Join room ${linkCode}` : 'Join a friend'}</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            {linkCode ? 'You were invited. Check your name above, then join.' : 'Type the code from the host’s screen.'}
          </p>
          <div className="mt-4 flex gap-2">
            <label htmlFor="code" className="sr-only">
              Room code
            </label>
            <Input
              id="code"
              value={code}
              inputMode="text"
              autoCapitalize="characters"
              autoComplete="off"
              spellCheck={false}
              placeholder="ABCDE"
              aria-invalid={!!codeError}
              onChange={(e) => {
                setCode(normalizeCode(e.target.value))
                setCodeError(null)
              }}
              className="h-12 flex-1 font-display text-xl font-bold uppercase tracking-[0.2em]"
            />
            <Button type="submit" size="lg" variant={linkCode ? 'default' : 'outline'} className="h-12 px-6">
              Join
            </Button>
          </div>
          {codeError && (
            <p className="mt-2 text-sm text-destructive" role="alert">
              {codeError}
            </p>
          )}
        </form>

        {linkCode && (
          <button type="button" onClick={onCreate} className="self-center text-sm text-muted-foreground underline-offset-4 hover:underline">
            Host a new room instead
          </button>
        )}
      </div>

      {resumable && (
        <div className="mt-6 rounded-lg border p-4">
          <p className="font-medium">You were hosting room {resumable.code}</p>
          <p className="mt-1 text-sm text-muted-foreground">
            {resumable.game ? 'A game was in progress. ' : ''}Reopen it and players will reconnect.
          </p>
          <div className="mt-3 flex gap-2">
            <Button size="sm" onClick={() => resumeHosting(resumable)}>
              Reopen room
            </Button>
            <Button
              size="sm"
              variant="ghost"
              onClick={() => {
                clearHostedRoom(resumable.code)
                setResumable(null)
              }}
            >
              Discard
            </Button>
          </div>
        </div>
      )}

      <section className="mt-auto pt-12">
        <h2 className="text-sm font-medium text-muted-foreground">Games</h2>
        <ul className="mt-3 flex flex-col gap-2 text-sm">
          {GAME_MODULES.map((g) => (
            <li key={g.id} className="flex justify-between">
              <span className="font-medium">{g.name}</span>
              <span className="text-muted-foreground">{playerRange(g.minPlayers, g.maxPlayers)}</span>
            </li>
          ))}
          {COMING_SOON.map((g) => (
            <li key={g.name} className="flex justify-between text-muted-foreground">
              <span>{g.name}</span>
              <span>Coming soon</span>
            </li>
          ))}
        </ul>
      </section>
    </main>
  )
}
