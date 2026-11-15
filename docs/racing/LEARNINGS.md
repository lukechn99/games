# Karts: lessons learned

What building and tuning the kart racer has taught us, as rules to follow
next time. Each lesson says what happened, then the rule. Newest findings
are marked with their date. The design itself is in `DESIGN.md`; this file
is about how to work on it without wasting time.

## Measuring performance

**Software rendering says nothing about frame rate.** The build machine has
no graphics card, so it draws in software at about 8 frames a second. Its
draw calls, triangles, objects and physics time are trustworthy; its frame
rate and frame times are not. Real frame rates only come from real devices.

**Averages hide freezes.** Loading the Blender item models the first time an
item appeared froze the game for a moment. The average physics time went
from 3 to 10 ms, which looked like a steady cost, and took six benchmark runs
to trace. *Rule:* load models while the race loads, never on first use; and
measure the longest single frame (verify reports any step over 50 ms).

**Compare against the same machine on the same day.** The cloud machine can
be replaced between sessions and run at a different speed. A "regression"
measured against an old baseline was once just a slower machine. *Rule:*
when a number moves, re-measure the previous version on the same machine
before hunting (`git stash`, bench, `git stash pop`).

**A baseline nobody can match is no baseline.** The bench was reworked with
new run names, so every comparison quietly skipped; and it would only save a
baseline when every run finished, which High never does in software. *Rule:*
when a check says "skipped" or "no baseline", treat it as broken, not as a
pass. Budgets with fixed limits (verify) don't have this problem.

**Count what's drawn at fixed spots, not during a race.** A race's numbers
shift when drivers take a different line or an item lands somewhere else.
Fixed viewpoints with the race frozen measure the same thing every run.

## Testing on phones

**One run per setting proves nothing.** (2026-11-14) On an iPhone 15 Pro,
Medium on Meadow gave either about 60 fps (0.2% of frames late) or about
51 fps (6 to 14% late), with nothing in between, across twelve runs and
every setting tried. We first blamed glow, then the tunnel lamps, each from
a single good run; both were wrong. *Rule:* compare settings inside one race
(`?autodrive&benchmedium`, `?autodrive&benchqualities`), so every setting
sees the same warm-up and background state, or alternate A, B, A, B, A, B.

