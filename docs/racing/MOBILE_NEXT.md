# Mobile browser follow-up

Review of main at `fbf2580` (2026-11-08). These are recommendations, not new
design decisions; DESIGN.md remains the spec. Prioritize reliable phone play
before more tracks or visual effects.

## Approved road and inspection changes

- Added an interactive top/oblique map inspection mode and readiness-based
  screenshot gallery tool; see DESIGN.md 14.3. Inspection disables haze and
  distance culling so missing terrain cannot be hidden by gameplay settings.
- Rebuilt Frost's two detour junctions from polygon unions of the actual road
  footprints, with shared visual/collision geometry, perimeter kerbs and paint,
  path-following centre dashes and stitched collision seams. The lake approach
  retains asphalt until the full road width reaches the ice. The exit ramp is
  kept open. The new junction meshes total about 4,900 triangles.
- Added full-width polygon and asphalt-collider coverage checks. Hardened the
  quiet test runner to reject a Godot script error or missing final summary
  even when Godot exits zero, matching the existing CI safeguard.
- Fixed fresh-checkout bench exports to create the output directory and copy
  the JavaScript bridges, and to track bridge changes for export freshness.
- Baseline browser runs on unmodified `fbf2580`, before the local road changes:
  Low average draw calls 299/376/282 (Meadow/Mine/Frost), zero resets and console
  errors. Only Frost reached the complete 30-second sample. These are software
  rendering workload observations, not phone FPS measurements; do not interpret
  them as measurements of the rebuilt junctions.

Visual review approved by the user on 2026-11-09. Validation: 63 Godot tests,
66 site tests, TypeScript/lint checks and error-free Frost browser captures.

## Implemented follow-up batch (2026-11-09)

- Release held touch inputs and tilt smoothing on cancellation, focus loss,
  page hiding, UI hiding, layout changes and control-scheme changes. Reset on
  race/lobby transitions and block touch input while the garage is open.
  Browser suspension also suppresses automatic throttle. Lifecycle handling
  runs even when motion sensors are unavailable.
- Benchmark schema 2 separates wall time from simulation delta, labels process
  time correctly, counts completed laps, and records progress and build/scenario
  metadata. The optional perf overlay uses wall time too.
- Add high-DPR `--profile phone`, independent `--repeat N` runs and timestamped
  raw results. Reject incompatible/partial baseline comparisons and updates;
  keep old baseline entries as historical evidence.
- Add native multi-finger/interruption/measurement tests and browser bridge /
  comparison-policy tests. Include the JavaScript checks in local checks and CI.

Remaining from this batch's broader goals: physical-phone interruption/thermal/
Safari validation, safe-area layout, phone-friendly JSON export and actual GPU
render-target inspection. Those require additional work; they are not implied by
passing headless tests or Chromium phone-profile runs.

Further visual/asset optimizations follow these measurements; any new visual
changes will receive fresh captures before publishing.

## Follow-up verification evidence

The rebuilt Frost track was measured for 12 simulation seconds per run, Low,
four karts and autodrive, with Chromium 156 / SwiftShader and Godot 4.4.1.
These runs verify the new measurement path; they are **not phone FPS** and are
not comparable to the old 30-second baseline or to each other across profiles.

| Profile | Canvas | 3D scale / estimated pixels | Average draws | Errors / resets |
|---|---|---|---:|---:|
| Desktop, DPR 1 | 960 × 540 | 1.0 / 518,400 | 321 | 0 / 0 |
| Phone, DPR 3, run 1 | 2532 × 1170 | 0.5 / 740,610 | 392 | 0 / 0 |
| Phone, DPR 3, run 2 | 2532 × 1170 | 0.5 / 740,610 | 392 | 0 / 0 |

Validation passed: 76 Godot tests, 66 site tests, four browser-tool tests,
TypeScript and lint. A rendered interruption check injected blur, focus and
touch cancellation: the run recorded all three events, marked itself invalid,
and completed without script or browser errors.

All three samples were complete and valid. Desktop simulation delta implied
7.5 FPS while monotonic elapsed time measured 1.9 FPS, demonstrating why the
old number was misleading on a slow renderer. Phone-profile wall FPS was
1.3 / 1.2; the p95 frame intervals were 916 / 1015 ms on this software host.
No historical baseline was overwritten.

**Next graphics experiment:** Low's 0.5 scale floor exceeds its 600,000-pixel
budget by 23% in the phone profile. A scale around 0.450 should meet the target,
reducing pixels by about 19% from this profile's current output. Confirm the
actual render target and visual readability, then compare repeated matching
runs; reduced pixel count alone does not prove a frame-time improvement.

