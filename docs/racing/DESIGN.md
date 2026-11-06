# Kart racer: design document

A cartoon kart racer for Game Night, built in Godot. Friends in the same room build
their own karts, pick an animal driver, and race each other from their phones,
connected peer to peer through the same rooms, video call and relay as the other
games.

This is a living document. It is the spec the code is built from, so when a
decision changes, change it here first.

**Status key**
- **Decided**: agreed; build to this.
- **Proposed**: a recommendation waiting for a yes or no.
- **Open**: needs a decision before the work that depends on it.

---

## 1. The pitch

**Decided.** A Mario Kart–style party kart racer with its own identity:

- **Build your kart** before every race. The chassis, wheels and driver all change how it drives.
- **Animal drivers** in a bright cartoon style.
- **Tracks across different terrains**, each with its own obstacles and surfaces.
- **Original items** to collect and use. We design these ourselves, so they're not copies of Mario Kart's.
- **It feels dynamic:** screen shake on crashes, big hits and bumpy landings.
- **Steer by tilting your phone** like a steering wheel, or with on-screen buttons, a keyboard or a gamepad. Players choose.

Working title: **Open.** (Ideas: *Critter Kart*, *Paw Prix*, *Wild Wheels*.)

## 2. Goals and non-goals

**Proposed goals**
- From opening the room to the first race in under two minutes, kart building included. A race lasts about 2–4 minutes.
- Phone first: touch or tilt controls, 60 fps on a mid-range phone, quick to load.
- Computer drivers fill the grid, so a race is fun with only two people.
- It plugs into Game Night like the other games: same room code, lobby, video call, reconnects and relay.
- **Open for more:** tracks, kart parts, drivers and items are data plus scenes. Adding one is new content, not new engine code.
- It costs nothing to run: static files on GitHub Pages, peer to peer, no game server.

**Proposed non-goals (for the first version)**
- Realistic simulation (tire temperatures, gears, damage models).
- Online play with strangers, leaderboards or accounts.
- A track editor.
- Perfect fairness on bad networks. It's a party game among friends.

## 3. Players and platforms

| | |
|---|---|
| Karts per race | **Proposed:** up to 8 people plus bots, 8 karts total. Possibly 12 later; see 13.3. |
| Devices | Phones first (iOS Safari, Android Chrome), then desktop browsers. |
| Orientation | Landscape while racing (**Proposed**). Portrait is fine in the kart builder. |
| Session | One room plays many races in a row (a "cup"). |

## 4. Stages of the game

**Proposed flow**

1. **Lobby.** The existing Game Night lobby. The host picks the kart racer and adds bots as usual.
2. **Track vote.** Everyone votes from the available tracks. The host can override, or choose "random".
3. **Kart builder** (section 5). Players pick a driver, chassis, wheels and colour, with a live stats panel and a 3D preview that spins. The build is saved on your phone for next time. A 45-second timer keeps it moving; anyone who runs out of time keeps their last build.
4. **Loading.** Every phone loads the track and reports "ready". Anyone still loading after 20 seconds becomes a spectator for this race.
5. **Countdown.** "3, 2, 1, go", in sync across phones using the host's clock. Pressing gas right at "go" gives a small launch boost.
6. **Race.** Laps, positions, a minimap, items, and screen shake on crashes.
7. **Finish.** Players who finish watch the others. After the first player finishes, the rest have 30 seconds before the race ends (DNF, "did not finish", for anyone still out).
8. **Results.** A podium, times and best lap, plus fun awards like "most items landed", "most airtime" and "biggest crash".
9. **Next.** Back to the track vote, with builds kept. You can tweak your kart, "race again", or go "back to lobby". A cup is **Open**: 3–4 races with points carried over.

Reconnecting follows the platform rules. A player who drops mid-race gets their kart back if they return before the race ends; otherwise their kart is parked and they get a DNF. If the host drops, the race pauses until the host returns, as in the other games.

## 5. Kart builder

**Decided:** a build-your-kart stage before racing. The chassis sets turning and the hit box; the wheels and tires set handling and grip on each surface.
**Proposed:** the driver adds weight, and there's an optional third part (below).

