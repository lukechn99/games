import type { CharacterDef } from '../types'

/**
 * All 12 explorers from Betrayal at House on the Hill.
 * Paired by card colour; each pair shares a physical character card.
 *
 * Trait scales: 8 values (indices 0–7), startIndex marks the initial clip.
 * Index 0 represents the "skull" / death threshold for most traits.
 */
export const CHARACTERS: CharacterDef[] = [
  // ── Green pair ────────────────────────────────────────────────────
  {
    id: 'brandon',
    name: 'Brandon Jaspers',
    age: 12,
    color: 0x4caf50,
    colorName: 'Green',
    description: 'A quiet kid who\'s always reading about the occult.',
    traits: {
      speed:     { values: [3, 4, 4, 4, 5, 6, 7, 8], startIndex: 3 },
      might:     { values: [2, 3, 3, 4, 5, 6, 6, 7], startIndex: 3 },
      sanity:    { values: [3, 3, 3, 4, 5, 6, 7, 8], startIndex: 3 },
      knowledge: { values: [1, 3, 3, 5, 5, 6, 6, 7], startIndex: 3 },
    },
  },
  {
    id: 'peter',
    name: 'Peter Akimoto',
    age: 13,
    color: 0x4caf50,
    colorName: 'Green',
    description: 'A jock with a brave face and a terrified heart.',
    traits: {
      speed:     { values: [3, 3, 3, 4, 6, 6, 7, 7], startIndex: 3 },
      might:     { values: [2, 3, 3, 4, 5, 5, 6, 8], startIndex: 3 },
      sanity:    { values: [3, 4, 4, 4, 5, 6, 6, 7], startIndex: 3 },
      knowledge: { values: [3, 4, 4, 5, 6, 7, 7, 8], startIndex: 3 },
    },
  },
  // ── Red / Orange pair ─────────────────────────────────────────────
  {
    id: 'flash',
    name: 'Darrin "Flash" Williams',
    age: 20,
    color: 0xf44336,
    colorName: 'Red',
    description: 'A former track star who still runs from his problems.',
    traits: {
      speed:     { values: [4, 4, 4, 5, 6, 7, 7, 8], startIndex: 5 },
      might:     { values: [2, 3, 3, 4, 5, 6, 6, 7], startIndex: 3 },
      sanity:    { values: [1, 2, 3, 4, 5, 5, 5, 7], startIndex: 3 },
      knowledge: { values: [2, 3, 3, 4, 5, 5, 5, 7], startIndex: 3 },
    },
  },
  {
    id: 'ox',
    name: 'Ox Bellows',
    age: 23,
    color: 0xff5722,
    colorName: 'Orange',
    description: 'A big guy who\'s stronger than he looks—and he looks strong.',
    traits: {
      speed:     { values: [2, 2, 2, 3, 4, 5, 5, 6], startIndex: 5 },
      might:     { values: [4, 5, 5, 6, 6, 7, 8, 8], startIndex: 3 },
      sanity:    { values: [2, 2, 3, 4, 5, 5, 6, 7], startIndex: 3 },
      knowledge: { values: [2, 2, 3, 3, 5, 5, 6, 6], startIndex: 3 },
    },
  },
  // ── Yellow pair ───────────────────────────────────────────────────
  {
    id: 'zoe',
    name: 'Zoe Ingstrom',
    age: 8,
    color: 0xffeb3b,
    colorName: 'Yellow',
    description: 'A little girl with a big imagination and an even bigger scream.',
    traits: {
      speed:     { values: [4, 4, 4, 4, 5, 6, 8, 8], startIndex: 4 },
      might:     { values: [2, 2, 3, 3, 4, 4, 6, 7], startIndex: 3 },
      sanity:    { values: [3, 4, 5, 5, 6, 6, 7, 8], startIndex: 5 },
      knowledge: { values: [1, 2, 3, 4, 4, 5, 5, 5], startIndex: 3 },
    },
  },
  {
    id: 'missy',
    name: 'Missy Dubourde',
    age: 9,
    color: 0xffc107,
    colorName: 'Yellow',
    description: 'A dainty girl who can talk her way out of anything.',
    traits: {
      speed:     { values: [3, 4, 5, 6, 6, 6, 7, 7], startIndex: 3 },
      might:     { values: [2, 3, 3, 3, 4, 5, 6, 7], startIndex: 4 },
      sanity:    { values: [1, 2, 3, 4, 5, 5, 6, 7], startIndex: 3 },
      knowledge: { values: [2, 3, 4, 4, 5, 6, 6, 6], startIndex: 4 },
    },
  },
  // ── White pair ────────────────────────────────────────────────────
  {
    id: 'rhinehardt',
    name: 'Father Rhinehardt',
    age: 62,
    color: 0xeeeeee,
    colorName: 'White',
    description: 'A man of God who suspects the devil lurks in every shadow.',
    traits: {
      speed:     { values: [2, 3, 3, 4, 5, 6, 7, 7], startIndex: 3 },
      might:     { values: [1, 2, 2, 4, 4, 5, 5, 7], startIndex: 3 },
      sanity:    { values: [3, 4, 5, 5, 6, 7, 7, 8], startIndex: 5 },
      knowledge: { values: [1, 3, 3, 4, 5, 6, 6, 8], startIndex: 4 },
    },
  },
  {
    id: 'longfellow',
    name: 'Professor Longfellow',
    age: 57,
    color: 0xbdbdbd,
    colorName: 'White',
    description: 'An old professor who knows more than he lets on.',
    traits: {
      speed:     { values: [2, 2, 4, 4, 5, 5, 6, 6], startIndex: 3 },
      might:     { values: [1, 2, 3, 4, 5, 5, 6, 6], startIndex: 3 },
      sanity:    { values: [1, 3, 3, 4, 5, 5, 6, 7], startIndex: 3 },
      knowledge: { values: [4, 5, 5, 5, 5, 6, 7, 8], startIndex: 5 },
    },
  },
  // ── Purple pair ───────────────────────────────────────────────────
  {
    id: 'heather',
    name: 'Heather Granville',
    age: 18,
    color: 0x9c27b0,
    colorName: 'Purple',
    description: 'A prom queen who won\'t back down from a dare.',
    traits: {
      speed:     { values: [3, 3, 4, 5, 6, 6, 7, 8], startIndex: 3 },
      might:     { values: [3, 3, 3, 4, 5, 6, 7, 8], startIndex: 3 },
      sanity:    { values: [3, 3, 3, 4, 5, 6, 6, 6], startIndex: 3 },
      knowledge: { values: [2, 3, 3, 4, 5, 6, 7, 8], startIndex: 5 },
    },
  },
  {
    id: 'jenny',
    name: 'Jenny LeClerc',
    age: 21,
    color: 0xba68c8,
    colorName: 'Purple',
    description: 'A babysitter with a surprisingly sharp survival instinct.',
    traits: {
      speed:     { values: [2, 3, 4, 4, 4, 5, 6, 8], startIndex: 4 },
      might:     { values: [3, 4, 4, 4, 4, 5, 6, 8], startIndex: 3 },
      sanity:    { values: [1, 1, 2, 4, 4, 4, 5, 6], startIndex: 5 },
      knowledge: { values: [2, 3, 3, 4, 4, 5, 6, 8], startIndex: 3 },
    },
  },
  // ── Blue pair ─────────────────────────────────────────────────────
  {
    id: 'vivian',
    name: 'Vivian Lopez',
    age: 42,
    color: 0x2196f3,
    colorName: 'Blue',
    description: 'A horror-movie actress who wishes the screaming would stop.',
    traits: {
      speed:     { values: [3, 4, 4, 4, 4, 6, 7, 8], startIndex: 4 },
      might:     { values: [2, 2, 2, 4, 4, 5, 6, 6], startIndex: 3 },
      sanity:    { values: [4, 4, 4, 5, 6, 7, 8, 8], startIndex: 3 },
      knowledge: { values: [4, 5, 5, 5, 5, 6, 6, 7], startIndex: 4 },
    },
  },
  {
    id: 'zostra',
    name: 'Madame Zostra',
    age: 37,
    color: 0x1565c0,
    colorName: 'Blue',
    description: 'A fortune teller who didn\'t see this coming.',
    traits: {
      speed:     { values: [2, 3, 3, 5, 5, 6, 6, 7], startIndex: 3 },
      might:     { values: [2, 3, 3, 4, 5, 5, 5, 6], startIndex: 4 },
      sanity:    { values: [4, 4, 4, 5, 6, 7, 8, 8], startIndex: 3 },
      knowledge: { values: [1, 3, 4, 4, 4, 5, 6, 6], startIndex: 4 },
    },
  },
]

export const CHARACTER_MAP: Record<string, CharacterDef> = Object.fromEntries(
  CHARACTERS.map((c) => [c.id, c])
)