## Camera and rotation follow-up (implemented)

- The intro camera retained about 1.9 m of filtered terrain-clearance lift at
  its endpoint on all three tracks, then `follow()` removed it instantly. Fade
  clearance after smoothing so it reaches zero smoothly; hand the current pose
  to the chase spring without teleporting. Native scene checks cover each track.
- Keep the landscape prompt separate from motion-sensor setup. Hide it on the
  physical orientation event, even while an iframe still has portrait dimensions;
  size it from the visible viewport. Canvas CSS follows the viewport immediately
  while Godot updates its backing buffer on the next engine frame. Remove the
  old 50/200/500/1000 ms synthetic resize sequence.
- Validation: 76 game tests, three native intro scenes, eight browser-tool tests,
  66 site tests, types/lint and rendered browser checks pass. Camera handoff is
  0.0000 m on all three native tracks and in the Frost web capture. The prompt
  fits 390 × 844 and 320 × 480 viewports and hides synchronously in the test
  that rotates the physical screen before the iframe layout catches up.
- `node racing/tools/bench/transitions.mjs [output-directory]` checks the prompt
  through mismatched screen/viewport orientations and captures a real Frost
  descent. `?autodrive&intro&introtrace` exposes the sampled camera path and
  final handoff distance in `window.__introReport`. Real-phone rotation latency
  still needs confirmation; browser tests cannot reproduce OS animation timing.

## Next work, in order

1. **Make benchmark results comparable (foundation implemented).** Record commit, Godot/export version,
   browser/device, viewport, DPR, actual 3D render size, quality, kart count,
   control mode and seed. Keep rendering-cost tests separate from race-completion
   tests. Compare matching route/progress windows; do not compare arbitrary
   partial runs against full runs. Repeat runs and retain raw results.
   - Implemented: rename `script_ms` to `process_ms`: `Performance.TIME_PROCESS` is process time, not a
     measurement of GDScript execution alone. Use the profiler or explicit
     timers for individual script systems.
   - Record wall-clock frame intervals alongside Godot delta; report p50/p95/p99,
     frames over 33/50/100 ms, startup/load time and longest hitch. Slow-run
     simulation delta can be clamped and conceal actual wall-clock slowness.
   - Legacy `player_laps` means the kart's lap counter: crossing the starting
     line advances 0 to 1. A result of 1 does not prove a completed lap. Report
     completed laps, checkpoint progress and distance separately.
   - Add a phone-friendly Copy/Download JSON action; invalidate or annotate
     measurements when the page is backgrounded.
   - The desktop runner uses 960 × 540 at DPR 1 (0.52 MP). Schema 2 adds a
     high-DPR phone profile to exercise resolution scaling; establish separate
     repeated baselines for each profile.
   - Acceptance: same exported build and scenario can be compared across runs
     without mistaking a quality, route or sampling change for an improvement.

2. **Run a real-phone baseline.** iOS Safari and Android Chrome, including an
   older/mid-range device; all tracks at Low, then Medium where sustainable.
   Test 1/4/8 karts, host versus guest, video call off/on, first load versus warm
   load, and a 10-minute session for thermal effects. Software-rendered cloud
   results describe rendering workload, not phone FPS. Agree device-specific
   gates against the design's 60 FPS goal; use 16.7 ms as the frame budget.

3. **Make controls survive browser interruptions (reset implemented).** Clear fingers, steering and
   held pedals on focus loss, page hiding, cancellation, control-scheme change
   and menu transitions. The interruption reset is implemented; now verify actual iOS/Android event
   delivery when browser gestures interrupt it.
   Respect safe-area insets in both the page and Godot UI; measure button sizes
   in CSS/display pixels rather than assuming canvas pixels are physical size.
   Test gas + steering + brake/drift + item together, both landscape directions,
   sensor denial/no events, browser bars, rotation, lock/unlock and rejoining.
   - Acceptance: no stuck throttle/steering, inaccessible buttons or repeated
     item activation after an interruption; deny tilt and still finish a race.

4. **Reduce the measured draw sources.** Use `--sources` at fixed track locations
   before choosing an optimization. Keep spatially chunked MultiMeshes, shared
   materials and opaque surfaces. Test fewer material surfaces per moving kart
   group, cheaper distant karts and distance-based secondary animation. Only
   investigate a skeletal merge if the remaining kart cost justifies it.
   Track maximum/p95 workloads as well as averages. Inspect transparent item
   boxes, water, particles and layered shade for overdraw on phones.
   - Acceptance: lower draws or measured GPU/frame time on the target phone,
     with matching route coverage and no loss of road/hazard readability.
   The baseline Frost run attributed roughly 120 estimated draws to the two
   snow-pine scatter types versus 21 to merged kart meshes. Tree material consolidation and triangle reduction are now implemented; see
   the evidence below. Any future wind animation needs an explicit leaf mask
   so trunks remain still.

