import type { CardDef } from '../types'

// ══════════════════════════════════════════════════════════════════════
//  EVENT CARDS
// ══════════════════════════════════════════════════════════════════════

export const EVENT_CARDS: CardDef[] = [
  {
    id: 'evt_angry_being',
    name: 'Angry Being',
    type: 'event',
    flavour: 'It emerged from the mists, eyes burning.',
    effect: 'Make a Sanity roll (4+ dice). Take 1 Mental damage on failure.',
  },
  {
    id: 'evt_bloody_vision',
    name: 'Bloody Vision',
    type: 'event',
    flavour: 'You see a vision of your own death.',
    effect: 'Make a Sanity roll (5+ dice). Lose 1 Sanity on failure.',
  },
  {
    id: 'evt_burning_man',
    name: 'Burning Man',
    type: 'event',
    flavour: 'A man on fire stumbles toward you, screaming.',
    effect: 'Make a Speed roll (4+ dice). Take 1 Physical damage on failure.',
  },
  {
    id: 'evt_creepy_crawlies',
    name: 'Creepy Crawlies',
    type: 'event',
    flavour: 'Bugs. Everywhere. Under your skin.',
    effect: 'Make a Sanity roll (3+ dice). Lose 1 Sanity on failure.',
  },
  {
    id: 'evt_debris',
    name: 'Debris',
    type: 'event',
    flavour: 'The ceiling groans and chunks fall.',
    effect: 'Make a Speed roll (3+ dice). Take 1 Physical damage on failure.',
  },
  {
    id: 'evt_drip_drip',
    name: 'Drip... Drip...',
    type: 'event',
    flavour: 'The sound is maddening.',
    effect: 'Make a Sanity roll (4+ dice). Lose 1 Sanity on failure, or gain 1 Sanity on success.',
  },
  {
    id: 'evt_footsteps',
    name: 'Footsteps',
    type: 'event',
    flavour: 'You hear footsteps behind you. You turn—nothing.',
    effect: 'Make a Might roll (4+ dice). Take 1 Speed damage on failure.',
  },
  {
    id: 'evt_funeral',
    name: 'Funeral',
    type: 'event',
    flavour: 'You stumble upon a funeral in progress. Yours.',
    effect: 'Make a Sanity roll (4+ dice). Lose 1 Sanity and 1 Might on failure.',
  },
  {
    id: 'evt_grave_dirt',
    name: 'Grave Dirt',
    type: 'event',
    flavour: 'You find a mound of freshly turned earth.',
    effect: 'Make a Knowledge roll (4+ dice). Gain 1 Knowledge on success.',
  },
  {
    id: 'evt_hanged_men',
    name: 'Hanged Men',
    type: 'event',
    flavour: 'Three bodies swing from the rafters.',
    effect: 'Make a Sanity roll (4+ dice). Lose 2 Sanity on failure.',
  },
  {
    id: 'evt_hidden_stairs',
    name: 'Hidden Stairs',
    type: 'event',
    flavour: 'A secret passage opens beneath your feet.',
    effect: 'You may move to any explored room on an adjacent floor.',
  },
  {
    id: 'evt_image_in_mirror',
    name: 'Image in the Mirror',
    type: 'event',
    flavour: 'Your reflection moves independently.',
    effect: 'Make a Sanity roll (4+ dice). Lose 1 Sanity on failure, gain 1 Sanity on success.',
  },
  {
    id: 'evt_jonah',
    name: 'Jonah\'s Turn',
    type: 'event',
    flavour: 'Something in the walls whispers your name.',
    effect: 'Make a Sanity roll (5+ dice). Lose 1 Sanity and 1 Knowledge on failure.',
  },
  {
    id: 'evt_lights_out',
    name: 'Lights Out',
    type: 'event',
    flavour: 'Every light in the house goes dark.',
    effect: 'Make a Sanity roll (3+ dice). All explorers in the room lose 1 Sanity on failure.',
  },
  {
    id: 'evt_locked_safe',
    name: 'Locked Safe',
    type: 'event',
    flavour: 'A heavy safe with a combination lock.',
    effect: 'Make a Knowledge roll (5+ dice). Gain an Item card on success.',
  },
  {
    id: 'evt_mists',
    name: 'Mists from the Walls',
    type: 'event',
    flavour: 'A cold fog seeps from the walls.',
    effect: 'Make a Sanity roll (3+ dice). Lose 1 Sanity on failure.',
  },
  {
    id: 'evt_night_view',
    name: 'Night View',
    type: 'event',
    flavour: 'From the window you see the moon, impossibly large.',
    effect: 'Make a Knowledge roll (4+ dice). Gain 1 Knowledge on success.',
  },
  {
    id: 'evt_phone_call',
    name: 'Phone Call',
    type: 'event',
    flavour: 'The phone rings. You know you shouldn\'t answer it.',
    effect: 'Make a Sanity roll (4+ dice). Gain 1 Sanity on success, lose 1 Sanity on failure.',
  },
  {
    id: 'evt_rotten_wall',
    name: 'Rotten Wall',
    type: 'event',
    flavour: 'The wall crumbles as you lean against it.',
    effect: 'Make a Might roll (3+ dice). You may discover an adjacent room on success.',
  },
  {
    id: 'evt_silence',
    name: 'Silence',
    type: 'event',
    flavour: 'An absolute, deafening silence. Your heartbeat thunders.',
    effect: 'Make a Sanity roll (4+ dice). Gain 1 Sanity on success.',
  },
  {
    id: 'evt_skeletons',
    name: 'Skeletons',
    type: 'event',
    flavour: 'You discover a pile of bones. Some are fresh.',
    effect: 'Make a Sanity roll (5+ dice). Lose 1 Sanity on failure.',
  },
  {
    id: 'evt_smoke',
    name: 'Smoke',
    type: 'event',
    flavour: 'Thick smoke billows from nowhere.',
    effect: 'Make a Speed roll (4+ dice). Take 1 Speed damage on failure.',
  },
  {
    id: 'evt_something_slimy',
    name: 'Something Slimy',
    type: 'event',
    flavour: 'You step in something cold and wet.',
    effect: 'Make a Speed roll (3+ dice). Lose 1 Speed on failure.',
  },
  {
    id: 'evt_spider',
    name: 'Spider',
    type: 'event',
    flavour: 'A spider the size of a fist drops on you.',
    effect: 'Make a Speed roll (4+ dice) or Sanity roll (4+ dice). Take 1 damage on failure.',
  },
  {
    id: 'evt_whoops',
    name: 'Whoops!',
    type: 'event',
    flavour: 'The floor gives way beneath you.',
    effect: 'Make a Speed roll (3+ dice). Fall to the basement on failure.',
  },
]