### 5.1 Stats (Proposed)
Everything comes down to a few stats, each shown as 1–10 bars in the builder:

| Stat | What it does |
|---|---|
| Top speed | Maximum speed on a good surface |
| Acceleration | How quickly you reach top speed, and recover after a hit |
| Weight | Who gets pushed around in a bump; heavy karts lose less speed when hit |
| Turning | Turn radius and how quickly the kart changes direction |
| Grip | How much sideways force before sliding, per surface (see 5.3) |
| Drift | How easy drifts are to start and hold, and how fast they charge boost |

The stats map onto the physics tuning in section 7, so the builder and the physics share one set of numbers.

### 5.2 Chassis (Decided: affects turn radius and hit box)
Each chassis sets **turning**, its **hit box** size and shape, and some **weight**. A small hit box is harder to hit with items and slips through gaps; a big one shoves others around in bumps.

**Proposed starting set (4)**

| Chassis | Feel | Turning | Hit box | Weight |
|---|---|---|---|---|
| Go-kart frame | Classic, all-round | Medium | Medium | Medium |
| Soapbox | Tiny and twitchy | Tight | Small | Light |
| Hauler | A truck of a kart, hard to push around | Wide | Large | Heavy |
| Racer | Long and low, fast but takes the long way round | Wide-ish | Long and narrow | Medium |

### 5.3 Wheels and tires (Decided: affect handling and friction on the road)
Tires set **grip, handling and drift**, and how much grip they keep **on each surface**. This is where track choice matters: pick tires for the terrain.

**Proposed starting set (4)**

| Tires | Asphalt | Dirt and grass | Sand and mud | Ice and snow | Notes |
|---|---|---|---|---|---|
| Slicks | Excellent | Poor | Poor | Poor | Best on clean tracks |
| Knobby off-road | Fine | Excellent | Good | Fine | Bumpier ride, slower top speed |
| Balloon | Fine | Good | Excellent | Fine | Bouncy; lands jumps softly |
| Studded | Fine | Fine | Poor | Excellent | Built for ice and snow |

### 5.4 Drivers: animals (Decided: animal characters)
**Proposed:** drivers are mostly about looks and personality, with a light weight class (small, medium or large) so your choice matters a little. A roster with clear, different silhouettes (**Open**, pick or replace):

| Small | Medium | Large |
|---|---|---|
| Frog, red panda, hedgehog | Corgi, otter, raccoon | Capybara, bear |

Each driver gets a few short animations: idle, steering lean, getting hit, celebrating and a "tilt" taunt.

### 5.5 A third part? (Open)
A **motor**, trading top speed against acceleration, would round out the builder. It's optional; the builder works with just chassis and wheels.

### 5.6 Keeping it fair (Proposed)
Every part is a trade-off, so no build is best everywhere. All builds should finish within about 5% of each other on a lap when driven well. Bots use preset balanced builds.

## 6. Items

**Decided:** items you collect on the track, designed by us so they aren't copies of Mario Kart.
**Proposed rules:** item crates sit in rows across the track and reappear 3 seconds after being picked up. You hold one item at a time. What you get depends on your position: karts near the back get more catch-up items.

**Candidate items to choose from (Open: pick about 8 for launch)**
Each fills a role every kart racer needs, with our own twist:

| Role | Item idea | What it does |
|---|---|---|
| Trap behind you | **Honey puddle** | A sticky patch: karts that drive through it slow down and steer sluggishly for 2 seconds |
| Trap behind you | **Tumbleweed** | Rolls back down the track, bouncing unpredictably |
| Forward shot | **Acorn volley** | Three bouncing acorns fired ahead. Each that hits makes a kart wobble |
| Forward shot | **Snowball** | Grows as it rolls forward. A bigger snowball means a bigger hit |
| Seeks someone | **Bee swarm** | Chases the kart directly ahead of you, and can be shaken off by drifting |
| Self boost | **Tailwind** | A strong gust behind you: a boost that also pushes nearby karts aside |
| Defense | **Bubble** | Absorbs one hit, then pops |
| Escape | **Burrow** | Dig underground for 3 seconds: you can't be hit and pass under obstacles, but you can't steer much |
| Chaos | **Party dice** | A game-night item: roll for a random effect, good or bad |
| Catch-up | **Slipstream rope** | Latches onto the kart ahead and slingshots you past it |
| Field effect | **Fog horn** | Blows fog over the screens of everyone ahead of you for a few seconds (lighter fog for those further ahead) |