5. **Make Low resilient.** Measure whether its remaining cost is pixels, draw
   submission, shaders or simulation. Current automatic quality stepping stops
   at Low. Consider a bounded resolution controller only if pixel cost is the
   bottleneck, keeping the HUD sharp and using hysteresis. `_fit_resolution()`
   clamps scale to 0.5, so 0.6 MP is not a strict cap on large backing buffers.
   Verify the actual backing size/DPR before changing this.

6. **Add a multiplayer racing browser scenario.** Existing room-rule tests are
   valuable but do not validate a rendered network race. Exercise two clients,
   host-driven bots, countdown, item delivery, race finish, Grand Prix next race,
   reconnect, host interruption and relay fallback. Measure stale updates,
   jitter, bandwidth and send-buffer growth with calls enabled.

7. **Enforce the asset contract.** Add a machine-readable manifest per asset:
   generator/version, pivots, units, bounds, moving groups, attachment points,
   material/surface count, post-export triangles, vertices and file size. Check
   exported GLBs and Godot imports, then review contact sheets of all 64
   chassis × tire × driver combinations. Images alone do not prove no clipping;
   add geometry/attachment checks for meaningful fit constraints.

8. **Recheck loading and docs.** Measure compressed transfer size and time to
   playable on the actual Pages deployment. `all_resources` exports can include
   unused assets; prune only after confirming dynamic load dependencies. Keep
   4.4.1 engine/templates pinned while optimizing. This local export's main files total about 17.8 MB with gzip (WASM 9.39 MB,
   PCK 8.31 MB, JS 0.08 MB), above the 15 MB target; this is a local estimate,
   not an observed production transfer. Update stale design notes:
   stretched parts now merge, Medium's code budget is 1.2 MP, Low is 0.6 MP,
   and old prototype download numbers need fresh measurement.

## Working Godot practices

- Keep fixed-step simulation, render interpolation and the interpolated chase
  camera. Add content through part/track data rather than branching core logic.
- Profile release Web exports on the actual deployment and phones. Native
  physics tests, software WebGL tests and human feel reviews answer different
  questions; retain all three.
- Cache/share immutable meshes and materials. Profile moving procedural mesh
  merging to import/build time or caching by build combination to reduce startup
  work, while preserving independent wheel/head/tail pivots.
  `_merge()` also builds a duplicate combined mesh for cast shadows on Low;
  measure avoiding or lazily building that data when shadows are disabled,
  ensuring a later quality switch can still enable them correctly.
- Keep simple physics collision separate from visual geometry. Chunk scenery
  for culling; a whole-track MultiMesh loses useful per-instance culling.
- Preserve inverse-transpose normal transforms for stretched meshes. If future
  materials need UVs/tangents, extend `_combine()` deliberately: it currently
  preserves position/normal/color/index only. Handle mirrored winding explicitly
  if negative scales are introduced.
- Make every optimization one hypothesis, one change, one comparable run and
  a visual/control check. Keep the previous baseline until the improvement is
  demonstrated; never bless a partial run simply to clear a regression report.

## Working Blender practices

- Pin Blender and Python dependencies (`bpy`, NumPy, scikit-image, Pillow as
  applicable); document one reproducible generation command per asset family.
- Model in meters with documented forward/up axes, real pivot locations and
  stable names for moving parts and mounts. Validate the exported orientation
  in Godot, not only in a Blender beauty render.
- Keep high-detail source generation separate from the game export. Spend
  geometry on silhouettes visible from the race camera; preserve eyes, ears,
  tires and contact points before small hidden fittings.
- Measure after modifiers and triangulation. `common.export()` currently uses
  approximate decimation and skips small meshes, so its target is not a hard
  budget gate. Fail validation on an over-budget final GLB instead of assuming
  decimation achieved the target. Retain vertex colors/AO and inspect normals.
  A direct audit of the checked-in GLB primitives found 2,860 triangles in
  `wheel.glb` against its 2,400 target, and 7,236 in `kart_hauler.glb` against
  7,000. Driver-file totals include seated and standing variants, so validate
  the selected race assembly separately from the whole file.
- Budget material surfaces and moving groups alongside triangles. Joining
  objects alone does not collapse material draw calls. Keep rubber, paint,
  metal and fur distinct only where that distinction is visible.
- Bake AO consistently and preserve color-space conventions. Vertex AO suits
  the current style; use texture/normal detail only when visible at phone scale.
  Avoid transparent layers for details that can be opaque geometry or paint.
