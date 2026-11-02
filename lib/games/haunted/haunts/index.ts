import { haunt28 } from './h28'
import { haunt30 } from './h30'
import { haunt44 } from './h44'
import type { HauntDef } from './types'

export const HAUNTS: Record<number, HauntDef> = {
  28: haunt28,
  30: haunt30,
  44: haunt44,
}

export const IMPLEMENTED = Object.keys(HAUNTS).map(Number)

/**
 * Stand-ins when the chart points to a haunt that isn't built yet. Haunt 30
 * needs the Ring in a hero's hands, so it only runs when actually triggered.
 */
export const SUBSTITUTES = [28, 44]
