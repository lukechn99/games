# Racing game: design document

A Godot racing game for Game Night: friends in the same room race each other from
their own phones, connected peer to peer through the same rooms, video call and
relay as the other games.

This is a living document. It is the spec the code is built from, so when a
decision changes, change it here first.

**Status key**
- **Decided**: agreed; build to this.
- **Proposed**: a recommendation waiting for a yes or no.
- **Open**: needs a decision before the work that depends on it.

---

## 1. The pitch

> **Open.** Your idea, in a few sentences: what makes this race fun at a game
> night, what it feels like to play, and what you want people talking about
> afterwards.

Working title: **Open.**

## 2. Goals and non-goals

**Proposed goals**
- A race starts within a minute of opening the room, and a race lasts about 2–4 minutes.
- It feels good on a phone first: touch controls, 60 fps on a mid-range phone, quick to load.
- 2–8 players, with computer drivers to fill the grid.
- It plugs into Game Night the way the other games do: same room code, lobby, video call, reconnects and TURN relay.
- It costs nothing to run: static files on GitHub Pages, peer to peer, no game server.

**Proposed non-goals (for the first version)**
- Realistic simulation (tire temperatures, gear ratios, damage models).
- Online matchmaking with strangers, leaderboards or accounts.
- A track editor.
- Perfect fairness over bad networks. This is a party game among friends.

## 3. Players and platforms

| | |
|---|---|
| Players | 2–8 per race (**Proposed**), plus computer drivers. Extra people in the room spectate. |
| Devices | Phones first (iOS Safari, Android Chrome), then desktop browsers. |
| Orientation | Landscape on phones (**Proposed**). The game asks you to rotate if you're in portrait. |
| Session | One room hosts many races in a row. |

## 4. Stages of the game

**Proposed flow**

1. **Lobby.** The existing Game Night lobby. The host picks the racing game, and players add bots as usual.
2. **Race setup.** The host picks the track, the number of laps and the bot difficulty. Each player picks a car and a colour. The race can't start until everyone has picked.
3. **Loading.** Each phone loads the track and reports "ready". If someone takes longer than 20 seconds, the race starts without them and they join as a spectator.
4. **Countdown.** "3, 2, 1, go", in sync on every phone using the host's clock. The engine revs, but the car can't move. Optional: a launch-boost reward for pressing gas right on "go".
5. **Race.** Laps, positions, lap times and a minimap.
6. **Finish.** Players who have finished watch the others or roam freely. Once the first player finishes, everyone else has 30 seconds before the race ends (DNF, "did not finish", for anyone still out).
7. **Results.** A podium, finishing times, best lap, and maybe fun awards (most time airborne, most bumps).
8. **Next race.** The host picks "race again" (same track), "next track", or "back to lobby".

Reconnecting follows the platform rules. A player who drops mid-race gets their car back if they return before the race ends; otherwise their car is parked and they get a DNF. If the host drops, the race pauses until the host returns, as in the other games.

## 5. Core gameplay

> **Open: what kind of racer?** This choice drives most of the sections below.
> - **A. Arcade kart racer**: drifting, boosts, maybe items. Forgiving, chaotic, best for mixed skill levels.
> - **B. Arcade "real cars" racer**: grip racing with drifting, no items. Cleaner and more skill-based.
> - **C. Something else** you have in mind (top-down, stunt, demolition…).

**Proposed for any choice**
- Laps are counted through ordered checkpoints. A lap only counts if you pass every checkpoint in order, so shortcuts can't skip half the track.
- Driving off the track slows you down, it doesn't kill you. Falling off the world or ending up upside down for more than 2 seconds puts you back on the track at your last checkpoint, at reduced speed.
- Catch-up help ("rubber-banding") is optional and off by default for human players. Bots use it according to their difficulty.

**Open:** items or power-ups (yes or no, and which ones); a boost meter; jumps; stunts.

## 6. Physics

Godot runs physics 60 times a second (fixed timestep) on every phone. Each phone simulates its own car; the network section explains why.

### 6.1 Vehicle model (Proposed)

Instead of Godot's built-in `VehicleBody3D`, I'd build a **custom arcade car on a `RigidBody3D`**. It's easier to tune for "feels fun" and behaves the same on every device.

