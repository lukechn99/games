'use client'

import { X } from 'lucide-react'
import { useSession } from '@/lib/session'

export default function Notices() {
  const { notices, dismissNotice } = useSession()
  if (notices.length === 0) return null
  return (
    <div
      className="fixed inset-x-0 bottom-24 z-50 flex flex-col items-center gap-2 px-4 pointer-events-none"
      role="status"
      aria-live="polite"
    >
      {notices.map((n) => (
        <div
          key={n.id}
          className="pointer-events-auto flex max-w-sm items-start gap-3 rounded-lg bg-foreground px-4 py-3 text-sm text-background shadow-lg animate-in fade-in slide-in-from-bottom-2"
        >
          <span className="flex-1">{n.text}</span>
          <button type="button" aria-label="Dismiss" onClick={() => dismissNotice(n.id)} className="opacity-70 hover:opacity-100">
            <X className="size-4" />
          </button>
        </div>
      ))}
    </div>
  )
}
