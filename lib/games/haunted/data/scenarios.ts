import type { OmenId } from '../types'

/*
 * Scenario cards: the 3rd-edition chart of which haunt each omen triggers
 * and who becomes the traitor, per scenario. Scenario names are our own.
 */
export type TraitorRule =
  | 'revealer'
  | 'leftOfRevealer'
  | 'hidden'
  | 'none'
  | 'freeForAll'
  | 'oldest'
  | 'mostOmens'
  | { highest: 'speed' | 'might' | 'sanity' | 'knowledge'; excludeRevealer?: boolean }
  | { lowest: 'speed' | 'might' | 'sanity' | 'knowledge'; excludeRevealer?: boolean }

export interface Scenario {
  id: string
  name: string
  blurb: string
  chart: Record<OmenId, { haunt: number; traitor: TraitorRule }>
}

const R = 'revealer' as const

export const SCENARIOS: Scenario[] = [
  {
    id: 'curse',
    name: 'The Curse',
    blurb: 'Something has marked every one of you. The cure, if there is one, is in this house.',
    chart: {
      idol: { haunt: 23, traitor: R },
      armor: { haunt: 50, traitor: R },
      ring: { haunt: 2, traitor: 'hidden' },
      dog: { haunt: 20, traitor: 'oldest' },
      book: { haunt: 39, traitor: { highest: 'knowledge', excludeRevealer: true } },
      dagger: { haunt: 17, traitor: R },
      holySymbol: { haunt: 19, traitor: R },
      skull: { haunt: 46, traitor: R },
      mask: { haunt: 27, traitor: R },
    },
  },
  {
    id: 'ghostHunters',
    name: 'Ghost Hunters',
    blurb: 'A scrappy crew of investigators, here because the readings went off the scale.',
    chart: {
      idol: { haunt: 28, traitor: R },
      armor: { haunt: 47, traitor: R },
      ring: { haunt: 18, traitor: R },
      dog: { haunt: 42, traitor: R },
      book: { haunt: 16, traitor: R },
      dagger: { haunt: 15, traitor: R },
      holySymbol: { haunt: 31, traitor: R },
      skull: { haunt: 32, traitor: R },
      mask: { haunt: 5, traitor: 'none' },
    },
  },
  {
    id: 'openHouse',
    name: 'Open House',
    blurb: 'A fixer-upper at a suspicious price. Some of you want to buy it; some came for the snacks.',
    chart: {
      idol: { haunt: 41, traitor: R },
      armor: { haunt: 10, traitor: 'freeForAll' },
      ring: { haunt: 29, traitor: R },
      dog: { haunt: 4, traitor: 'none' },
      book: { haunt: 14, traitor: 'leftOfRevealer' },
      dagger: { haunt: 49, traitor: R },
      holySymbol: { haunt: 36, traitor: { lowest: 'sanity' } },
      skull: { haunt: 22, traitor: 'leftOfRevealer' },
      mask: { haunt: 40, traitor: R },
    },
  },
  {
    id: 'invitation',
    name: 'The Invitation',
    blurb: 'Each of you received a letter with no return address. You all came anyway.',
    chart: {
      idol: { haunt: 9, traitor: 'freeForAll' },
      armor: { haunt: 37, traitor: R },
      ring: { haunt: 38, traitor: R },
      dog: { haunt: 8, traitor: 'none' },
      book: { haunt: 45, traitor: R },
      dagger: { haunt: 6, traitor: 'hidden' },
      holySymbol: { haunt: 26, traitor: R },
      skull: { haunt: 48, traitor: { highest: 'might' } },
      mask: { haunt: 24, traitor: { highest: 'speed' } },
    },
  },
  {
    id: 'missingFriend',
    name: 'The Missing Friend',
    blurb: 'A friend vanished last week. Their phone last pinged from this hill.',
    chart: {
      idol: { haunt: 34, traitor: { highest: 'knowledge' } },
      armor: { haunt: 25, traitor: 'leftOfRevealer' },
      ring: { haunt: 30, traitor: { lowest: 'sanity', excludeRevealer: true } },
      dog: { haunt: 43, traitor: 'mostOmens' },
      book: { haunt: 21, traitor: R },
      dagger: { haunt: 11, traitor: 'freeForAll' },
      holySymbol: { haunt: 13, traitor: R },
      skull: { haunt: 35, traitor: R },
      mask: { haunt: 44, traitor: 'leftOfRevealer' },
    },
  },
]

export const SCENARIO_BY_ID = new Map(SCENARIOS.map((s) => [s.id, s]))
