import type { CardDef, EventDef, OmenId } from '../types'

/*
 * Items: the 22 base-game 3rd-edition items. Effects are the real ones,
 * rewritten in our own words; flavor text is original.
 */
export const ITEMS: CardDef[] = [
  { id: 'feather', kind: 'item', name: 'Dove Feather', flavor: 'Weightless, and warm as a held breath.', effect: { kind: 'feather' },
    rules: 'When you must make a trait roll, you may bury this instead and choose any result from 0 to 8.' },
  { id: 'brooch', kind: 'item', name: 'Cameo Brooch', flavor: 'Cold enough to sting, oddly reassuring.', effect: { kind: 'brooch' },
    rules: 'Whenever you take Physical or Mental damage, you may take it as General damage instead.' },
  { id: 'chainsaw', kind: 'item', name: 'Chainsaw', flavor: 'Starts on the first pull. That is the scary part.', effect: { kind: 'weapon', trait: 'might', extraDice: 1 },
    rules: 'Weapon. When you attack with it, roll 1 extra die.' },
  { id: 'doll', kind: 'item', name: 'Porcelain Doll', flavor: 'Its glass eyes follow you, disapprovingly.', effect: { kind: 'doll' },
    rules: 'Once per turn, reroll all dice on a trait roll you just made. Then lose 1 Sanity.' },
  { id: 'crossbow', kind: 'item', name: 'Crossbow', flavor: 'Old wood, new string.', effect: { kind: 'weapon', trait: 'speed', extraDice: 1, range: 'adjacent', noDamageIfLose: true },
    rules: 'Weapon. Attack anyone on your tile or an adjacent one. Both sides roll Speed; you roll 1 extra die. If you lose, you take no damage.' },
  { id: 'dynamite', kind: 'item', name: 'Dynamite', flavor: 'Sweating slightly. Probably fine.', effect: { kind: 'dynamite' },
    rules: 'Instead of attacking, bury it and pick your tile or an adjacent one. Everyone there makes a Speed roll. 4+: nothing. 0-3: 4 Physical damage.' },
  { id: 'firstAid', kind: 'item', name: 'First Aid Kit', flavor: 'Bandages, tape and a little hope.', effect: { kind: 'firstAid' },
    rules: 'On your turn, bury it to heal all of your critical traits, or those of another explorer on your tile.' },
  { id: 'flashlight', kind: 'item', name: 'Flashlight', flavor: 'Two batteries, one flicker.', effect: { kind: 'flashlight' },
    rules: 'During events, roll 2 extra dice on trait rolls.' },
  { id: 'gun', kind: 'item', name: 'Revolver', flavor: 'Six chambers, all full.', effect: { kind: 'weapon', trait: 'speed', extraDice: 0, range: 'sight', noDamageIfLose: true },
    rules: 'Weapon. Attack any target in line of sight. Both sides roll Speed. If you lose, you take no damage.' },
  { id: 'headphones', kind: 'item', name: 'Headphones', flavor: 'Plugged into nothing, playing something soothing.', effect: { kind: 'headphones' },
    rules: 'Whenever you take Mental damage, reduce it by 1.' },
  { id: 'jacket', kind: 'item', name: 'Leather Jacket', flavor: 'Heavy, and from no animal you can name.', effect: { kind: 'jacket' },
    rules: 'Roll 1 extra die when you defend against an attack.' },
  { id: 'coin', kind: 'item', name: 'Two-Faced Coin', flavor: 'Never lands the same way twice.', effect: { kind: 'coin' },
    rules: 'Once per turn, reroll every blank die on a trait roll you just made. Take 1 Mental damage for each blank on the reroll.' },
  { id: 'machete', kind: 'item', name: 'Machete', flavor: 'Rust on the handle, none on the edge.', effect: { kind: 'weapon', trait: 'might', extraDice: 0, addResult: 1 },
    rules: 'Weapon. When you attack with it, add 1 to your result.' },
  { id: 'camera', kind: 'item', name: 'Spirit Camera', flavor: 'Develops things that were not there.', effect: { kind: 'camera' },
    rules: 'You may use your Sanity in place of Knowledge for Knowledge rolls.' },
  { id: 'map', kind: 'item', name: 'Shifting Map', flavor: 'The corridors rearrange when you look away.', effect: { kind: 'map' },
    rules: 'On your turn, bury it to move your explorer to any tile.' },
  { id: 'mirror', kind: 'item', name: 'Hand Mirror', flavor: 'Your reflection looks calmer than you feel.', effect: { kind: 'mirror' },
    rules: 'On your turn, bury it to heal your Knowledge and Sanity.' },
  { id: 'stopwatch', kind: 'item', name: 'Backward Watch', flavor: 'Wind it and the hands run home.', effect: { kind: 'stopwatch' },
    rules: 'After the haunt has started: on your turn, bury it to take another turn after this one.' },
  { id: 'necklace', kind: 'item', name: 'Tooth Necklace', flavor: 'Few of the teeth are human.', effect: { kind: 'necklace' },
    rules: 'At the end of your turn, you may gain 1 in a critical trait.' },
  { id: 'rabbitFoot', kind: 'item', name: "Rabbit's Foot", flavor: 'Lucky for you. Not for the rabbit.', effect: { kind: 'rabbitFoot' },
    rules: 'Once per turn, reroll one die you just rolled.' },
  { id: 'skeletonKey', kind: 'item', name: 'Bone Key', flavor: 'Fits every lock, and some walls.', effect: { kind: 'skeletonKey' },
    rules: 'You may move through walls into placed tiles. Each time, roll a die: on a blank, bury the key. It cannot be used to discover rooms.' },
  { id: 'amulet', kind: 'item', name: 'Clear-Mind Amulet', flavor: 'Wearing it, your thoughts go quiet and sharp.', effect: { kind: 'amulet' },
    rules: 'Whenever you take Physical damage, gain 1 Sanity.' },
  { id: 'medicine', kind: 'item', name: 'Odd Tonic', flavor: 'Side effects include everything.', effect: { kind: 'medicine' },
    rules: 'On your turn, bury it to heal your Might and Speed.' },
]

