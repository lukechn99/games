# Hide and Seek: design document

A prop-hunt party game for Game Night, built in Godot. Hiders disguise
themselves as everyday objects on a farm; seekers hunt them down before the
clock runs out. Friends in the same room play from their phones or
computers, connected peer to peer through the same rooms, video call and
relay as the other games.

This is a living document and the spec the code is built from. When a
decision changes, change it here first.

**Status key**
- **Decided**: agreed; build to this.
- **Proposed**: a recommendation waiting for a yes or no.
- **Open**: needs a decision before the work that depends on it.

---

## 1. The pitch

**Decided (from the owner's brief):** Call of Duty's Prop Hunt, our way.

- Two teams. **Hiders** pick an object from the map and become it. **Seekers** search the map and tag anything suspicious.
- Instead of the whistles that give hiders away in Call of Duty, **hiders burst sparks and confetti** for a moment, on a timer.
- **First map: a farm** with a farmhouse, a barn, a silo and the yard around them.
- Built in **Godot**, like Animal Karts.

Name: **Hide and Seek** (working name; **Open**, see 15).

## 2. How Call of Duty's Prop Hunt works (research)

What the reference mode does, so we know what we're keeping and changing:

- **Teams:** one team hunts, one hides. Hiders are assigned or choose map objects ("props"), control them and hide anywhere on the map. Hunters are ordinary soldiers with a gun.
- **Winning:** hiders win by surviving until the timer runs out; hunters win by finding them all.
- **The whistle:** every 25 seconds the props whistle **one at a time, in sequence**, with a countdown to the next whistle on screen. A whistle gives away roughly where a prop is, so props often move after one. Hunters stand still and listen.
- **Prop abilities (WWII):** change to a different prop **twice per round**; drop **decoys** (copies of yourself) **three times per round**; a flash that disorients and slows hunters so the prop can escape.
- **Hunters:** shoot suspicious objects; a hit marker confirms a hidden player. In the mobile version hunters have limited bullets per round, so spraying everything early leaves them empty later.
- **Common hider tactics:** pick small objects; pick ones that fit the place (tires in a garage, not beside the house); hide near a teammate in a bigger prop, since hunters who found one prop often don't search the same spot again.
- Common across prop hunt versions (not from these pages): hunters are blinded for the first stretch of each round while props hide, and props can **lock their rotation** so they can look around without the object turning.

What this means for us: the fun comes from (1) props that look exactly like the scenery, (2) a regular tell that forces hiders to take risks, and (3) a cost to guessing wrong. All three must survive the move to phones and to a visual tell.

## 3. Players and platforms

| | |
|---|---|
| Players | **Proposed:** 3–10 people. Bots fill in (12). |
| Teams | **Decided 2026-11-25:** roles are dealt at random each round, no choosing or switching. Seekers = (players + 1) ÷ 3 rounded down, at least 1; bots count as players: 2–4 players → 1 seeker, 5–7 → 2, 8–10 → 3. |
| Devices | Phones (iOS Safari, Android Chrome) and desktop browsers, same as the racer. |
| Orientation | Landscape while playing: in portrait the racer's prompt asks to turn the phone (owner, 2026-11-25). |
| Session | One room plays several rounds; teams swap so everyone seeks once (5). |

## 4. Stages of a round

**Proposed flow**

1. **Lobby.** The usual Game Night lobby; the host picks Hide and Seek.
2. **Teams.** The room deals the seekers at random (Decided 2026-11-25). **Open:** whether to favour people who haven't sought yet, so a match evens out.
3. **Hide phase (45 s).** Hiders are dropped in the yard, pick a prop and run to a spot. Seekers wait in the farmhouse kitchen with the screen dark and a countdown, and can't move.
4. **Seek phase (3 min).** Seekers are released. Every 25 s the hiders spark one after another (6). Seekers tag suspicious objects (7).
5. **Final minute.** Sparks come every 15 s instead of 25, so the end gets tense instead of stalling.
6. **Round over.** When all hiders are found (seekers win) or the timer ends (surviving hiders win). A results card shows who hid where (a top-down map with each hider's spot), who found whom, and the best hiding spot.
7. **Next round** with new teams; after everyone has sought once, match standings.

**Decided 2026-11-25: a found hider joins the seekers** for the rest of the round (with a fresh paintball supply), so nobody sits out, as in playground hide and seek.

## 5. Scoring (Proposed)

- Hider: 1 point for every 30 s survived in the seek phase, 3 for surviving the round.
- Seeker: 3 points for each hider found (split if two seekers tag the same one within a second).
- A match is as many rounds as it takes for everyone to seek once. Most points wins.

## 6. The spark tell (instead of the whistle)

**Decided:** a short burst of sparks and confetti flies off a hider instead of a sound.

The catch, and what to do about it: **a whistle carries through walls; confetti doesn't.** A hider in the barn's hayloft would be invisible to a seeker in the yard, and the tell would stop working indoors. So the burst has two parts (**Decided 2026-11-25**):

- **The pop (on the prop):** about 1 second of bright confetti and sparks thrown off the object. Close up, it tells you exactly which object it was.
- **The plume (above it):** a thin streak of sparks shoots straight up about 8–10 m and bursts, like a small firework, high enough to clear the barn roof and be seen from across the farm. From afar, it tells you roughly where to look, the way a distant whistle does.

**Warning for hiders (Decided 2026-11-25):** a hider always knows their own burst is coming: for the 5 seconds before it (Proposed), the edges of that hider's screen flash, faster as it gets closer, with no countdown numbers. That's time to stay put or make a run for it. Only that hider sees it; seekers only see the cycle countdown below.

**Proposed details**
- Sequence like the reference: hiders spark **one at a time**, about a second apart, in a random order each cycle so the order doesn't reveal who's who. A countdown to the next cycle shows for everyone.
- Each hider's confetti is the same colours, so the colour doesn't say who it is.
- Indoors, the plume rises through the roof (drawn over it, faded where it passes through), so it still shows outside roughly where the hider is.
- **Extra pop (optional, Proposed):** a hider can spark on purpose ("taunt") for bonus points, a classic prop hunt risk-for-reward.
- Bonus: a visual tell works with the sound off, which is how most people play on a phone in a room together, and works for players who can't hear.

**How it's built:** the spark schedule comes from the host's clock, so every phone shows the same burst at the same moment with no extra messages. Particles are `CPUParticles3D` (cheap, the same on every device, no shader compile on first use if drawn once while loading; see 14).

## 7. Seekers

- **Tagging tool (Decided 2026-11-25): a paintball marker.** Short range (about 15 m). A hit on a hider shows a hit marker and a burst; that hider is found.
- **Paint fades (Decided 2026-11-25):** a splat on an ordinary object shows everyone it's been checked, but only for a while. If paint stayed all game, seekers could rule out every checked object for good, and the farm would get "solved". **Proposed:** a splat stays bright for 20 s, then fades out over the next 20 s (40 s in all, a bit more than one spark cycle). Once it's gone, that spot is worth checking again. It's also a hider tactic: sneak in next to something freshly painted, because seekers think that corner is done.
- **Limited ammo (Decided 2026-11-25):** every wrong guess spends a paintball, so seekers can't spray everything. **Proposed:** each seeker starts a round with **100 paintballs** (owner, 2026-11-25: at least 100) and gets **+3 for each hider they find**. No other refills. The host can change the starting amount. If every seeker runs out while hiders are left, the hiders win the round straight away.
- The ammo count shows top left; at 10 or fewer it turns red.
- **View:** first person, like the reference, so seekers see the world at human height and small props are easy to overlook.
- **Optional seeker gadget (Proposed, later):** one "sniff" per round that makes the nearest hider spark immediately.

## 8. Hiders

- **Your prop is assigned at random (Decided 2026-11-25)** from the pool of objects used as scenery around the farm (9.2). You become that exact object: same model, size, colours and shadow as the scenery copies.
- **Two rerolls per round (Decided 2026-11-25):** don't like your prop? Reroll for another random one, twice. (These replace Call of Duty's two prop changes.) **Proposed:** rerolls work any time, but a reroll during the seek phase swaps you on the spot, which a watching seeker could notice.
- **Jumping (Decided 2026-11-25):** hiders and seekers both jump, about 1.3 m (Proposed), so a hay bale can hop up onto a stack of two bales and sit among the others. Seekers can climb the same stacks to look around.
- **View:** third person, so you can see around you and check you blend in.
- **Lock rotation:** a toggle so you can look around without the object turning. Locked props sit square on the ground like the real ones.
- **Decoys: 3 per round** (built 2026-11-25): drop a copy of your current prop where you stand (Q, or the Decoy button). Everyone sees them (they're in the room's state). A seeker who paints one spends the paintball and it pops in a puff of confetti. Hider bots leave two somewhere else once hidden; seeker bots can be fooled by them. **Open:** whether decoys should spark too, on their own timing.
- **Escape (Proposed instead of a flashbang):** a **chaff burst**: a cloud of hay and feathers that blocks seekers' view for 2 s, once per round.
- **Moving:** big props move slower than small ones (Proposed), so a hay bale is safe to sit in but slow to run with, and a bucket is quick but easy to spot when it moves.

## 9. The farm map

### 9.1 Layout (Proposed; we design it together)

About 90 × 90 m, walkable everywhere, with buildings you can go inside:

| Area | What's there | Why it's good to play in |
|---|---|---|
| **Farmhouse** | Two floors: porch, kitchen (seekers' waiting room), living room, two bedrooms, attic, cellar | Cluttered rooms full of small props; stairs and doors make chases fun |
| **Barn** | Animal stalls, a tack wall, a hayloft reached by a ladder, big doors at both ends | The centrepiece: many hay bales, open sight lines from the loft |
| **Silo** | A tall round silo with a spiral stair inside and a lookout at the top | A seeker vantage point; dangerous to hide near |
| **Chicken coop** | Small hut with nesting boxes, a fenced run | Tight space, lots of small objects |
| **Tractor shed** | An open-fronted shed with a tractor, tools, tires, oil drums | Hiding in plain sight among clutter |
| **Yard** | Well, water trough, wood pile, washing line, wagon | Open ground between buildings: crossing it is the risk |
| **Pumpkin patch and garden** | Rows of pumpkins, a scarecrow, a garden shed | Many identical props |
| **Corn rows** | A small field of tall corn on one edge | Blocks sight; must be drawn cheaply (14) |
| **Pond** | Small dock, a rowboat, reeds | Edge of the map |

Fences and a tree line mark the edge.

### 9.2 Prop list (Proposed)

Three sizes. Hiders' props come only from objects used as scenery, and every one appears several times, so there's always somewhere it fits in. Owner's first ideas (2026-11-25): rakes leaning against walls, hay bales, trash cans, tires, chairs.

- **Small:** bucket, milk can, watering can, lantern, flower pot, pumpkin, boot.
- **Medium:** trash can, tire, chair, barrel, crate, feed sack, wheelbarrow, small hay bale, rake (leans against a wall).
- **Large:** round hay bale, water trough, wood pile, scarecrow, dresser.

**Leaning props (Proposed):** a rake (or shovel, pitchfork) only fits in leaning against a wall. A hider who gets one tilts against the nearest wall when they lock rotation, and stands upright (suspicious) when they don't.

**H0 starts with:** square hay bale, trash can, tire, chair, crate, bucket and rake.

Rule: **a prop must look the same everywhere.** No hand-placed variations that only scenery copies have, and the same blob shadow on scenery copies and on hiders, or a hider stands out.

### 9.3a Textured props (Decided 2026-11-25: the owner asked for textured models that look great and run fast)

Built by `hideseek/tools/blender/props.py` (`python3`, bpy), one model at a time, each approved by the owner before the next:
- **One mesh, one material, one draw call** per prop; 300–1,500 triangles; sized to the prop's collision box, origin at the bottom centre.
- **Detail is baked, not modelled:** each prop's look is a procedural Blender material (straw, grain, rubber, metal), baked once into a 512 px colour texture with soft ambient occlusion multiplied in, and a 512 px normal map. Both are JPEGs packed in the `.glb`.
- **Normal maps are optional:** `?relief=off` (and later, Low quality) draws without them.
- **Lighting:** the shade is warm-neutral with a little sky, not pure sky blue, which turned straw in shadow olive green.
- Checks: each model is one surface, within 1,500 triangles, and matches its collision box.

| Prop | Status | Triangles | File |
|---|---|---|---|
| Hay bale | **Approved** 2026-11-25 | 676 | 151 KB |
| Tractor (scenery, not a hider prop) | Waiting for approval | 3,960 | 378 KB (1024 px textures) |

### 9.3b Buildings, ground and light (Decided 2026-11-25: the owner asked for wood siding on the barn and house, shiny metal on the silo, grass outside, sun and shadows)

- **Surfaces** (`hideseek/tools/textures.py`, numpy): seamless 512 px colour and normal maps, each covering a fixed number of metres so every wall shares one scale: red board-and-batten barn siding with worn paint, white trim, a weathered corrugated barn roof, white lap siding, asphalt shingles, galvanized corrugated silo steel with ring seams and rivets, plank floor, grass, dirt, concrete. 20 JPEGs, 1.2 MB in all. They're named `.jpg.bin` so Godot ships them as they are; its import re-encodes them losslessly, several times larger.
- **One draw call per surface:** `scripts/surfaces.gd` merges every wall, trim piece and roof of a surface into one mesh, with UVs in metres (13 building surfaces in all).
- **Finishes:** silo steel is metallic and smooth, so it shines and reflects the sky; the barn roof is half-metallic; paint, wood, shingles and grass are matte.
- **What's there now:** the barn (siding, white trim on corners and doors, hayloft door, sliding doors slid open with white X braces, metal roof with overhang, plank floors inside); the farmhouse beside it, outside only (two storeys of lap siding on a concrete footing, shingle roof, chimney, 17 trimmed windows, a green front door, a porch facing the barn); the silo (13 m of galvanized steel on a concrete footing, bands, domed cap, a ladder); grass out to the horizon. Interiors for the house and silo come with the H1 farm.
- **Sun and shadows:** one shadow-casting sun (2 cascades, 45 m, soft filtering, 2048 px map); every prop, hider and building casts and receives, so a hider's shadow matches the scenery's. `?shadows=off` turns them off.
- **The brightening, measured:** in this renderer a shadow-casting sun is drawn in its own pass and added after conversion to screen colours, so sunlit surfaces came out about 1.4x brighter on screen (2x in light terms; the racer saw the same and turned shadows off). Measured with `?ambient=` and `?sunscale=` against the no-shadow picture: with shadows on, the sun runs at 0.45 of its strength and the fill light at 0.4 instead of 0.62. Sunlit grass then matches the no-shadow picture to within a few levels, and shade reads as shade (the barn floor inside went from 116 to 56 brightness).
- **Not yet measured on a phone.** Shadows are the most expensive effect; a frame-rate check on a real phone (like the racer's benchmark) should decide whether Low quality turns them off.

### 9.3c Inside the barn (Decided 2026-11-25: the owner asked for sections so it isn't monotonous)

- **Horse stalls** down the west wall: four, each with board walls and black bars to 2.2 m (too high to jump), a front with its gate swung open, straw bedding with a heap, a hay rack full of hay, and a water bucket.
- **Tool corner** under the loft (north-west): a workbench with a toolbox, vise and paint cans; a pegboard of hammers, wrenches, a saw and screwdrivers; metal shelves with crates, cans and a bucket; a shovel, pitchfork and hoe hanging on the wall, with rakes leaning beside them.
- **Tractor bay** under the loft (north-east): the textured tractor model, parked facing the north door, with a stack of tires.
- **Hay corner** (south-east): 40 bales stacked in steps, four high at the walls down to one at the front, so a bale hider can climb in, plus loose bales.
- Hiding spots moved to suit (10 now), including a bucket on the workbench, a tire on the stack and a bale on the hay steps.

### 9.3 Where the models come from (Proposed)

The same way as the racer: low-poly models built by script in Blender (`tools/blender`, `bpy`) to fixed triangle budgets, plus CC0 Kenney kits where they fit (the furniture and nature kits are likely candidates for the farmhouse interior and the trees; to check). Colours from one palette, toon-lit like Animal Karts so both games feel like one family.

## 10. Controls

- **Phone:** a movement stick shown bottom left from the start (owner, 2026-11-25: there was no visible way to move), drag on the right half to look, buttons bottom right: **Shoot** (seekers) or **Switch prop / Lock / Decoy** (hiders), and Jump. They're placed from the screen as it is every frame: they had been laid out for an upright phone and left below the screen after turning it sideways (owner's report, 2026-11-25). Touch input is set up like Bulwark's (no mouse events made from touches); mobile.js releases held touches when Safari interrupts; and a new thumb on the left always takes the stick, so a finger whose release never arrives can't leave it stuck "held". (A fallback that read mouse clicks as a thumb was removed: Safari's delayed fake clicks after a tap grabbed the stick and left it held, owner's screenshot 2026-11-25.)
- **Computer:** WASD and mouse (the pointer locks to the game), left click to shoot, F to switch prop, R to lock, Q decoy, Space jump.
- **Gamepad:** standard twin stick.

## 11. Audio

**Proposed:** light farm ambience and footsteps, but **nothing that gives a hider away**. The tell is visual only, as decided.

## 12. Bots (Proposed, later)

- **Hider bots** pick a prop and one of a set of hiding spots placed by hand in the map, then sit still.
- **Seeker bots** wander between areas, walk towards spark plumes, and tag objects near the last burst.
- Bots let one person test the whole game and let small rooms play.

## 13. Networking

**Proposed: the same setup as Animal Karts (racing design 13).** The Godot game runs in a frame on the room page and talks to it through the same message bridge (`net.js` / `net.gd`).

- **Round rules lane (reliable, through the host):** a normal room game module, `lib/games/hideseek/rules.ts`, with tests. It holds the teams, the phase start times on the host's clock, each hider's current prop, decoy and ability counts, who's been found, and scores. Reconnecting, spectating and pausing when the host leaves work as in the other games.
- **Player lane (direct between phones, may drop):** each phone sends its player's position, facing and stance about 15 times a second, through the direct links built for the racer. Hiders are mostly still, so this is lighter than racing.
- **Event lane (reliable):** tags, decoys and chaff, so every phone agrees.
- **Who decides a tag (Proposed):** the **seeker's phone**, from what it sees, then the host accepts it if that hider was within about 1 m of where the seeker saw it. Favouring the seeker feels fair here, because hiders are usually still, so lag rarely matters; the 1 m check stops a stale hit on a hider who just ran.
- **Sparks** need no messages (6).
- **Secrets:** every phone knows who's which prop (it has to draw them). A player could dig that out of their browser. Among friends, that's acceptable, same as the racer's stance on cheating.

### 13a. What's built (Decided and built 2026-11-25, owner: "make seeker bots and get multiplayer working", reusing the racer's code)

- **Rules:** `lib/games/hideseek/rules.ts` on the host: each round deals roles at random, a random prop per hider, 2 rerolls, 100 paintballs, finds (+3; a found hider becomes a seeker), the clock (45 s hide, 3 min seek), winners, scores (design 5), then 8 s of results and the next round. `hideseek/scripts/rules.gd` is the same rules on the same data for solo practice; a test checks the numbers and props match.
- **Reused from the racer:** the room engine, relay, lobby and call as they are; `racing/web/net.js` is now shared (it takes the game's name, `data-source`), as is `landscape.js`; `HideSeekView.tsx` follows `RacingView.tsx`; `scripts/session.gd` follows the racer's `net.gd` (Godot projects can't share scripts).
- **What goes where:** rules actions (reroll, shoot, find) go to the host; positions (about 12 a second, one message per phone with everyone it runs) and each paintball shot go player to player through the relay. Whoever fired decides whether it found someone (13). Sparks need no messages: every phone builds the schedule from the round's seed.
- **Bots:** room bots (Add a computer player) and practice bots are run by the host's game, acting through the rules for themselves (`as`). Hider bots take a free spot beside matching scenery (or a hand-placed spot) partway through the hide phase. Seeker bots walk a navigation mesh baked from the barn when the game loads (stalls, tractor and bales are obstacles; the ramp reaches the loft); a spark plume sends them roughly there (less exactly from farther away), where they paint things in sight near the spot, sometimes sensing the right one, and they chase a hider they see move. Levels: easy, medium, hard (aim, sense, shots per search, reaction).
- **Others in view:** other seekers appear as a farmhand in overalls and a straw hat with a paintball marker, each a different shirt colour, with their name above; hiders have no name.
- **Joining mid-round:** you watch (a seeker without paint) and play from the next round.
- **Checks:** `check.sh hideseek` plays a whole practice round headless (a seeker bot walks 100+ m and finds a hider; hider bots take free spots; a path from the yard to the loft). `tests/e2e/hideseek.mjs` runs two people and two bots in a real room in two Chrome instances through a local broker: same deal on both, the guest's movement seen by the host, a reroll seen by the other, bots in the same places on both, paintballs seen on the other screen.

## 14. Building and shipping

### 14.1 Why Godot, and why it fits (Proposed)

Godot was explored as the engine; it's the right choice:

- **Everything the racer built is reusable:** the web export without threads (GitHub Pages can't send the headers threaded builds need), the Compatibility renderer, the frame-on-the-room-page bridge, tilt/mobile/landscape/loading scripts, the CI job that tests and exports on push to `main`, quality levels, and the verify and bench tools.
- **The game is easier on phones than the racer:** players walk (about 5 m/s, not 25), the map is small, and most of it is still. Characters use `CharacterBody3D` with a capsule (seekers) or the prop's own collision shape (hiders), instead of vehicle physics.
- **Its hard parts are known ones:** interiors and first person close-ups (texture detail matters more), many small props (instancing), and particles (shader compile hitches, which the racer already solved by drawing everything once while loading).
- The alternative, a plain three.js page, would mean rebuilding the export pipeline, tools and bridge from nothing.

### 14.2 Project layout (Proposed)

- A **separate Godot project** in `hideseek/`, with this document in `docs/hideseek/` and its lessons in `docs/hideseek/LEARNINGS.md`. A separate project keeps each game's download to its own content.
- CI exports it to `public/hideseek/` (built, not committed, like `public/racing`).
- The racer's web scripts (`net.js`, `mobile.js`, `landscape.js`, `loading.js`) move to a shared folder that both exports copy, instead of being duplicated. **Open:** whether to rename `window.racingNet` to a neutral name at the same time (a small change to the racer and `RacingView.tsx`).
- **Download:** the Godot engine is about 9 MB compressed again on the first visit; the racer's cached copy can't be reused because it lives at a different address. **Open:** point both games at one shared engine file later, if the first load is a problem.

### 14.3 Performance plan (Proposed, using the racer's rules)

Same budgets and quality levels as Animal Karts (Low / Medium / High, everyone starts on Low, steps down under 45 fps), and the racer's lessons applied from day one:

- **Merge by prop kind:** all scenery copies of one prop are one `MultiMesh` (one draw call); hiders are drawn separately with the same mesh and material.
- **Corn as one or two instanced meshes,** stopping at a set distance.
- **Interiors don't draw from outside:** visibility ranges on interior clutter, and rooms that switch off when you're out of the building.
- **Draw every particle effect, prop and material once while loading,** so the first spark doesn't freeze the game.
- **No real lights below High;** windows and lanterns glow by themselves. Blob shadows, not real-time shadows.
- **Budgets:** about 150 draw calls on Low; props 300–1,500 triangles each.
- **Measuring:** a `?perf` overlay and fixed-viewpoint budgets in a verify script from the start; frame rate only from real phones.

### 14.4 Checking a change (Proposed)

- `rules.ts` has vitest tests for phases, timers, tags, ability counts and scores, run by `check.sh site`.
- Godot headless tests (as in `racing/tests/`) for movement, becoming a prop, the spark schedule and tag checks, run by `check.sh game` and in CI.
- A `verify` like the racer's: tests, a fast bot round, draw budgets at fixed viewpoints, approved pictures, download size. A dozen lines of output.

## 15. Open questions (for the owner)

1. **Name:** keep "Hide and Seek", or something farm-flavoured ("Barnyard Hide and Seek", "Hay Hunt")?
2. **Numbers to confirm:** 5 s edge-flash warning; paint bright for 20 s then fading over 20 s; 12 paintballs, +3 per find; 1.3 m jump?
3. **Abilities:** keep decoy ×3 and a chaff burst instead of a flashbang?
4. **Timers:** 45 s to hide, 3 min to seek, sparks every 25 s (15 s in the last minute)?
5. **Shared web scripts:** H0 copies the racer's loading script; share them properly in H2, when the bridge is needed.

## 16. Milestones (Proposed)

Each one is reviewed before the next starts.

| | Milestone | Done when |
|---|---|---|
| H0 | Sandbox (**built, 16a**) | In a grey test barn: walk as a seeker or hider on phone and computer, get a random prop and reroll it, jump onto stacked bales, lock rotation, shoot paintballs with limited ammo and fading paint, and see the spark burst, plume and edge-flash warning. Exports in CI to `/games/hideseek/`. |
| H1 | Rules and a grey farm | `rules.ts` with tests; the farm laid out in grey blocks with every building enterable; a full round with hide phase, sparks, tags and results, alone with bots. |
| H2 | In Game Night | Multiplayer through the room: teams, synced timers, positions, tags, decoys, reconnects, spectators. |
| H3 | Farm art | Blender props and buildings, palette, toon lighting, corn and pond. |
| H4 | Polish and phones | Abilities, scoring and results map, performance on real phones, verify and bench. |

## 16a. What's built (H0, 2026-11-25)

Play it at `/games/hideseek/` once merged (CI tests and exports it on push to `main`). It's one person in a test barn with three sandbox hiders; nothing is networked yet.

- **Where the code lives:** `hideseek/` (Godot 4.4.1, same settings as the racer). `scripts/rules.gd` holds the round rules with no nodes (timers, spark schedule, rerolls, ammo, finding, paint fade), so `rules.ts` can mirror it in H2. `props.gd` builds each prop as one merged mesh. `test_barn.gd` builds the barn, the scenery and the hiding spots. `player.gd` is both seekers and hiders.
- **The test barn:** walls, roof, doors at both ends, stalls, a hayloft reached by a ramp (ladders later), and the yard by the doors. 46 scenery props of 7 kinds: hay bales (including a double stack to hop onto), trash cans, tires, chairs, crates, buckets and rakes leaning on walls. Each kind is one MultiMesh, so one draw call.
- **You:** each round deals the roles at random among you and three bots (one seeker in four), with no switching (owner, 2026-11-25). There are no seeker bots yet, so in rounds where you hide, nobody hunts you. Test links can still pick a side with `?role=hider` or `?role=seeker`. Seekers start in the yard, blindfolded during the hide phase. Hiders get a random prop with 2 rerolls, can lock rotation (a rake then leans on the nearest wall) and see the edge flash before their burst.
- **Sandbox hiders:** three, in random hand-placed spots (8 spots, including a bale on top of the double stack). They spark on the real schedule and join the seekers' count when painted.
- **Paint:** 38 m/s with a slight drop, 15 m range, 12 shots plus 3 per find. Splats are about 0.55 m across, bright for 20 s, then fade over 20 s.
- **Sparks:** CPU particles. The plume is drawn without depth test so it shows through the roof. One burst, one splat and one paintball are drawn behind the loading cover so the first ones don't stutter.
- **Sandbox shortcuts:** hiding lasts 15 s here instead of 45. Test links: `?role=hider`, `?hide=N`, `?t=N` (start the clock at N), `?at=X,Z&look=YAW,PITCH`, `?sparknow`, `?seed=N`.
- **Not yet:** shadows (none, so scenery and hiders match), decoys, chaff, the farm beyond the barn, multiplayer, bots that move.
- **Checks:** `racing/tools/check.sh hideseek` (44 checks: the prop pool, rerolls, ammo, finding, winners, spark schedule and order, paint fade, a bale jumping onto a double stack, a seeker climbing it, jump height, a rake leaning on lock, paintball hits and range, the edge flash). CI runs the same.
- **Download:** about 9.5 MB compressed, almost all the Godot engine; the game itself is 48 KB.

## 17. Sources

- [Call of Duty: WWII Prop Hunt guide](https://www.callofduty.com/br/pt/wwii/landing/prop-hunt-guide): teams, whistle every 25 s in sequence, 2 prop changes, 3 decoys, flashbangs, hit markers.
- [Upcomer: how to play Prop Hunt in CoD Mobile](https://upcomer.com/how-to-play-prop-hunt-in-cod-mobile-best-strategies-to-use/) (2019, marked outdated): limited bullets, hider tactics.
- [Thunderpick: Call of Duty Prop Hunt](https://thunderpick.io/blog/call-of-duty-prop-hunt): couldn't be opened; not used.
- Animal Karts design and lessons: `docs/racing/DESIGN.md`, `docs/racing/LEARNINGS.md`.

## 18. Decision log

- 2026-11-25: Game started from the owner's brief: prop hunt modelled on Call of Duty, sparks and confetti instead of sounds, farm as the first map, explore Godot. This document drafted; everything not in the brief is Proposed.
- 2026-11-25: Owner review: spark plume decided; hiders get a warning countdown before their own burst; seekers use a paintball marker; paint fades instead of staying all game; seekers have limited ammo (replaces the stamina idea).
- 2026-11-25: Owner review: the hider warning is a screen-edge flash, not a countdown; found hiders join the seekers; hiders get a random prop from the scenery pool with two rerolls (replacing "Become" and prop changes); everyone can jump, e.g. a bale onto a stack of bales. H0 started.
- 2026-11-25: H0 merged to main. Textured Blender props started (9.3a), one at a time with the owner approving each: the hay bale first.
- 2026-11-25: Hay bale approved. Buildings and ground textured (9.3b): barn siding, farmhouse and silo outsides, grass to the horizon, sun and real shadows with the renderer's brightening measured and corrected.
- 2026-11-25: Owner review after trying it: an always-visible movement stick on phones; landscape required (the racer's prompt, now worded per game); 100 paintballs; the barn inside split into horse stalls, a tool corner, a tractor bay and a hay corner (9.3c), with a tractor model. Hide and Seek is on the game list as solo practice.
- 2026-11-25: Roles dealt at random, no Switch (owner). Seekers = (players + 1) ÷ 3, at least 1.
- 2026-11-25: Seeker bots and multiplayer (13a), reusing the racer's room bridge. Practice now runs on game time.
- 2026-11-25: Owner report: no phone controls showed. They had been placed for an upright screen and stayed below the screen after turning; now placed every frame. Buttons named Shoot and Switch prop; decoys built (3 per hider, shared, pop when painted).
- 2026-11-25: Owner report: the stick showed but didn't respond on an iPhone in a room. Couldn't reproduce in Chrome; touch settings now match the racer (which works on that phone), mobile.js added, and mouse-only thumbs drive the stick too.
- 2026-11-25: Owner report: the stick lagged and stuttered while looking around was smooth. Cause: it rested in the bottom-left corner, where iPhone Safari delays touches while it checks for its back and home swipes. The stick now rests clear of the edges (it still floats to wherever a thumb lands on the left side), and the buttons sit higher. Phones show a diagnostic line (build, touch counts, fps) for now.
- 2026-11-25: Owner screenshot: stick "held" with no thumb down. Safari's delayed fake mouse clicks were taken as a thumb by the mouse fallback; fallback removed, touch set like Bulwark, and a new thumb always takes the stick.
- 2026-11-26: Owner: "just do the joystick from scratch". The phone stick and buttons are now drawn and handled by the page (`hideseek/web/touch.js`, the browser's own touch events), and the game reads the stick and presses each frame; touches that reach the game only look around. Godot's own stick is kept for when the page controls are missing.