- Review assets inside Godot Compatibility at Low, from race distance, under
  tunnel and daylight lighting. Cycles previews cannot validate WebGL shading,
  material translation, transparency, or runtime cost.

## General development cadence

Finish one vertical slice on real phones: join → build → drive → use an item →
finish → race again. Watch a new player without coaching and record wrong turns,
missed buttons, unwanted drifts, recoveries and time to first race. Use that
evidence to tune controls, feedback and track readability before adding content.
Audio feedback for countdown, grip/drift, item hits and finish is a useful next
polish slice once performance is stable; unlock audio from a real tap and test
its balance with the call. Music style remains an open design decision.

## Tree asset optimization (2026-11-09)

The five tree GLBs now have one opaque surface each, with bark, leaf/needle and
snow colours stored in linear COLOR_0. The shared shader corrects Compatibility's additional vertex-colour conversion; a side-by-side render checks the result. They share one runtime material and retain
spatial MultiMesh chunks. This preserves the existing static tree rendering;
adding wind is a separate change. Triangle budgets are checked after decimation
and again on Godot's imported meshes.

| Tree | Previous triangles | Current triangles | Surfaces before → after |
|---|---:|---:|---:|
| Puffy | 1,799 | 892 | 3 → 1 |
| Pine | 988 | 742 | 3 → 1 |
| Round | 1,500 | 742 | 3 → 1 |
| Snow pine tall | 1,500 | 742 | 4 → 1 |
| Snow pine round | 1,268 | 642 | 4 → 1 |

Total: 7,055 → 3,760 triangles (47% fewer); GLBs 214,936 → 135,576 bytes.
Generate with Blender 4.3.2, using its Python runtime to invoke
`props.py OUTDIR tree_puffy pine_tall tree_round snowpine_tall snowpine_round --no-preview`.
Omit `--no-preview` for Blender beauty sheets; always inspect the Godot export.

A matching 12-second Frost Low / four-kart autodrive run measured 326 → 224
average draws (31% fewer). The estimated snow-pine draw sources
fell from 137 to 34. Both runs completed with zero errors/resets and passed the
scenario/route compatibility checks. Engine-reported scene primitives rounded
to 75k in both runs (import LODs and other scene content remain relevant).
The final correctness suite overlapped the final draw-workload check, so timing
metrics from that check are not used for comparison. These results establish
fewer draw submissions, not a demonstrated frame-time or real-phone FPS gain.
Historical baselines were not updated.

## Approved colour rollout: Meadow first

See DESIGN.md 9.1a for the approved eight-colour sRGB starting palette, lighting
direction and per-track identities. The Meadow prototype has been approved and enabled; the same art direction
now extends to the Mine and Frost themes. The Meadow prototype covered foliage, roadside props,
lighting and kart paint, reducing nearby blue haze and improving light/shadow
separation. Matched Low-quality Web captures were reviewed before rollout. Preserve the one-surface tree materials, vertex colours,
LODs and spatial culling; measure material/shader changes. Mine and Frost extend that approved direction with their own themes.

Meadow palette prototype approved for rollout: clearer sky, reduced nearby blue
haze, warmer kart paints, greener foliage, charcoal asphalt and ivory markings.
All tracks now default to this palette direction; `palette=classic` retains
the comparison view. Chooser shots are recaptured from the updated Web export.

Mine and Frost now use track-specific rock/snow/ice, foliage, sky/fog and accent
colours while sharing the approved kart paints. The chooser capture tool
(`racing/tools/bench/thumbnails.mjs`) regenerates all four cards from the actual
Web export and checks for browser errors. Shared tree surfaces/LODs/culling are
preserved. Classic palette comparisons remain available through `palette=classic`.

## Controlled-route quality comparison

Phone comparisons now use three full laps, split at half the canonical racing-line distance. The schedule is Low/Medium, High/High, Medium/Low; every quality covers both halves once. Each half excludes the same first 50 m, then records its own FPS, frame-time percentiles, draw calls and route progress. Required routes are Meadow cave, Mine tunnel and Frost underwater through hole index 1, validated on all three player laps. This replaces the earlier six timed windows. Use `?autodrive&benchqualities&quality=low`, adding `track=mine` or `track=frost`.

The isolated `scripts/benchmark/` module adapts the race through `BenchmarkContext`; no route/quality test policy is embedded in kart physics or track assets. Real-route integration tests and normal gameplay regression tests run on every deployment. Moving traffic and physics remain live, so route-matched halves improve coverage without claiming exact replay equivalence or proving phone performance gains.