/*
 * Omens: the 9 3rd-edition omens (these names drive the haunt chart).
 * Their exact card effects couldn't be sourced, so the effects below are
 * approximations in the spirit of earlier editions.
 */
export const OMENS: CardDef[] = [
  { id: 'omenArmor', kind: 'omen', omen: 'armor', name: 'Armor', flavor: 'Dented plate that still turns a blade.', effect: { kind: 'armor' }, approx: true,
    rules: 'Damage you take from attacks is reduced by 1.' },
  { id: 'omenBook', kind: 'omen', omen: 'book', name: 'Book', flavor: 'The handwriting changes every page.', onDraw: { knowledge: 2 }, approx: true,
    rules: 'Gain 2 Knowledge when you take this card.' },
  { id: 'omenDagger', kind: 'omen', omen: 'dagger', name: 'Dagger', flavor: 'It is thirsty, and it knows your name.',
    effect: { kind: 'weapon', trait: 'might', extraDice: 2, speedCost: 1 }, approx: true,
    rules: 'Weapon. Roll 2 extra dice when you attack with it, then lose 1 Speed.' },
  { id: 'omenDog', kind: 'omen', omen: 'dog', name: 'Dog', flavor: 'Scruffy, silent, and watching the doors.', onDraw: { might: 1, sanity: 1 }, approx: true,
    rules: 'Gain 1 Might and 1 Sanity when you take this card.' },
  { id: 'omenHolySymbol', kind: 'omen', omen: 'holySymbol', name: 'Holy Symbol', flavor: 'Faintly bright in the dark.', onDraw: { sanity: 2 }, approx: true,
    rules: 'Gain 2 Sanity when you take this card.' },
  { id: 'omenIdol', kind: 'omen', omen: 'idol', name: 'Idol', flavor: 'Worn stone. You cannot tell what it depicts.', effect: { kind: 'idol' }, approx: true,
    rules: 'Once per turn, roll 2 extra dice on a trait roll. If you do, take 1 Mental damage.' },
  { id: 'omenMask', kind: 'omen', omen: 'mask', name: 'Mask', flavor: 'Smooth, and slightly warm.', onDraw: { knowledge: 1, sanity: 1 }, approx: true,
    rules: 'Gain 1 Knowledge and 1 Sanity when you take this card.' },
  { id: 'omenRing', kind: 'omen', omen: 'ring', name: 'Ring', flavor: 'A band that twists back on itself.', onDraw: { knowledge: 1, sanity: 1 }, approx: true,
    rules: 'Gain 1 Knowledge and 1 Sanity when you take this card.' },
  { id: 'omenSkull', kind: 'omen', omen: 'skull', name: 'Skull', flavor: 'Etched with marks too fine to read.', onDraw: { knowledge: 1, might: 1 }, approx: true,
    rules: 'Gain 1 Knowledge and 1 Might when you take this card.' },
]

