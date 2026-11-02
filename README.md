# Game Night

Party games played browser to browser. One person creates a room, everyone else joins from their phone with a 5-letter code or a link. No accounts, no installs, and no game server to pay for.

## How it works

```
GitHub Pages ──(static files, once)──▶ every browser
PeerJS broker ──(introductions only)──▶ every browser

            Player ──┐
            Player ──┼──▶ Host's browser  (runs the rules, saves the game)
            Player ──┘
```

- **Static site.** Everything is plain files, so it's hosted free on GitHub Pages.
- **Star, not mesh.** Each player connects only to the host's browser over WebRTC. The host runs the room and game rules and sends each player just what they're allowed to see, so hidden roles never reach other players' devices.
- **Matchmaking.** The host registers with the free public [PeerJS](https://peerjs.com) broker under an id built from the room code. Players dial that id. After the handshake the broker is out of the loop.
- **Rejoining.** Each tab keeps a stable player id, so a refresh drops you back into your seat. If you closed the tab, join again with the same name to reclaim your seat. If the host refreshes or closes the tab, the game is saved in their browser and players reconnect automatically when they come back (or when the host clicks "Reopen room").

## Games

- **Spyfall** (3–12 players)
- **Four in a Row** (2 players)
- **Haunted House** (3–6 players): explore a house tile by tile until the haunt begins and one player turns traitor. Plays by Betrayal at House on the Hill 3rd-edition rules, with original names, text and art. Data notes are in `lib/games/haunted/data/`: explorer stats, room tiles, items and the scenario chart match 3rd edition; event cards, omen effects and room doorway layouts are approximations because they couldn't be sourced. Three haunts are built (28, 30, 44); when the chart points to an unbuilt haunt, 28 or 44 is played instead.

## Code map

| Path | What it is |
| --- | --- |
| `lib/engine/` | Pure room logic: join, leave, rejoin, kick, start, per-player views. No networking. |
| `lib/games/<game>/rules.ts` | A game as pure functions: `setup`, `action`, `view`, `tick`, `playerLeft`. |
| `lib/games/<game>/*View.tsx` | The game's UI. Receives its view and an `act()` function. |
| `lib/net/` | PeerJS host and client sessions, heartbeats, reconnection, storage. |
| `lib/session.tsx` | React glue between sessions and the UI. |
| `components/` | Home, lobby, game shell. |
| `legacy/` | Secret Hitler and Codenames from the old engine, waiting to be ported. Not built. |

### Adding a game

1. Write `lib/games/<id>/rules.ts` exporting a `GameModule` (see `lib/engine/types.ts` and `lib/games/spyfall/rules.ts`). Keep it pure: use `ctx.now` and `ctx.random`, never `Date.now()` or `Math.random()`.
2. Strip anything a player shouldn't see in `view(state, playerId)`.
3. Write a view component that takes `GameViewProps`.
4. Register both in `lib/games/modules.ts` and `lib/games/ui.ts`.
5. Add rule tests next to `tests/room.test.ts`.

## Development

```bash
npm install
npm run dev        # http://localhost:3000, uses the public PeerJS broker
npm test           # engine and rules unit tests
```

Open the site in two or more tabs (or a normal and a private window) to play against yourself. Each tab is its own player.

To work offline or run the end-to-end test, use the local broker:

```bash
npm run broker &   # PeerJS broker on 127.0.0.1:9000
NEXT_PUBLIC_PEER_HOST=127.0.0.1 NEXT_PUBLIC_PEER_PORT=9000 NEXT_PUBLIC_PEER_SECURE=false npm run build
npx serve out -l 3100 &
APP_URL=http://127.0.0.1:3100/ CHROME=/path/to/chrome npm run test:e2e
```

The end-to-end test drives five separate Chrome profiles through joining, refreshing, reclaiming a seat, the host refreshing mid-game, voting, kicking and closing the room.

## Deploying

Pushing to `main` builds and deploys to GitHub Pages via `.github/workflows/deploy.yml`. One-time setup: **Settings → Pages → Build and deployment → Source: GitHub Actions**.

Optional repository variables (**Settings → Secrets and variables → Actions → Variables**):

| Variable | Use |
| --- | --- |
| `PEER_HOST`, `PEER_PORT`, `PEER_PATH`, `PEER_SECURE` | Use your own broker (the `peer` npm package, e.g. on Render or Fly.io) instead of the public one. |
| `TURN_URL`, `TURN_USERNAME`, `TURN_CREDENTIAL` | A TURN relay for players on strict networks, e.g. Metered's free Open Relay. These end up in the public site, so anyone could find them. |

The same build also deploys unchanged to Vercel or Netlify (leave `NEXT_PUBLIC_BASE_PATH` unset there).
