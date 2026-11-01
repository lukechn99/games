'use client'

import App from '@/components/app'
import { SessionProvider } from '@/lib/session'

export default function Page() {
  return (
    <SessionProvider>
      <App />
    </SessionProvider>
  )
}