/*
 * Events. The 3rd-edition event cards couldn't be sourced, so these are
 * original events in the same format (a trait roll with a results table).
 * Swap in the real ones by editing this list.
 */
const E = (id: string, name: string, flavor: string, roll: EventDef['roll'], outcomes: EventDef['outcomes']): EventDef => ({
  id, name, flavor, roll, outcomes, approx: true,
})

export const EVENTS: EventDef[] = [
  E('evWhispers', 'Whispers in the Wall', 'Voices argue just behind the plaster. One of them says your name.', 'sanity', [
    { min: 4, text: 'You tune them out. Gain 1 Sanity.', outcome: { kind: 'gain', trait: 'sanity', amount: 1 } },
    { min: 0, text: 'They will not stop. Take 1 Mental damage.', outcome: { kind: 'damage', type: 'mental', amount: 1 } },
  ]),
  E('evFallingPlaster', 'Falling Plaster', 'The ceiling sighs and lets go.', 'speed', [
    { min: 4, text: 'You dodge clear.', outcome: { kind: 'nothing' } },
    { min: 0, text: 'It catches you. Take 1 die of Physical damage.', outcome: { kind: 'damage', type: 'physical', amount: 1, dice: true } },
  ]),
  E('evOldDiary', 'An Old Diary', 'Pressed flowers and a child\'s careful handwriting.', 'knowledge', [
    { min: 5, text: 'You piece together the house\'s history. Gain 1 Knowledge and 1 Sanity.', outcome: { kind: 'multi', outcomes: [{ kind: 'gain', trait: 'knowledge', amount: 1 }, { kind: 'gain', trait: 'sanity', amount: 1 }] } },
    { min: 2, text: 'Interesting, if unsettling. Gain 1 Knowledge.', outcome: { kind: 'gain', trait: 'knowledge', amount: 1 } },
    { min: 0, text: 'The last page is about you. Take 1 Mental damage.', outcome: { kind: 'damage', type: 'mental', amount: 1 } },
  ]),
  E('evStuckDoor', 'The Stuck Door', 'Something leans on the other side.', 'might', [
    { min: 4, text: 'You shove it open. Gain 1 Might.', outcome: { kind: 'gain', trait: 'might', amount: 1 } },
    { min: 0, text: 'It shoves back. Take 1 Physical damage.', outcome: { kind: 'damage', type: 'physical', amount: 1 } },
  ]),
  E('evPortrait', 'The Watching Portrait', 'The eyes in the painting are wet.', 'sanity', [
    { min: 5, text: 'You stare back until it looks away. Gain 1 Sanity.', outcome: { kind: 'gain', trait: 'sanity', amount: 1 } },
    { min: 0, text: 'You can\'t shake the feeling. Lose 1 Sanity.', outcome: { kind: 'lose', trait: 'sanity', amount: 1 } },
  ]),
  E('evDraft', 'Cold Draft', 'Every candle in the room bends toward you.', null, [
    { min: 0, text: 'A chill settles in your bones. Take 1 Physical damage.', outcome: { kind: 'damage', type: 'physical', amount: 1 } },
  ]),
  E('evMusicBox', 'A Music Box Plays', 'Somewhere nearby, a tune you knew as a child.', 'knowledge', [
    { min: 4, text: 'You recognize the song, and it steadies you. Gain 1 Sanity.', outcome: { kind: 'gain', trait: 'sanity', amount: 1 } },
    { min: 0, text: 'You can\'t place it, and it won\'t stop. Take 1 Mental damage.', outcome: { kind: 'damage', type: 'mental', amount: 1 } },
  ]),
  E('evRats', 'Rats', 'A river of them, flowing around your ankles.', 'speed', [
    { min: 3, text: 'You hop clear.', outcome: { kind: 'nothing' } },
    { min: 0, text: 'They bite on the way past. Take 1 Physical damage.', outcome: { kind: 'damage', type: 'physical', amount: 1 } },
  ]),
  E('evTrapdoor', 'Trapdoor', 'The floorboard gives way under your heel.', 'speed', [
    { min: 5, text: 'You catch the edge and haul yourself up.', outcome: { kind: 'nothing' } },
    { min: 0, text: 'You drop into the dark. Go to the Basement Landing and take 1 die of Physical damage.', outcome: { kind: 'multi', outcomes: [{ kind: 'teleport', to: 'basementLanding' }, { kind: 'damage', type: 'physical', amount: 1, dice: true }] } },
  ]),
  E('evHiddenDrawer', 'Hidden Drawer', 'A click, and a panel slides open.', 'knowledge', [
    { min: 4, text: 'Something useful inside. Draw an Item.', outcome: { kind: 'drawItem' } },
    { min: 0, text: 'Empty, except for a lock of hair.', outcome: { kind: 'nothing' } },
  ]),
  E('evReflection', 'Wrong Reflection', 'Your reflection is a half-second late.', 'sanity', [
    { min: 4, text: 'You blink, and it catches up.', outcome: { kind: 'nothing' } },
    { min: 0, text: 'It smiles first. Take 2 Mental damage.', outcome: { kind: 'damage', type: 'mental', amount: 2 } },
  ]),
  E('evHeavyChest', 'Heavy Chest', 'Iron bands and a lid that hasn\'t moved in years.', 'might', [
    { min: 5, text: 'It opens. Draw an Item.', outcome: { kind: 'drawItem' } },
    { min: 0, text: 'You strain something. Lose 1 Speed.', outcome: { kind: 'lose', trait: 'speed', amount: 1 } },
  ]),
  E('evLaughter', 'Childish Laughter', 'Running feet overhead, though you\'re on the top floor.', 'sanity', [
    { min: 3, text: 'You laugh along, nervously. Nothing happens.', outcome: { kind: 'nothing' } },
    { min: 0, text: 'Take 1 die of Mental damage.', outcome: { kind: 'damage', type: 'mental', amount: 1, dice: true } },
  ]),
  E('evSmoke', 'Smoke Without Fire', 'Grey fog pours from under the floor.', 'speed', [
    { min: 4, text: 'You find your way through. Gain 1 Speed.', outcome: { kind: 'gain', trait: 'speed', amount: 1 } },
    { min: 0, text: 'You stumble and cough. Take 1 Physical damage.', outcome: { kind: 'damage', type: 'physical', amount: 1 } },
  ]),
  E('evGuestbook', 'The Guestbook', 'Every visitor signed it. The last signature is yours, dated tomorrow.', 'knowledge', [
    { min: 5, text: 'You study the names and learn something. Gain 2 Knowledge.', outcome: { kind: 'gain', trait: 'knowledge', amount: 2 } },
    { min: 0, text: 'Lose 1 Sanity.', outcome: { kind: 'lose', trait: 'sanity', amount: 1 } },
  ]),
  E('evBanging', 'Banging Pipes', 'Something is knocking to get out.', 'might', [
    { min: 4, text: 'You wrench the valve shut. Gain 1 Might.', outcome: { kind: 'gain', trait: 'might', amount: 1 } },
    { min: 0, text: 'Scalding steam. Take 1 die of Physical damage.', outcome: { kind: 'damage', type: 'physical', amount: 1, dice: true } },
  ]),
  E('evKindlyGhost', 'A Kindly Spirit', 'An old woman in grey pats your hand and is gone.', null, [
    { min: 0, text: 'You feel looked after. Heal your Sanity.', outcome: { kind: 'heal', traits: ['sanity'] } },
  ]),
  E('evCreakingStairs', 'Creaking Footsteps', 'Someone is following, matching your pace exactly.', 'sanity', [
    { min: 4, text: 'You turn and face the empty hall. Gain 1 Sanity.', outcome: { kind: 'gain', trait: 'sanity', amount: 1 } },
    { min: 0, text: 'You run. Take 1 Mental damage.', outcome: { kind: 'damage', type: 'mental', amount: 1 } },
  ]),
  E('evSpiders', 'Webs', 'Sticky threads, and something large has noticed.', 'might', [
    { min: 3, text: 'You tear free.', outcome: { kind: 'nothing' } },
    { min: 0, text: 'You thrash your way out. Take 2 Physical damage.', outcome: { kind: 'damage', type: 'physical', amount: 2 } },
  ]),
  E('evStrangeTea', 'Tea for One', 'A cup, still steaming, set out for you.', 'knowledge', [
    { min: 4, text: 'You recognize the herbs. It\'s restorative. Heal your Might and Speed.', outcome: { kind: 'heal', traits: ['might', 'speed'] } },
    { min: 0, text: 'You drink it anyway. Take 1 die of General damage.', outcome: { kind: 'damage', type: 'general', amount: 1, dice: true } },
  ]),
  E('evLightsOut', 'Lights Out', 'Every bulb in the house pops at once.', 'sanity', [
    { min: 4, text: 'You wait for your eyes to adjust.', outcome: { kind: 'nothing' } },
    { min: 0, text: 'Something brushes past you. Take 1 Mental damage.', outcome: { kind: 'damage', type: 'mental', amount: 1 } },
  ]),
  E('evSecretPassage', 'Secret Passage', 'A bookcase swings outward onto a narrow stair.', 'knowledge', [
    { min: 4, text: 'You follow it up to the Upper Landing.', outcome: { kind: 'teleport', to: 'upperLanding' } },
    { min: 0, text: 'It leads in a circle back to the Entrance Hall.', outcome: { kind: 'teleport', to: 'entrance' } },
  ]),
  E('evAdrenaline', 'Second Wind', 'Your heart pounds, and the fear turns to fuel.', null, [
    { min: 0, text: 'Gain 1 in a Physical trait.', outcome: { kind: 'gain', trait: 'physical', amount: 1 } },
  ]),
  E('evOldPhotos', 'Old Photographs', 'Generations of a family, each with the same face in the background.', 'knowledge', [
    { min: 4, text: 'You spot the pattern. Gain 1 in a Mental trait.', outcome: { kind: 'gain', trait: 'mental', amount: 1 } },
    { min: 0, text: 'The face is in your phone\'s photos too. Take 2 Mental damage.', outcome: { kind: 'damage', type: 'mental', amount: 2 } },
  ]),
]

export const ALL_CARDS: CardDef[] = [...ITEMS, ...OMENS]
export const CARD_BY_ID = new Map<string, CardDef>(ALL_CARDS.map((c) => [c.id, c]))
export const EVENT_BY_ID = new Map(EVENTS.map((e) => [e.id, e]))

export function isWeapon(cardId: string): boolean {
  return CARD_BY_ID.get(cardId)?.effect?.kind === 'weapon'
}

export function omenOf(cardId: string): OmenId | undefined {
  return CARD_BY_ID.get(cardId)?.omen
}