| System | How it works | What to tune |
|---|---|---|
| Suspension | 4 downward rays, each a spring and damper pushing the body up | Ride height, stiffness, damping |
| Engine and brakes | A forward force along the car, from a speed-to-force curve | Top speed, acceleration, braking distance |
| Grip | Sideways force that cancels sliding, from a simple slip curve per axle | Front and rear grip, how suddenly grip breaks away |
| Steering | Steering angle shrinks as speed grows | Turn rate at low and high speed |
| Drift | Holding drift lowers rear grip and adds a little turning help; a long drift can build boost (if 5 says yes) | Drift angle, how easy it is to keep a drift going |
| Downforce | Extra downward push that grows with speed, so cars stay planted | Strength |
| Air | Mild self-levelling in the air; optional small air steering | Self-righting strength |
| Surfaces | The track material sets grip and drag: asphalt, dirt, grass, sand, ice, boost pads | One multiplier pair per surface |
| Stability | Low centre of mass, limits on spin speed, auto-recovery when flipped | Recovery time |

All tuning numbers live in one `CarStats` resource per car, so different cars are just different numbers. For example: light and grippy, heavy and fast, or drift-happy.

### 6.2 Collisions (Proposed)
- **Walls:** solid, with glancing hits that slide along the wall instead of stopping dead. Speed lost depends on the impact angle.
- **Car to car:** each phone treats the other cars as solid shapes moving where the network says they are. A bump pushes your own car; the other player's phone handles theirs. This feels right at party-game speeds. The push is capped so nobody gets launched by a lag spike.
- **Props:** light props (cones, boxes) can be knocked around but only move on your own phone; they're decoration, not shared state.

### 6.3 What the physics doesn't need
Exact determinism across devices. Each car has one owner, and everyone else just shows that owner's version. That avoids the hardest problem in networked physics.

## 7. Tracks

