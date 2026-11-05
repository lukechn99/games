'use client'

import { useEffect, useState } from 'react'
import { onRelayStatus, relayStatus, type RelayStatus } from '@/lib/net/turn'

const TEXT: Record<string, string> = {
  off: 'Relay: not configured',
  checking: 'Relay: checking…',
  ready: 'Relay: ready',
  'bot-check-failed': 'Relay: bot check failed',
  unavailable: 'Relay: unavailable',
  'cap-reached': 'Relay: 30-day cap reached',
  'daily-cap-reached': 'Relay: daily cap reached',
  'usage-unknown': "Relay: Worker can't read usage",
  'turn-error': 'Relay: Cloudflare TURN error',
}

/** Diagnostic badge, shown only when the address has ?relay in it. */
export default function RelayBadge() {
  const [show, setShow] = useState(false)
  const [s, setS] = useState<RelayStatus>('checking')
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setShow(new URLSearchParams(window.location.search).has('relay'))
    setS(relayStatus())
    return onRelayStatus(setS)
  }, [])
  if (!show) return null
  return (
    <p role="status" className={`fixed bottom-2 right-2 z-[70] rounded-full px-3 py-1 text-xs font-medium text-white shadow ${s === 'ready' ? 'bg-ok' : s === 'checking' ? 'bg-slate-500' : 'bg-destructive'}`}>
      {TEXT[s] ?? `Relay: ${s}`}
    </p>
  )
}
