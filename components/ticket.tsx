'use client'

import { Check, Link2, Share2 } from 'lucide-react'
import { useState } from 'react'

export function inviteLink(code: string) {
  const url = new URL(window.location.href)
  url.search = ''
  url.hash = ''
  url.searchParams.set('room', code)
  return url.toString()
}

/** The room code as an admission ticket: the thing people read out loud. */
export default function Ticket({ code }: { code: string }) {
  const [copied, setCopied] = useState(false)
  const canShare = typeof navigator !== 'undefined' && 'share' in navigator

  async function copy() {
    try {
      await navigator.clipboard.writeText(inviteLink(code))
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      window.prompt('Copy this invite link:', inviteLink(code))
    }
  }

  async function share() {
    try {
      await navigator.share({ title: 'Join my game', text: `Room code ${code}`, url: inviteLink(code) })
    } catch {
      /* user cancelled */
    }
  }

  return (
    <div className="ticket px-8 pb-4 pt-5 text-center">
      <p className="text-sm font-medium opacity-80">Room code</p>
      <p
        className="font-display text-6xl font-extrabold tracking-[0.12em]"
        aria-label={`Room code ${code.split('').join(' ')}`}
      >
        {code}
      </p>
      <div className="mt-3 flex justify-center gap-2 border-t border-dashed border-ticket-ink/30 pt-3">
        <button
          type="button"
          onClick={copy}
          className="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium hover:bg-ticket-ink/10"
        >
          {copied ? <Check className="size-4" /> : <Link2 className="size-4" />}
          {copied ? 'Link copied' : 'Copy invite link'}
        </button>
        {canShare && (
          <button
            type="button"
            onClick={share}
            className="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium hover:bg-ticket-ink/10"
          >
            <Share2 className="size-4" />
            Share
          </button>
        )}
      </div>
    </div>
  )
}