// ══════════════════════════════════════════════════════════════════════
//  ITEM CARDS
// ══════════════════════════════════════════════════════════════════════

export const ITEM_CARDS: CardDef[] = [
  {
    id: 'item_amulet',
    name: 'Amulet of the Ages',
    type: 'item',
    flavour: 'Ancient and heavy with power.',
    effect: 'Gain 1 to all traits (Might, Speed, Knowledge, Sanity).',
  },
  {
    id: 'item_angel_feather',
    name: 'Angel Feather',
    type: 'item',
    flavour: 'Soft as a whisper, warm as hope.',
    effect: 'Gain 2 Sanity. You are immune to Sanity damage while holding this.',
  },
  {
    id: 'item_armor',
    name: 'Armor',
    type: 'item',
    flavour: 'Rusty but still solid.',
    effect: 'Reduce all Physical damage by 1 (minimum 0).',
  },
  {
    id: 'item_axe',
    name: 'Axe',
    type: 'item',
    flavour: 'Sharp enough to split bone.',
    effect: 'Add 1 to your Might during attacks.',
  },
  {
    id: 'item_bell',
    name: 'Bell',
    type: 'item',
    flavour: 'It tolls with an unearthly resonance.',
    effect: 'Once per turn, ring the bell to gain 1 Sanity.',
  },
  {
    id: 'item_blood_dagger',
    name: 'Blood Dagger',
    type: 'item',
    flavour: 'The blade hums for blood.',
    effect: 'Add 2 to Might during attacks. Lose 1 Sanity each time you use it.',
  },
  {
    id: 'item_bottle',
    name: 'Bottle',
    type: 'item',
    flavour: 'The liquid inside glows faintly.',
    effect: 'Drink to gain 2 to any one trait. One use only.',
  },
  {
    id: 'item_candle',
    name: 'Candle',
    type: 'item',
    flavour: 'A tiny flame against the darkness.',
    effect: 'Gain 1 Knowledge. Immune to Darkness effects.',
  },
  {
    id: 'item_dark_dice',
    name: 'Dark Dice',
    type: 'item',
    flavour: 'Carved from obsidian, warm to the touch.',
    effect: 'Once per turn, roll an extra die on any roll.',
  },
  {
    id: 'item_dynamite',
    name: 'Dynamite',
    type: 'item',
    flavour: 'Handle with care. Or don\'t.',
    effect: 'Place and detonate in a room. All explorers in the room take 3 Physical damage.',
  },
  {
    id: 'item_healing_salve',
    name: 'Healing Salve',
    type: 'item',
    flavour: 'A strange-smelling paste that tingles.',
    effect: 'Apply to heal 1 Physical damage. 3 uses.',
  },
  {
    id: 'item_lucky_stone',
    name: 'Lucky Stone',
    type: 'item',
    flavour: 'It\'s warm in your pocket.',
    effect: 'Once per turn, reroll any one die roll.',
  },
  {
    id: 'item_medical_kit',
    name: 'Medical Kit',
    type: 'item',
    flavour: 'Everything a doctor would need. Almost.',
    effect: 'Heal 1 Might or 1 Speed damage. Usable once per turn.',
  },
  {
    id: 'item_music_box',
    name: 'Music Box',
    type: 'item',
    flavour: 'A haunting melody that calms the soul.',
    effect: 'Gain 1 Sanity when you open it. Usable once per turn.',
  },
  {
    id: 'item_puzzle_box',
    name: 'Puzzle Box',
    type: 'item',
    flavour: 'Intricate and impossible to put down.',
    effect: 'Make a Knowledge roll (5+ dice). Gain 2 Knowledge on success.',
  },
  {
    id: 'item_rabbit_foot',
    name: "Rabbit's Foot",
    type: 'item',
    flavour: 'Lucky for you. Less so for the rabbit.',
    effect: 'Gain 1 Speed.',
  },
  {
    id: 'item_revolver',
    name: 'Revolver',
    type: 'item',
    flavour: 'Six shots. Make them count.',
    effect: 'Instead of Might, use Speed for your attack roll.',
  },
  {
    id: 'item_ring',
    name: 'Ring',
    type: 'item',
    flavour: 'An ornate ring set with a dark gem.',
    effect: 'Gain 1 Knowledge.',
  },
  {
    id: 'item_sacrificial_dagger',
    name: 'Sacrificial Dagger',
    type: 'item',
    flavour: 'Stained and wicked-looking.',
    effect: 'Add 2 to Might during attacks.',
  },
  {
    id: 'item_smelling_salts',
    name: 'Smelling Salts',
    type: 'item',
    flavour: 'One whiff and the world snaps into focus.',
    effect: 'Gain 1 Knowledge. Usable on yourself or an adjacent explorer.',
  },
]

