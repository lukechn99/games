import type { RoomDef } from '../types'

/**
 * Room tiles for Betrayal at House on the Hill.
 *
 * Starting rooms are pre-placed on the board.
 * Other rooms are drawn from the stack during exploration.
 *
 * `doors` lists which walls have openings. When placed, a tile may be
 * rotated so its doors align with the adjacent room's opening.
 */
export const ROOMS: RoomDef[] = [
  // ══════════════════════════════════════════════════════════════════
  // STARTING TILES (pre-placed)
  // ══════════════════════════════════════════════════════════════════
  {
    id: 'entrance_hall',
    name: 'Entrance Hall',
    floors: ['ground'],
    doors: ['north', 'south', 'east'],
    isStarting: true,
    effect: 'The front door is barred shut behind you.',
  },
  {
    id: 'foyer',
    name: 'Foyer',
    floors: ['ground'],
    doors: ['north', 'south', 'west'],
    isStarting: true,
    effect: 'Dusty portraits stare down at you from the walls.',
  },
  {
    id: 'grand_staircase',
    name: 'Grand Staircase',
    floors: ['ground'],
    doors: ['north', 'south'],
    isStarting: true,
    effect: 'Connects to Upper Landing (upper floor) and Basement Landing (basement).',
  },
  {
    id: 'upper_landing',
    name: 'Upper Landing',
    floors: ['upper'],
    doors: ['north', 'south', 'east', 'west'],
    isStarting: true,
    effect: 'The top of the grand staircase. Drafts whistle through the halls.',
  },
  {
    id: 'basement_landing',
    name: 'Basement Landing',
    floors: ['basement'],
    doors: ['north', 'south', 'east', 'west'],
    isStarting: true,
    effect: 'Cold, damp stairs descend into darkness.',
  },

  // ══════════════════════════════════════════════════════════════════
  // GROUND FLOOR ROOMS
  // ══════════════════════════════════════════════════════════════════
  {
    id: 'ballroom',
    name: 'Ballroom',
    floors: ['ground'],
    doors: ['north', 'south', 'east', 'west'],
    cardDraw: 'event',
    effect: 'The music plays on, though no one dances.',
  },
  {
    id: 'bloody_room',
    name: 'Bloody Room',
    floors: ['ground'],
    doors: ['north', 'south', 'east', 'west'],
    cardDraw: 'item',
    effect: 'The floor is covered in something dark and sticky.',
  },
  {
    id: 'charred_room',
    name: 'Charred Room',
    floors: ['ground', 'upper'],
    doors: ['north', 'south', 'east', 'west'],
    cardDraw: 'omen',
    effect: 'Everything in this room is blackened by fire.',
  },
  {
    id: 'conservatory',
    name: 'Conservatory',
    floors: ['ground', 'upper'],
    doors: ['north', 'east'],
    cardDraw: 'event',
    effect: 'Dead plants and cracked glass fill this once-beautiful room.',
  },
  {
    id: 'dining_room',
    name: 'Dining Room',
    floors: ['ground'],
    doors: ['north', 'south', 'east'],
    cardDraw: 'omen',
    effect: 'A table set for a feast that no one will eat.',
  },
  {
    id: 'drawing_room',
    name: 'Drawing Room',
    floors: ['ground'],
    doors: ['north', 'south'],
    cardDraw: 'event',
    effect: 'Faded paintings and velvet furniture. Someone was wealthy once.',
  },
  {
    id: 'game_room',
    name: 'Game Room',
    floors: ['ground', 'upper', 'basement'],
    doors: ['north', 'south', 'east', 'west'],
    cardDraw: 'event',
    effect: 'Chess pieces move on their own. The game is not finished.',
  },
  {
    id: 'gardens',
    name: 'Gardens',
    floors: ['ground'],
    doors: ['north', 'east'],
    cardDraw: 'event',
    effect: 'Overgrown and wild. Something rustles in the hedges.',
  },
  {
    id: 'kitchen',
    name: 'Kitchen',
    floors: ['ground', 'basement'],
    doors: ['north', 'south'],
    cardDraw: 'omen',
    effect: 'Something is cooking. You don\'t want to know what.',
  },
  {
    id: 'organ_room',
    name: 'Organ Room',
    floors: ['ground', 'upper'],
    doors: ['south', 'east'],
    cardDraw: 'event',
    effect: 'The pipes wheeze a discordant melody.',
  },
  {
    id: 'patio',
    name: 'Patio',
    floors: ['ground'],
    doors: ['north', 'south', 'east', 'west'],
    cardDraw: 'event',
    effect: 'Cracked flagstones and a fountain that runs red.',
  },
  {
    id: 'servants_quarters',
    name: "Servant's Quarters",
    floors: ['ground', 'upper', 'basement'],
    doors: ['north', 'south'],
    cardDraw: 'omen',
    effect: 'Cramped rooms with narrow beds. Someone still lives here.',
  },
  {
    id: 'statuary_corridor',
    name: 'Statuary Corridor',
    floors: ['ground', 'upper', 'basement'],
    doors: ['north', 'south'],
    cardDraw: 'event',
    effect: 'Stone figures watch you pass. Did that one just move?',
  },
  {
    id: 'coal_chute',
    name: 'Coal Chute',
    floors: ['ground'],
    doors: ['north', 'south'],
    specialExit: { toFloor: 'basement' },
    effect: 'A dark chute slides down to the basement. One way trip down.',
  },

  // ══════════════════════════════════════════════════════════════════
  // UPPER FLOOR ROOMS
  // ══════════════════════════════════════════════════════════════════
  {
    id: 'abandoned_room',
    name: 'Abandoned Room',
    floors: ['upper'],
    doors: ['north', 'south', 'east', 'west'],
    cardDraw: 'omen',
    effect: 'Someone used to live here. The belongings are scattered.',
  },
  {
    id: 'attic',
    name: 'Attic',
    floors: ['upper'],
    doors: ['south'],
    cardDraw: 'event',
    effect: 'Dusty boxes and forgotten memories. The roof creaks.',
    barrier: true,
  },
  {
    id: 'balcony',
    name: 'Balcony',
    floors: ['upper'],
    doors: ['north', 'south'],
    cardDraw: 'omen',
    effect: 'A precarious overlook. The railing is rotting.',
  },
  {
    id: 'bedroom',
    name: 'Bedroom',
    floors: ['upper'],
    doors: ['north', 'east'],
    cardDraw: 'event',
    effect: 'The bed is made. Someone is expected.',
  },
  {
    id: 'gallery',
    name: 'Gallery',
    floors: ['upper'],
    doors: ['north', 'south'],
    cardDraw: 'event',
    effect: 'Portraits of the family. Their eyes follow you.',
  },
  {
    id: 'library',
    name: 'Library',
    floors: ['upper'],
    doors: ['north', 'south', 'west'],
    cardDraw: 'event',
    effect: 'Ancient tomes line the shelves. Knowledge waits here.',
  },
  {
    id: 'master_bedroom',
    name: 'Master Bedroom',
    floors: ['upper'],
    doors: ['north', 'south', 'east'],
    cardDraw: 'omen',
    effect: 'A lavish room with a four-poster bed. Something under it moves.',
  },
  {
    id: 'nursery',
    name: 'Nursery',
    floors: ['upper'],
    doors: ['north', 'south'],
    cardDraw: 'event',
    effect: 'A crib rocks by itself. A music box plays softly.',
  },
  {
    id: 'operating_laboratory',
    name: 'Operating Laboratory',
    floors: ['upper', 'basement'],
    doors: ['north', 'south', 'east'],
    cardDraw: 'event',
    effect: 'Surgical tools and something on the table. Don\'t look.',
  },
  {
    id: 'sewing_room',
    name: 'Sewing Room',
    floors: ['upper'],
    doors: ['north', 'south'],
    cardDraw: 'event',
    effect: 'Needles and thread. A half-finished doll watches you.',
  },
  {
    id: 'tower',
    name: 'Tower',
    floors: ['upper'],
    doors: ['south'],
    cardDraw: 'event',
    effect: 'A narrow staircase spirals upward. The wind howls.',
  },

  // ══════════════════════════════════════════════════════════════════
  // BASEMENT ROOMS
  // ══════════════════════════════════════════════════════════════════
  {
    id: 'catacombs',
    name: 'Catacombs',
    floors: ['basement'],
    doors: ['north', 'south', 'east', 'west'],
    cardDraw: 'omen',
    effect: 'Bones are stacked neatly in the walls.',
  },
  {
    id: 'chasm',
    name: 'Chasm',
    floors: ['basement'],
    doors: ['north', 'east'],
    cardDraw: 'event',
    effect: 'A gaping void. You can barely see the other side.',
    barrier: true,
  },
  {
    id: 'crypt',
    name: 'Crypt',
    floors: ['basement'],
    doors: ['north', 'south'],
    cardDraw: 'event',
    effect: 'Stone coffins line the walls. One is open.',
  },
  {
    id: 'dungeon',
    name: 'Dungeon',
    floors: ['basement'],
    doors: ['north', 'south'],
    cardDraw: 'event',
    effect: 'Chains and manacles. The smell of rust and fear.',
    barrier: true,
  },
  {
    id: 'furnace_room',
    name: 'Furnace Room',
    floors: ['basement'],
    doors: ['north', 'south', 'west'],
    cardDraw: 'omen',
    effect: 'The furnace burns with an unnatural heat.',
  },
  {
    id: 'larder',
    name: 'Larder',
    floors: ['basement'],
    doors: ['north', 'south'],
    cardDraw: 'item',
    effect: 'Shelves of preserved… things. Some might be edible.',
  },
  {
    id: 'mystic_elevator',
    name: 'Mystic Elevator',
    floors: ['ground', 'upper', 'basement'],
    doors: ['north', 'south', 'east', 'west'],
    dumbwaiter: true,
    effect: 'Roll to determine which floor the elevator takes you.',
  },
  {
    id: 'pentagram_chamber',
    name: 'Pentagram Chamber',
    floors: ['basement'],
    doors: ['north', 'south', 'east'],
    cardDraw: 'omen',
    effect: 'A pentagram glows faintly on the floor. Power resonates.',
  },
  {
    id: 'underground_lake',
    name: 'Underground Lake',
    floors: ['basement'],
    doors: ['north', 'south'],
    cardDraw: 'event',
    effect: 'Black, still water. Something ripples just below the surface.',
  },
  {
    id: 'wine_cellar',
    name: 'Wine Cellar',
    floors: ['basement'],
    doors: ['north', 'south', 'east'],
    cardDraw: 'item',
    effect: 'Dusty bottles. Some may hold more than wine.',
  },
  {
    id: 'creaky_hallway',
    name: 'Creaky Hallway',
    floors: ['ground', 'upper', 'basement'],
    doors: ['north', 'south', 'east', 'west'],
    effect: 'The floorboards groan with every step.',
  },
  {
    id: 'dusty_hallway',
    name: 'Dusty Hallway',
    floors: ['ground', 'upper', 'basement'],
    doors: ['north', 'south', 'east', 'west'],
    effect: 'Thick dust coats everything. Footprints appear behind you.',
  },
  {
    id: 'collapsed_room',
    name: 'Collapsed Room',
    floors: ['ground', 'upper', 'basement'],
    doors: ['north', 'south'],
    cardDraw: 'event',
    effect: 'The ceiling has partially fallen. Debris everywhere.',
  },
  {
    id: 'chapel',
    name: 'Chapel',
    floors: ['ground', 'upper'],
    doors: ['north', 'south', 'east'],
    cardDraw: 'event',
    effect: 'Stained glass windows depict terrible scenes. Holy ground.',
  },
  {
    id: 'gymnasium',
    name: 'Gymnasium',
    floors: ['upper', 'basement'],
    doors: ['north', 'south', 'east', 'west'],
    cardDraw: 'omen',
    effect: 'Exercise equipment and the echo of bouncing balls.',
  },
  {
    id: 'junk_room',
    name: 'Junk Room',
    floors: ['ground', 'upper', 'basement'],
    doors: ['north', 'south', 'east', 'west'],
    cardDraw: 'item',
    effect: 'Piles of discarded items. One person\'s trash...',
  },
  {
    id: 'research_laboratory',
    name: 'Research Laboratory',
    floors: ['upper', 'basement'],
    doors: ['north', 'south', 'east'],
    cardDraw: 'event',
    effect: 'Bubbling beakers and strange formulae on the chalkboard.',
  },
  {
    id: 'storeroom',
    name: 'Storeroom',
    floors: ['upper', 'basement'],
    doors: ['north', 'south'],
    cardDraw: 'item',
    effect: 'Shelves of supplies. Some useful, some unsettling.',
  },
]

/** Map for quick lookups. */
export const ROOM_MAP: Record<string, RoomDef> = Object.fromEntries(
  ROOMS.map((r) => [r.id, r])
)

/** Non-starting rooms available for the exploration draw stack. */
export const ROOM_STACK: RoomDef[] = ROOMS.filter((r) => !r.isStarting)

/** Starting rooms. */
export const STARTING_ROOMS: RoomDef[] = ROOMS.filter((r) => r.isStarting)