## 7. Physics

Godot runs physics 60 times a second (fixed timestep) on every phone. Each phone simulates **its own kart**; section 13 explains why.

### 7.1 Kart model (Proposed)
A **custom arcade kart on a `RigidBody3D`**, not Godot's `VehicleBody3D`. It's easier to tune for fun, and it behaves the same on every device. Every number comes from the kart's build (section 5).

| System | How it works | Set by |
|---|---|---|
| Suspension | 4 downward rays, each a spring and damper holding the body up | Chassis (balloon tires add bounce) |
| Engine and brakes | Forward force from a speed-to-force curve | Top speed and acceleration (motor if 5.5) |
| Grip | Sideways force that cancels sliding, per axle, from a simple slip curve, multiplied by the surface | Tires (by surface) |
| Turning | Turn radius from the chassis, which widens a little at speed | Chassis |
| Drift | Hop into a drift; rear grip drops and turning tightens. Holding it charges a 3-stage boost | Tires and drift stat |
| Weight | Mass, which decides who gets pushed in bumps and how much speed you lose when hit | Chassis plus driver |
| Hit box | A simple box or capsule for bumps and item hits, sized per chassis | Chassis |
| Downforce | Extra downward push at speed, so karts stay planted | Shared |
| Air | Mild self-levelling in the air; balloon tires soften landings | Shared and tires |
| Surfaces | Each patch of track has a type: asphalt, dirt, grass, sand, mud, ice, snow, boost pad or rough. It scales grip and drag | Track |
| Recovery | Off the world, upside down for 2 seconds, or stuck for 3: respawn on the track at the last checkpoint | Shared |

### 7.2 Collisions and crashes (Proposed)
- **Walls:** glancing hits slide along; head-on hits stop you and bounce you back a little. Speed lost depends on the angle.
- **Kart to kart:** your phone treats the other karts as solid shapes moving where the network says they are. A bump pushes your own kart according to the two weights, and their phone does the same for theirs. The push is capped so a lag spike can't launch anyone.
- **Item hits:** the phone of the kart that gets hit decides whether it was hit (13.4), then plays the spin-out or wobble.
- **Obstacles:** solid ones (rocks, logs) act like walls; moving ones (rolling barrels, swinging gates) follow a timed pattern, so every phone sees them in the same place.

### 7.3 Screen shake and feel (Decided: shake on crashes)
**Proposed:** a "trauma" value from 0 to 1 that crashes add to. Shake strength is trauma squared, so small bumps barely shake and big crashes really do. Trauma fades over about half a second.

| Event | Trauma added |
|---|---|
| Light bump with a kart | 0.15 |
| Wall hit | 0.2–0.6, by impact speed |
| Hit by an item | 0.5 |
| Hard landing after a jump | 0.3 |
| Big explosion or chaos item | 0.7 |