> **Open:** the number of tracks for version 1 (I'd suggest 3), and the setting (see 9).

**Proposed for each track**
- About 60–90 seconds per lap, 3 laps by default (the host can choose 1–5).
- The racing line is a `Path3D`, used for bots, positions ("you're 3rd") and respawn spots.
- 8–16 checkpoints, each an invisible gate across the track.
- A starting grid with 8 spots.
- At least one shortcut or alternate route, and one "moment" (a jump, a loop, a big drop).
- A minimap drawn automatically from the path.

## 8. Camera
- **Proposed:** a chase camera behind the car on a soft spring. It widens its field of view slightly at speed and swings into turns. "Look back" works while held.
- Spectators can follow any driver, or use a slow overhead camera.
- Every camera respects reduced-motion settings: no shake and a milder field-of-view change.

## 9. Graphics style

> **Open: setting and look.** Two directions I think fit Game Night:
> - **A. Toy cars on a tabletop.** Race across a kitchen counter, a living-room floor or a backyard sandbox, with toy-sized cars and huge everyday objects. It's charming, it's different from typical racers, and it's cheap to build: a few big simple props carry each scene.
> - **B. Stylised low-poly outdoors.** Flat-shaded hills, desert canyons and coastal roads in a bright, simple palette.
> - **C.** Your own idea.

**Proposed for any style**
- Low-poly models with flat or simple toon shading, one shared colour-palette texture, and no detailed texture maps. That keeps files small and phones fast.
- Godot's **Compatibility** renderer, the same one Bulwark uses and the one that works on the most phones.
- Lighting baked into the scene, with soft "blob" shadows under cars instead of real-time shadows.
- Car colours that colour-blind players can tell apart, plus a number on each car.
- Speed effects: wheel dust, drift smoke, speed lines and a boost glow. Keep them cheap.

## 10. Controls

**Proposed**

| Device | Steer | Gas | Brake / reverse | Drift | Other |
|---|---|---|---|---|---|
| Phone (default) | Left and right buttons, bottom left | Automatic, with an option to hold a button | Button, bottom right | Button, bottom right | Respawn, look back |
| Phone (optional) | Tilt the phone (iOS asks for motion permission) | Same as above | | | |
| Keyboard | A/D or arrow keys | W or Up | S or Down | Space | R respawn, C look back |
| Gamepad | Left stick | Right trigger | Left trigger | A / Cross | Y respawn |

Assists, which can be switched off in settings: automatic gas (on for phones), steering help that eases you toward the racing line at low level, and auto-recovery after a crash.

## 11. Audio
- Engine sound with pitch tied to speed, plus tyre screech while sliding, bump sounds, boost, countdown beeps and a finish fanfare.
- Music: **Open** (none, one looping track, or one per track).
- Everything is quieter while the video call is on, so you can still hear your friends.

## 12. Networking

### 12.1 Fitting into Game Night (Proposed)
The racing game stays a normal Game Night game. The Next.js site still owns the room: lobby, joining, reconnects, video call and the TURN relay. The Godot game runs **inside the game screen** and borrows the site's connections through a small message bridge. That way, everything we've already built, including the bot check and relay, works for the racing game for free.

```
Next.js game screen ──postMessage──► Godot (iframe)
  room, players, seat, host clock      race simulation, rendering, input
  PeerJS connections  ◄──postMessage── "send this to the host / to everyone"
```

There are two lanes of traffic:
- **Race rules lane (reliable):** a normal room-engine game module, `racing`, run by the host. It holds the race setup, the countdown start time, checkpoint progress, lap times, finishing order and results. It works like the other games, so spectating, reconnecting and pausing when the host leaves all work unchanged.
- **Car lane (fast, may drop packets):** each phone sends its own car's position, rotation, speed and inputs 20 times a second, over a second PeerJS connection set to drop late packets rather than retry them. A late car position is worthless anyway.

### 12.2 Showing other cars (Proposed)
- Other cars are drawn about **100 ms in the past**, smoothly blended between the updates received.
- If an update is missing, the car keeps moving forward based on its last speed, for up to 250 ms. After that it eases toward the next real update instead of jumping.
- Your own car always responds instantly. There's never any waiting on the network for your own driving.

### 12.3 Topology (Proposed)
Start with a **star**, as the other games do: phones send their car to the host, and the host passes it on to everyone. Eight cars at 20 updates a second is about 25 KB/s per phone, which is easy. If the extra trip through the host feels laggy, switch the car lane to a **mesh**, where every phone sends directly to every other phone. With 8 players that's 7 connections each, which is fine for small messages.

### 12.4 Keeping it fair-ish (Proposed)
The host checks race progress, not physics. Checkpoints have to be passed in order, a lap can't be faster than a minimum time for that track, and the finish time comes from the host's clock. A determined cheater could still drive faster than possible on their own phone. Among friends, that's acceptable.

### 12.5 Computer drivers
**Proposed:** bots drive on the host's phone and send their cars out like any player. They follow the racing line, looking ahead and braking for corners based on how sharp they are. Difficulty sets their top speed, how early they brake, how often they make mistakes, and how much catch-up help they get.

## 13. Building and shipping

**Proposed**
- Godot **4.4.1**, as Bulwark uses, with GDScript, the Compatibility renderer and the web export **without threads**. GitHub Pages can't send the special headers that threaded exports need.
- The Godot project lives in `racing/` in this repo. The deploy workflow downloads Godot, exports the game to `public/racing/`, then builds the site as now. This mirrors Bulwark's workflow.
- **Download size target:** under 15 MB compressed on first load, cached after that. The standard Godot web engine is most of that, and a slimmed-down custom engine build can cut it later.
- **Performance target:** 60 fps on a mid-range phone from the last 3–4 years. That means at most about 150 draw calls and 100k triangles on screen.

## 14. Accessibility
- Colour-blind-safe car colours with numbers.
- Automatic gas and steering assist.
- A reduced-motion mode: no camera shake and fewer speed effects.
- Buttons sized for thumbs, and a left-handed control layout.
- Captions for important sounds ("Final lap!").

## 15. Milestones (Proposed)

| | Milestone | Done when |
|---|---|---|
| M0 | Car feel | One car on a test track feels fun with keyboard and touch. |
| M1 | One full track | Laps, checkpoints, respawn, a HUD and a single-player race against one bot. |
| M2 | Inside Game Night | The web export runs in the game screen, the bridge works, and it builds in CI. |
| M3 | Two players | Two phones race, with smooth remote cars, a synced countdown and results. |
| M4 | Full grid | 8 players plus bots, reconnecting, spectators, and racing again. |
| M5 | Content and polish | All version-1 tracks, cars, audio and effects; performance hits the targets. |

## 16. Open questions
1. The pitch and working title (1).
2. The kind of racer: kart, arcade cars, or something else (5).
3. Items or power-ups, and boost (5).
4. The setting and graphics style (9).
5. The number of tracks and cars for version 1 (7).
6. Music (11).
7. The player limit: is 8 right (3)?
8. Phones in landscape only, or portrait too (3)?

## 17. Decision log

| Date | Decision | Why |
|---|---|---|
| 2026-11-06 | Build in Godot, embedded in the Game Night site | The user's request; reuses rooms, the call and the relay |
