import type { ExplorerDef } from '../types'

/**
 * Explorers. Trait tracks are the 3rd-edition values (lowest first; the
 * first value is critical, below it is death). Names, colors-by-pair and
 * blurbs are original. Each color pair shares one board, so only one
 * explorer of each color can be in a game.
 */
export const EXPLORERS: ExplorerDef[] = [
  { id: 'vera', name: "Vera Lindqvist", color: '#3B82F6', colorName: 'Blue', age: 40, blurb: "A documentary maker who thinks this house could finally be her big break.",
    traits: { speed: { values: [2, 3, 3, 5, 5, 6, 6, 7], start: 2 }, might: { values: [2, 3, 3, 4, 5, 5, 6, 6], start: 3 }, sanity: { values: [4, 4, 5, 5, 6, 7, 8, 8], start: 3 }, knowledge: { values: [2, 3, 4, 4, 4, 5, 6, 6], start: 2 } } },
  { id: 'odessa', name: "Odessa Marlowe", color: '#3B82F6', colorName: 'Blue', age: 49, blurb: "Runs a shop of herbs and curios, and has heard every rumor about the hill.",
    traits: { speed: { values: [3, 3, 4, 4, 5, 6, 7, 8], start: 3 }, might: { values: [3, 3, 4, 5, 6, 6, 7, 7], start: 2 }, sanity: { values: [3, 3, 4, 5, 6, 7, 8, 8], start: 3 }, knowledge: { values: [2, 3, 3, 4, 5, 6, 6, 7], start: 2 } } },
  { id: 'milo', name: "Milo Park", color: '#22C55E', colorName: 'Green', age: 11, blurb: "A kid detective with a notebook full of clues that never quite add up.",
    traits: { speed: { values: [3, 4, 4, 4, 5, 6, 7, 8], start: 2 }, might: { values: [2, 3, 3, 3, 4, 5, 6, 7], start: 3 }, sanity: { values: [3, 3, 4, 5, 5, 6, 7, 8], start: 2 }, knowledge: { values: [3, 3, 4, 5, 5, 6, 6, 7], start: 3 } } },
  { id: 'theo', name: "Theo Brandt", color: '#22C55E', colorName: 'Green', age: 9, blurb: "A pint-sized stage magician hunting for a prop with real mystery.",
    traits: { speed: { values: [2, 3, 4, 4, 5, 6, 7, 8], start: 4 }, might: { values: [3, 3, 4, 4, 5, 5, 6, 8], start: 2 }, sanity: { values: [2, 3, 4, 4, 5, 6, 6, 7], start: 3 }, knowledge: { values: [2, 3, 3, 4, 5, 6, 7, 8], start: 2 } } },
  { id: 'rosa', name: "Rosa Quinn", color: '#A855F7', colorName: 'Purple', age: 19, blurb: "Team captain. Doesn't believe in ghosts, and certainly doesn't fear them.",
    traits: { speed: { values: [3, 3, 4, 5, 6, 6, 7, 8], start: 2 }, might: { values: [2, 3, 4, 4, 5, 6, 7, 8], start: 4 }, sanity: { values: [2, 3, 3, 4, 5, 6, 6, 6], start: 2 }, knowledge: { values: [2, 3, 3, 4, 5, 6, 7, 8], start: 3 } } },
  { id: 'kiki', name: "Kiki Alvarez", color: '#A855F7', colorName: 'Purple', age: 22, blurb: "A DJ scouting the old house as the venue for the party of the year.",
    traits: { speed: { values: [2, 3, 3, 4, 4, 5, 6, 6], start: 2 }, might: { values: [3, 3, 4, 5, 6, 7, 7, 8], start: 3 }, sanity: { values: [3, 3, 4, 4, 5, 6, 6, 7], start: 3 }, knowledge: { values: [3, 3, 4, 5, 5, 6, 6, 7], start: 2 } } },
  { id: 'dex', name: "Dex Mahoney", color: '#EF4444', colorName: 'Red', age: 25, blurb: "Big, loud, loyal. Writes poetry he will never let anyone read.",
    traits: { speed: { values: [2, 2, 3, 4, 5, 6, 7, 8], start: 3 }, might: { values: [4, 4, 4, 5, 6, 7, 8, 8], start: 3 }, sanity: { values: [2, 3, 4, 4, 5, 5, 6, 6], start: 2 }, knowledge: { values: [2, 2, 3, 3, 5, 5, 6, 6], start: 2 } } },
  { id: 'elliot', name: "Elliot Crane", color: '#EF4444', colorName: 'Red', age: 33, blurb: "A runner and philosopher who came for the quiet and found the opposite.",
    traits: { speed: { values: [3, 3, 4, 5, 5, 6, 7, 8], start: 3 }, might: { values: [3, 3, 4, 4, 5, 6, 6, 7], start: 2 }, sanity: { values: [2, 3, 3, 4, 5, 5, 6, 7], start: 2 }, knowledge: { values: [3, 3, 3, 4, 5, 6, 6, 7], start: 3 } } },
  { id: 'harold', name: "Dr. Harold Pike", color: '#E5E7EB', colorName: 'White', age: 60, blurb: "A town doctor tired of patching up people who wandered too near the hill.",
    traits: { speed: { values: [2, 3, 3, 4, 5, 6, 7, 7], start: 2 }, might: { values: [3, 3, 4, 4, 5, 5, 6, 7], start: 2 }, sanity: { values: [2, 3, 4, 4, 5, 6, 7, 8], start: 3 }, knowledge: { values: [3, 3, 4, 5, 5, 6, 7, 8], start: 4 } } },
  { id: 'amos', name: "Father Amos Reed", color: '#E5E7EB', colorName: 'White', age: 71, blurb: "An old priest with steady nerves and a shelf of forbidden reading.",
    traits: { speed: { values: [2, 3, 4, 4, 5, 5, 6, 6], start: 2 }, might: { values: [2, 2, 3, 3, 4, 5, 6, 6], start: 3 }, sanity: { values: [3, 3, 3, 4, 5, 6, 7, 8], start: 4 }, knowledge: { values: [3, 3, 4, 5, 5, 6, 7, 8], start: 2 } } },
  { id: 'wren', name: "Wren Castillo", color: '#EAB308', colorName: 'Yellow', age: 11, blurb: "Reads ghost stories after dark and wants to live inside one.",
    traits: { speed: { values: [4, 4, 5, 5, 6, 7, 8, 8], start: 3 }, might: { values: [2, 3, 3, 3, 4, 5, 6, 7], start: 3 }, sanity: { values: [2, 3, 4, 5, 6, 7, 7, 8], start: 2 }, knowledge: { values: [2, 3, 4, 4, 5, 6, 6, 6], start: 2 } } },
  { id: 'lucia', name: "Lucia Ferro", color: '#EAB308', colorName: 'Yellow', age: 12, blurb: "Knows her herbs, doubts her parents' spirits, and still feels watched.",
    traits: { speed: { values: [2, 3, 4, 4, 5, 6, 7, 8], start: 2 }, might: { values: [2, 2, 3, 4, 4, 5, 6, 7], start: 3 }, sanity: { values: [2, 2, 3, 4, 5, 5, 6, 6], start: 2 }, knowledge: { values: [4, 4, 5, 5, 6, 7, 8, 8], start: 3 } } },
]

export const EXPLORER_BY_ID = new Map(EXPLORERS.map((e) => [e.id, e]))
