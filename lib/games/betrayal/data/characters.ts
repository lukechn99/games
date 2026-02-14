import type { CharacterDef } from '../types'

/**
 * All 12 explorers from Betrayal at House on the Hill (3rd Edition).
 * Paired by card colour; each pair shares a physical character card.
 *
 * Trait scales: 8 values (indices 0–7), startIndex marks the initial clip.
 * Index 0 represents the "skull" / death threshold for most traits.
 */
export const CHARACTERS: CharacterDef[] = [
  // ── Green pair ────────────────────────────────────────────────────
  {
    id: 'sammy',
    name: 'Sammy Angler',
    age: 9,
    color: 0x4caf50,
    colorName: 'Green',
    description: 'A bright kid obsessed with stage magic since a magician came to his 6th birthday. Looking for mystical stage dressing in the old house.',
    traits: {
      speed:     { values: [3, 4, 4, 4, 5, 6, 7, 8], startIndex: 3 },
      might:     { values: [2, 3, 3, 4, 5, 6, 6, 7], startIndex: 3 },
      sanity:    { values: [3, 3, 3, 4, 5, 6, 7, 8], startIndex: 3 },
      knowledge: { values: [1, 3, 3, 5, 5, 6, 6, 7], startIndex: 3 },
    },
  },
  {
    id: 'jaden',
    name: 'Jaden Jones',
    age: 11,
    color: 0x66bb6a,
    colorName: 'Green',
    description: 'An amateur detective armed with a magnifying glass and evidence case. He\'s documenting everything in the house for posterity.',
    traits: {
      speed:     { values: [3, 3, 3, 4, 6, 6, 7, 7], startIndex: 3 },
      might:     { values: [2, 3, 3, 4, 5, 5, 6, 8], startIndex: 3 },
      sanity:    { values: [3, 4, 4, 4, 5, 6, 6, 7], startIndex: 3 },
      knowledge: { values: [3, 4, 4, 5, 6, 7, 7, 8], startIndex: 4 },
    },
  },
  // ── Red / Orange pair ─────────────────────────────────────────────
  {
    id: 'oliver',
    name: 'Oliver Swift',
    age: 33,
    color: 0xf44336,
    colorName: 'Red',
    description: 'Fast but believes you should never run unless running from something. A philosophy-studying loner who finds people insufferable.',
    traits: {
      speed:     { values: [4, 4, 4, 5, 6, 7, 7, 8], startIndex: 5 },
      might:     { values: [2, 3, 3, 4, 5, 6, 6, 7], startIndex: 3 },
      sanity:    { values: [1, 2, 3, 4, 5, 5, 5, 7], startIndex: 3 },
      knowledge: { values: [2, 3, 3, 4, 5, 5, 5, 7], startIndex: 3 },
    },
  },
  {
    id: 'josef',
    name: 'Josef "Brosef" Hooper',
    age: 25,
    color: 0xff5722,
    colorName: 'Orange',
    description: 'Taken for a meathead college athlete, but has a softer side when it comes to sticking up for people he cares about.',
    traits: {
      speed:     { values: [2, 2, 2, 3, 4, 5, 5, 6], startIndex: 5 },
      might:     { values: [4, 5, 5, 6, 6, 7, 8, 8], startIndex: 3 },
      sanity:    { values: [2, 2, 3, 4, 5, 5, 6, 7], startIndex: 3 },
      knowledge: { values: [2, 2, 3, 3, 5, 5, 6, 6], startIndex: 3 },
    },
  },
  // ── Yellow pair ───────────────────────────────────────────────────
  {
    id: 'isa',
    name: 'Isa Valencia',
    age: 11,
    color: 0xffeb3b,
    colorName: 'Yellow',
    description: 'A strange kid with an interest in the paranormal, she watches reruns of Bros vs. Ghosts on late night TV and blogs about it.',
    traits: {
      speed:     { values: [4, 4, 4, 4, 5, 6, 8, 8], startIndex: 4 },
      might:     { values: [2, 2, 3, 3, 4, 4, 6, 7], startIndex: 3 },
      sanity:    { values: [3, 4, 5, 5, 6, 6, 7, 8], startIndex: 5 },
      knowledge: { values: [1, 2, 3, 4, 4, 5, 5, 5], startIndex: 3 },
    },
  },
  {
    id: 'anita',
    name: 'Anita Hernandez',
    age: 12,
    color: 0xffc107,
    colorName: 'Yellow',
    description: 'Raised by superstitious parents, she works in their tea shop learning about magical qualities of herbs. Something about the old house gives her the creeps.',
    traits: {
      speed:     { values: [3, 4, 5, 6, 6, 6, 7, 7], startIndex: 3 },
      might:     { values: [2, 3, 3, 3, 4, 5, 6, 7], startIndex: 4 },
      sanity:    { values: [1, 2, 3, 4, 5, 5, 6, 7], startIndex: 3 },
      knowledge: { values: [2, 3, 4, 4, 5, 6, 6, 6], startIndex: 4 },
    },
  },
  // ── White pair ────────────────────────────────────────────────────
  {
    id: 'warren',
    name: 'Father Warren Leung',
    age: 71,
    color: 0xeeeeee,
    colorName: 'White',
    description: 'A no-nonsense priest with a backbone of steel. Has extensive knowledge of ancient religions and a history of banishing demons.',
    traits: {
      speed:     { values: [2, 3, 3, 4, 5, 6, 7, 7], startIndex: 3 },
      might:     { values: [1, 2, 2, 4, 4, 5, 5, 7], startIndex: 3 },
      sanity:    { values: [3, 4, 5, 5, 6, 7, 7, 8], startIndex: 5 },
      knowledge: { values: [1, 3, 3, 4, 5, 6, 6, 8], startIndex: 4 },
    },
  },
  {
    id: 'dan',
    name: 'Dan Nguyen, M.D.',
    age: 60,
    color: 0xbdbdbd,
    colorName: 'White',
    description: 'A town doctor for decades who has seen more and more injuries from that creepy old house. He\'s come to get to the bottom of it.',
    traits: {
      speed:     { values: [2, 2, 4, 4, 5, 5, 6, 6], startIndex: 3 },
      might:     { values: [1, 2, 3, 4, 5, 5, 6, 6], startIndex: 3 },
      sanity:    { values: [1, 3, 3, 4, 5, 5, 6, 7], startIndex: 3 },
      knowledge: { values: [4, 5, 5, 5, 5, 6, 7, 8], startIndex: 5 },
    },
  },
  // ── Purple pair ───────────────────────────────────────────────────
  {
    id: 'michelle',
    name: 'Michelle Monroe',
    age: 19,
    color: 0x9c27b0,
    colorName: 'Purple',
    description: 'A lacrosse champion who\'s faced worse than whatever this house throws at her. Used to being the underdog and bringing her team to victory.',
    traits: {
      speed:     { values: [3, 3, 4, 5, 6, 6, 7, 8], startIndex: 3 },
      might:     { values: [3, 3, 3, 4, 5, 6, 7, 8], startIndex: 3 },
      sanity:    { values: [3, 3, 3, 4, 5, 6, 6, 6], startIndex: 3 },
      knowledge: { values: [2, 3, 3, 4, 5, 6, 7, 8], startIndex: 5 },
    },
  },
  {
    id: 'brittani',
    name: 'Brittani "Beat Box" Bowen',
    age: 22,
    color: 0xba68c8,
    colorName: 'Purple',
    description: 'A DJ who\'s been throwing house parties since high school. Seeking new and exciting locations to play music — what could be more interesting than an abandoned old house?',
    traits: {
      speed:     { values: [2, 3, 4, 4, 4, 5, 6, 8], startIndex: 4 },
      might:     { values: [3, 4, 4, 4, 4, 5, 6, 8], startIndex: 3 },
      sanity:    { values: [1, 1, 2, 4, 4, 4, 5, 6], startIndex: 5 },
      knowledge: { values: [2, 3, 3, 4, 4, 5, 6, 8], startIndex: 3 },
    },
  },
  // ── Blue pair ─────────────────────────────────────────────────────
  {
    id: 'stephanie',
    name: 'Stephanie Richter',
    age: 40,
    color: 0x2196f3,
    colorName: 'Blue',
    description: 'An amateur filmmaker who uploads short documentaries online. A film about the haunted house would do wonders for her online presence.',
    traits: {
      speed:     { values: [3, 4, 4, 4, 4, 6, 7, 8], startIndex: 4 },
      might:     { values: [2, 2, 2, 4, 4, 5, 6, 6], startIndex: 3 },
      sanity:    { values: [4, 4, 4, 5, 6, 7, 8, 8], startIndex: 3 },
      knowledge: { values: [4, 5, 5, 5, 5, 6, 6, 7], startIndex: 4 },
    },
  },
  {
    id: 'persephone',
    name: 'Persephone Puleri',
    age: 49,
    color: 0x1565c0,
    colorName: 'Blue',
    description: 'Runs Blessed Botanicals, a shop specializing in crystals, herbs, and paranormal supplies. The haunted house rumors have been great for business.',
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
