import { describe, expect, it } from 'vitest'
import { hideSeek } from '@/lib/games/hideseek/rules'
import { getGameModule } from '@/lib/games/modules'
import { GAME_VIEWS } from '@/lib/games/ui'

const ctx = { now: 1000, random: () => 0.5 }

describe('hide and seek (practice)', () => {
  it('is on the game list with a view, and one person can start it', () => {
    expect(getGameModule('hideseek')).toBe(hideSeek)
    expect(GAME_VIEWS.hideseek).toBeDefined()
    expect(hideSeek.minPlayers).toBe(1)
  })
  it('seats everyone; late joiners watch', () => {
    const s = hideSeek.setup(['a', 'b'], ctx)
    expect(hideSeek.view(s, 'a')).toEqual({ phase: 'practice', seated: true })
    expect(hideSeek.view(s, null).seated).toBe(false)
    expect(hideSeek.isOver?.(s)).toBe(false)
  })
})