// ══════════════════════════════════════════════════════════════════════
//  OMEN CARDS
// ══════════════════════════════════════════════════════════════════════

export const OMEN_CARDS: CardDef[] = [
  {
    id: 'omen_bite',
    name: 'Bite',
    type: 'omen',
    flavour: 'Something in the dark bites you. The wound festers.',
    effect: 'Lose 1 Might. Gain 1 Speed.',
  },
  {
    id: 'omen_book',
    name: 'Book',
    type: 'omen',
    flavour: 'A leather-bound tome full of secrets.',
    effect: 'Gain 2 Knowledge.',
  },
  {
    id: 'omen_crystal_ball',
    name: 'Crystal Ball',
    type: 'omen',
    flavour: 'Swirling mists reveal terrible futures.',
    effect: 'Gain 2 Sanity. Look at the top 3 cards of any deck.',
  },
  {
    id: 'omen_dog',
    name: 'Dog',
    type: 'omen',
    flavour: 'A mangy mutt follows you loyally.',
    effect: 'Companion. Gain 1 Might and 1 Sanity while you have the Dog.',
  },
  {
    id: 'omen_girl',
    name: 'Girl',
    type: 'omen',
    flavour: 'A frightened child clutches your hand.',
    effect: 'Companion. Gain 1 Sanity and 1 Knowledge while you have the Girl.',
  },
  {
    id: 'omen_holy_symbol',
    name: 'Holy Symbol',
    type: 'omen',
    flavour: 'It glows with a faint, reassuring light.',
    effect: 'Gain 2 Sanity.',
  },
  {
    id: 'omen_madman',
    name: 'Madman',
    type: 'omen',
    flavour: 'He babbles incoherently but seems to know things.',
    effect: 'Companion. Gain 2 Might and lose 1 Sanity while you have the Madman.',
  },
  {
    id: 'omen_mask',
    name: 'Mask',
    type: 'omen',
    flavour: 'A porcelain mask that fits perfectly.',
    effect: 'Gain 2 Knowledge. Lose 2 Sanity.',
  },
  {
    id: 'omen_medallion',
    name: 'Medallion',
    type: 'omen',
    flavour: 'Cold metal etched with strange runes.',
    effect: 'Gain 1 to all traits.',
  },
  {
    id: 'omen_ring',
    name: 'Ring',
    type: 'omen',
    flavour: 'It whispers promises of power.',
    effect: 'Gain 2 Knowledge.',
  },
  {
    id: 'omen_skull',
    name: 'Skull',
    type: 'omen',
    flavour: 'It stares at you with empty sockets.',
    effect: 'Lose 2 Sanity. Gain 2 Knowledge.',
  },
  {
    id: 'omen_spear',
    name: 'Spear',
    type: 'omen',
    flavour: 'Ancient and wickedly sharp.',
    effect: 'Gain 2 Might. Add 2 to Might during attacks.',
  },
  {
    id: 'omen_spirit_board',
    name: 'Spirit Board',
    type: 'omen',
    flavour: 'The planchette moves on its own.',
    effect: 'Gain 2 Sanity.',
  },
]

// ── Aggregated ───────────────────────────────────────────────────────

export const ALL_CARDS: CardDef[] = [...EVENT_CARDS, ...ITEM_CARDS, ...OMEN_CARDS]

export const CARD_MAP: Record<string, CardDef> = Object.fromEntries(
  ALL_CARDS.map((c) => [c.id, c])
)
