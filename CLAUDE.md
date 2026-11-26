# Games repo

A Next.js site of party games (in `lib/games/`, `app/`) and a Godot kart
racer, Animal Karts (`racing/`), published at
https://lukechn99.github.io/games/ (the racer at `/games/racing/index.html`).

Hide and Seek, a prop-hunt game, is a second Godot project in `hideseek/`
(design in `docs/hideseek/DESIGN.md`; checks: `racing/tools/check.sh hideseek`;
multiplayer end to end: `tests/e2e/hideseek.mjs`, set up as `tests/e2e/run.mjs`),
published at `/games/hideseek/`.

Read before working on the racer:
- `docs/racing/DESIGN.md`: the design and decisions (section 14 for
  performance and measuring).
- `docs/racing/LEARNINGS.md`: what went wrong before and the rules that
  came out of it. Read the measuring and phone sections before any
  performance work.

## Checking a change

- `racing/tools/check.sh [game|site]`: all tests, one line per suite.
- `node racing/tools/verify/verify.mjs [track…|all] [--approve] [--no-tests]`:
  the full check of a racer change (tests, fast race, draw budgets,
  approved pictures, size). Run it before reporting; if pictures changed on
  purpose, look at `racing/tools/verify/out/sheet.png` once, then `--approve`.
- `node racing/tools/bench/bench.mjs`: race benchmark against a baseline.
- Frame rate only means something on a real device. Phone links:
  `…/games/racing/index.html?autodrive&bench&quality=medium` (one setting)
  or `?autodrive&benchmedium` (settings compared inside one race). Results
  come back as pasted text (every benchmark ends with a Copy result button).

## Rules

- Godot 4.4.1 at `~/godot/godot`; Blender models via `racing/tools/blender`
  (`python3`, bpy). New models load while the race loads, never on first use.
- `public/racing` is built by CI on push to `main`; don't commit it.
- Leave no untracked files (a hook checks); scratch work goes outside the repo.
- Never ask for or handle the Cloudflare TURN, Analytics or Turnstile secrets.
- The owner reviews each item before the next starts: finish one, report,
  wait.