**A 60 or 51 split means the frame is right at the deadline.** At 60 Hz each
frame has 16.7 ms. When the work takes about that long, small differences
(warmth, what's on screen, the browser) decide whether frames fit; those that
miss wait for the next refresh, so the average drops to about 51, not 58.
*Rule:* there may be no single culprit; the target is headroom (about 20%
under the deadline), found by removing work until runs are consistently 60.

**Make the phone report what it ran.** A result was once mistaken for the
new version while the phone may have run the old one. *Rule:* every result
line says the build (`build=`, stamped by the deploy workflow), the effects
actually in use (`glow=`, `lights=`, `aa=`), the screen size, the 3D scale
and the route. A screenshot of numbers costs far more to read than a line of
text: phones use the Copy result button.

**Warming up looks like a slow setting.** (2026-11-14) In one Medium
comparison race every setting ran about 60 fps for the first minute, then
all of them slowed (45.8, 47.4, 40.4) in the order they ran, not by
setting. *Rule:* read a comparison in time order first; flat draw calls and
objects with a falling frame rate mean the phone is warming up, rising ones
mean something builds up during the race.

**Phone checklist:** landscape, off the charger, not in Low Power Mode,
nothing else open, runs back to back. Discard any line marked INVALID.

## What things cost (this renderer)

The web build uses Godot's Compatibility renderer (WebGL 2).

- **Separate meshes are separate draw calls.** Blender wheels were scaled to
  each tyre's width, and stretched parts were left out of the kart merge, so
  each wheel stayed about ten draws: half of all draw calls in a race.
  Merging halved them. *Rule:* merge per kart, per prop kind, per material.
- **One mesh for many copies.** All sand piles share one MultiMesh (one draw
  call); the old tumbleweed was six rings, six draws, now one.
- **Each real light draws what it touches again.** The tunnel and cave had
  real lights at every quality although the design said High only. *Rule:*
  real lights on High only; elsewhere, surfaces that glow by themselves.
  Verify fails if any real light is on below High.
- **Merged meshes lose automatic far-away detail.** Godot makes simpler
  versions of imported models for distance, but not of meshes we build, so
  merged wheels drew full detail at any range. Generate them, or accept it.
- **What's left of a phone frame (Medium, iPhone 15 Pro, Meadow):** about
  340 draw calls, 200k triangles, under 2 ms physics, 8 to 10 ms of script.
  Low runs at 60; the extra work of Medium is pixels and effects.

## Building tracks (Series 2)

- **A model's file name can overwrite another's.** (2026-11-14) A Ferris
  wheel prop named `wheel` replaced the karts' wheel model: karts drove on
  Ferris wheels, every test passed, and verify showed it as a triangle drop
  and changed grid pictures. *Rule:* the Blender builder refuses reserved
  names (`RESERVED` in `tools/blender/props.py`); add to it when the game
  gains a model built elsewhere.
- **A thin wall is not a wall.** A kart at speed crossed a single-sheet
  barrier between two physics steps and fell out of Windy City. *Rule:* kit
  walls are two collision sheets 0.8 m apart (`KitTools.rooms`); anything
  new a kart can hit at speed needs thickness.
- **Coins and item boxes were a third of the draw calls.** At Windy City's
  grid they were 80 and 48 of 254 draws, one per coin and per box part.
  They are now batched by area (`Items.Batch`). *Rule:* when a view is over
  budget, read verify's "draws most from" line before guessing.
- **A jump that must always land is not left to physics.** Launch gaps fly
  every kart along one planned arc, whatever speed it arrives at, and only
  the model somersaults. Hazards that need timing (jets, barriers, sweepers)
  read the shared race clock, so every player sees the same gap.
- **Research the place before dressing it.** (2026-11-15) The first Series
  2 tracks were judged to lack detail. Asking "what is really in a starship,
  under Chicago, at a funfair, and what does each let a kart do?" gave both
  the scenery and the set pieces (loading docks and steam vents, a
  drawbridge to jump, a garden deck). Generic props did not.
- **A boost ramp on a road with no walls throws computer drivers off.** One
  on Starliner's hull walk cost a reset a race. *Rule:* ramps go where
  there are walls or wide ground; open stretches get boost strips.
- **One model drawn everywhere is drawn everywhere.** A MultiMesh is one
  object: if any copy is in view, every copy is drawn and counted. Props
  spread over a track go through `KitDress.scatter`, which splits them into
  squares so only the near ones draw; crowds are split ahead of and behind
  the grid for the same reason.
- **A test can't read a MultiMesh back without a renderer.** Headless Godot
  stores nothing in it. Test the code that computes the transforms
  (`Mover.where`), not the MultiMesh.
- **Don't build models while verify runs.** A Blender build alongside a
  verify made one viewpoint tour time out. One heavy job at a time, and no
  edits to game files during a verify.

## Godot and the export

- **New `class_name` scripts need an import.** A pull that adds classes fails
  with "Identifier not declared" until `godot --headless --import` runs.
  `check.sh` now does this when needed.
- **Godot packs everything it imports.** It imported the verify pictures in
  `racing/tools/` and shipped them in the game (index.pck 16 MB, now 8.7).
  *Rule:* folders the game doesn't use get a `.gdignore`.
- **Scripts run with `-s` don't load autoloads.** Loading `main.tscn` from a
  test script hangs waiting for the online service. Test scripts build the
  pieces they need (see `tests/race_report.gd`), and every test step has a
  time limit.
- **Faces point one way.** A mesh built by hand looked fine in Blender's
  preview (which draws both sides) and was invisible in the game. Builders
  check which way faces point.
- **Things built after a setting is applied miss it.** Tunnel lamps were
  made after the quality was set, so they ignored it. *Rule:* things built
  later read the setting when they're created (`Palette.lamps`).
- **Lambdas copy plain numbers.** A counter incremented inside a signal
  handler stayed 0. Keep counters in a dictionary or array.
- **Shared random generators are shared state.** Using the item system's
  generator to turn honey puddles changed which items came out of boxes, and
  every game in an online race must draw the same sequence. *Rule:* visual
  variety comes from position, never from a shared generator.

## Working on it

- **Verify before reporting.** `node racing/tools/verify/verify.mjs` checks
  the tracks a change touches: tests, a fast race (resets, stalls, routes,
  freezes), draw calls and triangles at fixed viewpoints against budgets,
  pictures against approved ones, download size. About 2 to 8 minutes, a
  dozen lines, and one image only if a picture changed.
- **Look at one sheet, not many screenshots.** `tools/bench/sheet.mjs` puts
  several views in one small image. Picking frames from a filmed race by
  colour didn't work (items are behind the kart, or out of view); fixed
  viewpoints and test views (`?showroom&items`, `?drop=`, `?give=`) do.
- **The picture check catches what tests don't.** Adding kit colours to the
  shared road builder landed two lines inside Mining Mountain's own colour
  block; every test passed, and verify showed 18 Mine pictures changed by
  23 to 32%. *Rule:* after touching shared track code, run verify on all
  tracks; "pictures changed" on a track you didn't mean to touch is a bug.
- **Fail fast.** A test or bench that can't load waits forever unless it has
  a time limit or watches for script errors; both now do.
- **Testing views:** `?showroom&items` (item models), `?give=ITEM` (start
  holding one), `?drop=A,B` (items ahead of the line), `?spots` (viewpoint
  tour), `?map` (whole course from above), effect switches `?glow=`,
  `?lights=`, `?aa=`, `?relief=off`, `?kartshadows=off`, `?px=`.