Also on crashes: a short camera field-of-view punch, sparks and dust, and a vibration on Android phones (iPhone browsers don't allow vibration). A **reduced shake** setting has three levels: full, gentle and off. It follows the phone's reduced-motion setting by default.

### 7.4 What the physics doesn't need
Exact determinism across devices. Each kart has one owner, and everyone else shows that owner's version, which avoids the hardest problem in networked physics.

## 8. Tracks

**Decided:** different terrains and obstacles, launching with one or two tracks and built so more can be added.

### 8.1 How a track is built (Proposed)
Each track is one Godot scene plus a `TrackInfo` resource:
- A **racing line** (`Path3D`), used for bots, positions, respawns and the minimap.
- **Checkpoints**: 8–16 invisible gates. A lap counts only when you pass them all in order.
- **Surface areas**, painted on the track so the physics knows what you're driving on.
- **Obstacles**, made from reusable pieces (rolling, swinging, sliding, popping up, static).
- **Item crate rows**, boost pads, jumps and at least one shortcut.
- A **starting grid** of 8 spots, plus lap count defaults.

Adding a track means building the scene and adding one entry to the track list. No code changes.

### 8.2 Candidate tracks (Open: pick 1–2 for launch, then we design each one together)

| Track idea | Terrain | Obstacles and gimmicks | Good tires |
|---|---|---|---|
| **Meadow Loop** | Asphalt and grass | Gentle hills, a farm gate, a beginner-friendly layout | Slicks |
| **Canyon Run** | Dirt and sand | Jumps over gaps, rolling tumbleweeds, a dusty shortcut | Knobby or balloon |
| **Frosty Pass** | Snow and ice | Icy hairpins, sliding snowballs, a frozen lake shortcut | Studded |
| **Bayou Boardwalk** | Mud and wooden planks | Swinging lanterns, mud pits, logs rolling across | Balloon |
| **Kitchen Counter** | Countertop, a tablecloth | Toy-scale race past rolling fruit and a spinning lazy Susan | Any |

**Proposed for launch:** Meadow Loop, to learn the basics, plus one terrain that rewards picking different tires, such as Canyon Run or Frosty Pass.

## 9. Characters and art style

**Decided:** a cartoonish, Mario Kart–like style with animal characters.
**Proposed, to keep phones fast:**
- **Look:** chunky, rounded, toy-like shapes; bright saturated colours; simple **toon shading** (2–3 flat bands of light) in Godot's Compatibility renderer.
- **Outlines** only on karts and drivers, the things you care about. They cost extra triangles, so they come with a low-quality setting to turn them off.
- **Materials:** one shared colour-palette texture for everything, with no detailed texture maps. That makes downloads small and drawing fast.
- **Lighting:** baked into the track, with soft "blob" shadows under karts instead of real-time shadows.
- **Kart assembly:** at race start, each kart's chassis, wheels and driver are merged into as few meshes as possible. Eight karts cost about 16 draw calls, not 80.
- **Level of detail:** karts further away switch to simpler versions; distant scenery is plain silhouettes.
- **Budget per kart:** about 3,000 triangles (kart plus driver), and 100,000 on screen in total, at most around 150 draw calls.
- **Quality settings:** automatic based on frame rate, plus a manual high, medium or low (outlines, effects, draw distance, resolution).

**Open: where do the 3D models come from?**
- **A. Free (CC0) packs as a base.** Quaternius makes low-poly animated animals and Kenney makes kart and racing kits. Both are free for any use, and we'd restyle them to match.
- **B. Built to order:** I model in Blender with scripts, using simple rounded shapes. Very consistent, but slower to make.
- **C. A mix:** packs for scenery, custom models for karts and drivers.

## 10. Controls

**Decided:** tilt-to-steer is investigated, and players can always choose their control method.

### 10.1 Tilt steering: feasible (Proposed design)
- **How it works:** hold the phone sideways like a steering wheel and turn it. The game measures which way gravity points across the screen. Turning the "wheel" changes that angle.
- **Godot can't read phone sensors in a web build.** The Game Night page reads the motion sensor with JavaScript and passes the angle to the game through the bridge (13.1), roughly 60 times a second.
- **iPhone permission:** iOS only allows motion sensors after the player taps a button and approves a prompt. So the kart builder has a **"Steer by tilting"** button that asks, on the main page rather than inside the game, which is the most reliable place on iOS. Android doesn't ask.
- **Calibration:** the wheel's centre is set when the countdown starts, and there's a "re-centre" button.
- **Feel:** a small dead zone (about 3°), full lock at about 30° (adjustable), light smoothing, and a choice between gentle and direct response.
- **Fallback:** if permission is refused or there's no sensor, the game switches to touch buttons and says so.

### 10.2 Control schemes (players choose in the builder or in settings)

| Scheme | Steer | Gas | Brake / reverse | Drift | Item |
|---|---|---|---|---|---|
| Tilt (phone) | Tilt | Automatic, or hold the right side of the screen | Bottom-left button | Bottom-right button | Big button on the right |
| Touch buttons (phone) | Left and right buttons | Automatic or button | Button | Button | Button |
| Touch slider (phone) | Drag a thumb left and right | Automatic or button | Button | Button | Button |
| Keyboard | A/D or arrow keys | W or Up | S or Down | Shift or Space | E or Enter |
| Gamepad | Left stick | Right trigger | Left trigger | Right bumper | A / Cross |

Assists, which players can turn off: automatic gas, steering help that keeps you off the walls, and auto-drift for younger players.

## 11. Audio
- Engine sound with pitch tied to speed (different per chassis), tyre screech while sliding, bumps, item sounds, countdown beeps, a finish fanfare and animal voices (a happy chirp or grunt).
- Music: **Open** (one looping track per course is the usual choice).
- Everything ducks under the video call, so you can still hear your friends.

## 12. Bots (computer drivers)
**Proposed:** bots drive on the host's phone and send their karts out like players do. They follow the racing line, looking ahead and braking for corners by how sharp they are. They pick items and use them with simple rules: drop traps when someone's close behind, fire when lined up with a kart ahead. Difficulty sets their speed, how early they brake, their mistakes, how smart they are with items, and a little catch-up help.

## 13. Networking

**Open, to decide together: a single host or a mesh, and how many players.** The analysis is below; my recommendation is in 13.3.

### 13.1 Fitting into Game Night (Proposed)
The Next.js site keeps owning the room: lobby, joining, reconnects, video call and the relay (including the bot check). The Godot game runs **inside the game screen** and uses the site's connections through a small message bridge, which also carries the tilt sensor and the host clock.

```
Next.js game screen ──postMessage──► Godot (iframe)
  room, players, host clock, tilt      race simulation, rendering, input
  PeerJS connections  ◄──postMessage── "send this to the host / to everyone"
```

There are two lanes of traffic:
- **Race rules lane (reliable):** a normal room-engine game module, run by the host. It holds the track vote, builds, the countdown start time, checkpoint progress, lap times, finishing order and results. Spectating, reconnecting and pausing when the host leaves all work as in the other games.
- **Kart lane (fast, may drop packets):** each phone sends its own kart's position, rotation, speed, inputs and item state about 20 times a second. A late update is worthless, so this lane drops it rather than retrying.

### 13.2 Star vs mesh: what it costs

Assumptions: one kart update is about 40 bytes, plus about 70 bytes of packet overhead, 20 times a second. A host in a star batches every kart into one update per player.

**Star (everyone goes through the host, as the games do today)**

| Karts | Each player sends | Each player receives | Host sends | Host connections |
|---|---|---|---|---|
| 4 | 2 KB/s | 4 KB/s | 11 KB/s | 3 |
| 8 | 2 KB/s | 7 KB/s | 49 KB/s | 7 |
| 12 | 2 KB/s | 10 KB/s | 112 KB/s | 11 |
| 16 | 2 KB/s | 13 KB/s | 201 KB/s (≈1.6 Mbps) | 15 |

**Mesh (every phone sends its kart to every other phone, as the video call does)**

| Karts | Each phone sends and receives | Connections per phone | Total connections |
|---|---|---|---|
| 4 | 7 KB/s | 3 | 6 |
| 8 | 15 KB/s | 7 | 28 |
| 12 | 24 KB/s | 11 | 66 |
| 16 | 33 KB/s | 15 | 120 |

**What the numbers say**
- **Bandwidth isn't the limit either way.** Even 16 karts in a star is under 2 Mbps of upload from the host, which any Wi-Fi or decent cellular connection handles.
- **Delay:** in a star, your kart reaches another phone in two hops (you, then the host, then them). In a mesh it's one hop. On the same Wi-Fi that's maybe 10–30 ms either way; through the relay or on cellular, the star could add 50–100 ms. Delay matters for racing far more than bandwidth, because it's how far behind where others really are you see them.
- **Connections:** a mesh needs every pair of phones to connect, and every extra connection is another chance a pair can't connect and needs the relay. A star has the fewest connections.
- **The real limits:** phone processor and drawing power (drawing 12–16 animated karts), track width and fun. Mario Kart itself tops out at 12.

### 13.3 Recommendation (Proposed)
- **A hybrid.** The race rules always go through the host, as a star. The kart lane uses a **mesh** for the lower delay. Any pair of phones that can't connect directly falls back to sending through the host, so nobody is left out.
- **Start with 8 karts** (people plus bots). Test 12 once everything works; the networking can handle it, so phone performance will decide.
- Bots run on the host and are sent out by the host; that's 4 bots × 7 players, still tiny.

### 13.4 Showing other karts and item hits (Proposed)
- Other karts are drawn about **100 ms in the past**, smoothly blended between updates. If an update goes missing, the kart keeps moving along its last speed for up to 250 ms, then eases back into place.
- **Your own kart always responds instantly**, never waiting on the network.
- **Items:** using an item sends a reliable "spawned" message (what, where, when, which direction). Every phone simulates the item from that. **The phone of the kart that gets hit decides whether it was hit**, then tells everyone. So you never get hit by something that clearly missed on your own screen.
- **Fair-ish:** the host checks checkpoints in order and a minimum lap time, and finish times come from the host's clock. A determined cheater could still drive faster than possible on their own phone. Among friends, that's acceptable.

## 14. Building and shipping
**Proposed**
- Godot **4.4.1**, as Bulwark uses, with GDScript, the Compatibility renderer and the web export **without threads**. GitHub Pages can't send the headers threaded exports need.
- The Godot project lives in `racing/` in this repo, with this document in `docs/racing/`. The deploy workflow exports the game to `public/racing/` and then builds the site, skipping the export when nothing in `racing/` has changed.
- **Download target:** under 15 MB compressed on first load, then cached.
- **Performance target:** 60 fps on a mid-range phone from the last 3–4 years (see the budgets in 9).

## 15. Accessibility
- Colour-blind-safe kart colours, plus a number on each kart.
- Assists: automatic gas, steering help and auto-drift.
- Screen shake levels (full, gentle, off) and a reduced-motion mode.
- Buttons sized for thumbs, a left-handed layout, and adjustable tilt sensitivity.
- Captions for important sounds ("Final lap!", "Bees incoming!").

## 16. Milestones (Proposed)

| | Milestone | Done when |
|---|---|---|
| M0 | Kart feel | One kart on a test track feels fun with keyboard, touch and tilt; chassis and tires noticeably change handling. |
| M1 | First track | Meadow Loop with laps, checkpoints, respawn, HUD and screen shake; a race against bots. |
| M2 | Kart builder | Drivers, chassis, tires and stats, with the build saved on your phone. |
| M3 | Inside Game Night | The web export runs in the game screen, the bridge and tilt steering work, and it builds in CI. |
| M4 | Multiplayer | 2–8 karts with smooth remote karts, a synced countdown, results, reconnecting and spectators. |
| M5 | Items | The launch set of items, synced across phones. |
| M6 | Second track and polish | The second terrain, audio, effects and performance tuning. |

## 17. Open questions
1. Working title (1).
2. A third kart part, the motor (5.5)?
3. The animal roster and weight classes (5.4).
4. Which ~8 items for launch (6).
5. The launch tracks: 1–2 from the candidate list (8.2).
6. Where the 3D models come from (9).
7. Star, mesh or hybrid, and the kart limit (13); recommended: hybrid with 8 karts.
8. Cups and points across races (4).
9. Music (11).

## 18. Decision log

| Date | Decision | Why |
|---|---|---|
| 2026-11-06 | Build in Godot, embedded in the Game Night site | The user's request; reuses rooms, the call and the relay |
| 2026-11-06 | Mario Kart–style kart racer with a kart builder (chassis, wheels and tires) | The user's request |
| 2026-11-06 | Chassis sets turn radius and hit box; tires set handling and grip per surface | The user's request |
| 2026-11-06 | Multiple terrains with obstacles; launch with 1–2 tracks, add more as content | The user's request |
| 2026-11-06 | Original items, designed together | The user's request; not copies of Mario Kart |
| 2026-11-06 | Screen shake on crashes | The user's request; reduced-shake settings for comfort |
| 2026-11-06 | Tilt-to-steer, with players free to choose their controls | The user's request; tilt is read by the page and passed to Godot |
| 2026-11-06 | Cartoon art style with animal drivers, tuned for phone performance | The user's request |
