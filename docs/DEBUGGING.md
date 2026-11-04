# Debugging guide

The game is built so problems are visible without adding a `print`. The debug
layers are independent of gameplay and work in solo and online matches.

---

## Surfaces

| Key | Surface |
| --- | --- |
| `F1` | HUD: FPS, frame graph, draw calls, memory, live watches |
| `F2` / `` ` `` | Console with commands, history and completion |
| `F3` | Hitboxes, cloud volumes, velocity vectors |
| `F4` | Profiler panel |
| `F6` / `F7` / `F8` | Pause / step / 0.25Ã— slow motion |
| `F9` | Screenshot to the save folder |
| `F5` | Reload the current scene (blocked during a live match) |

The 800Ã—450 world is rendered at 0.8Ã— into the 640Ã—360 game canvas, then scaled
to the window; the debug HUD is drawn at native window resolution so it stays
readable.

---

## Logging

`src/core/log.lua` writes to the terminal and a session file.

```lua
local log = require("src.core.log")

log.debug("phase=%s round=%d", phase, round)
log.info("room %d created", roomId)
log.warn("slow client %d", id)
log.error("snapshot encode failed: %s", err)
```

Levels: `trace`, `debug`, `info`, `warn`, `error`, `fatal`, `off`. The default
is `debug`.

- Session log: `%APPDATA%\LOVE\dogfight\logs\session-*.log`
- Crash report: `%APPDATA%\LOVE\dogfight\logs\crash-*.log`
- Console command `logs` opens the folder.

The server logs to stdout/journald (`journalctl -u yugoslavia-dogfight -f`).

---

## Console

`F2` opens the console; the game stops advancing while it is open. Commands are
parsed with quote support, history is kept, and exceptions are caught with a
traceback.

```text
help
stats
god
ammo 120
spawn
tp 320 180
timescale 0.5
step 2
watch
log warn
screenshot
```

`Up`/`Down` history, `Tab` completion, `PgUp`/`PgDn` scroll, `Ctrl+L` clear,
`Ctrl+U` clear input, `Esc` close.

Solo registers `god`, `ammo`, `spawn`, `kill`, `tp`. Online matches are
server-authoritative, so those cheats are not available there.

### Add a command

```lua
Debug:command("heal", "Restore the local plane", function(args)
  player.hp = player.maxHp
  Debug:echo("healed", "ok")
end, { ns = "game", usage = "heal" })
```

Remove namespaced commands and watches in `Scene:leave`:

```lua
Debug:removeCommands("game")
Debug:clearWatches("game")
```

---

## HUD and watches

```lua
Debug:watch("local hp", function() return player.hp end, "game")
Debug:watch("input seq", function() return self.seq end, "netmatch")
```

A watch is evaluated every frame under `pcall`; a throwing watch shows `ERR`
instead of breaking the overlay.

The HUD also shows the frame-time graph (last 180 frames), draw calls, memory,
time scale and seed. `F4` toggles the profiler.

---

## Profiler

The app measures `update` and `draw`. Add scopes around suspicious systems:

```lua
local profiler = require("src.core.profiler")

profiler.push("ai")
updatePlanes(dt)
profiler.pop()
```

The panel averages the last 120 frames. `profiler.reset()` clears it.

---

## Debug geometry

```lua
local dd = require("src.core.debugdraw")

dd.circle(x, y, radius, UI.C.orange)
dd.ray(x, y, angle, 40, UI.C.teal)
dd.vector(x, y, vx * 0.2, vy * 0.2, UI.C.green)
dd.grid(0, 0, 640, 360, 40, { 0.4, 0.5, 0.6, 0.1 })
dd.label("engine", x, y, UI.C.cream)
```

The plane hitboxes in `shared/combat.lua` are the same shapes used for damage,
so `F3` is the ground truth for "did that hit?".

---

## Time control

`F6` pauses, `F7` steps one 1/60 s update, `F8` toggles 0.25Ã—. In a live match
this freezes only the local client; the server keeps running, so snapshots will
snap you forward on resume. Use it for inspection, not as a pause button.

---

## Network debugging

### Local server

```bat
run.bat --server --port=7777
```

This runs the exact server code headlessly through LÃ–VE's bundled LuaSocket.
Then set Settings â†’ Server Address to `127.0.0.1`, port `7777`, and open
Multiplayer.

On Ubuntu:

```bash
lua5.1 server/run.lua --port=7777
```

### Test hooks

- `--flow=create` â€” connect and create a room automatically.
- `--flow=join` â€” connect and join the first room.
- `--flow=start` â€” create/join and start when 2+ players are present.
- `--noclouds` â€” disable cloud occlusion for screenshots/debugging.
- `--scene=menu|solo|multiplayer|settings` â€” boot straight into a scene.
- `--shot=name --frames=N` â€” capture a PNG and exit.
- `--uitest --nohud` â€” click Settings, edit fields and capture
  `preview-uitest.png`; proves mouse routing and text input.
- `--smoke` â€” solo smoke run (see below).

### Second player bot

`tools/bot_test.py` creates a room, joins as a second pilot, starts the match,
and sends inputs. Run it while the server is up, then launch the client with
`--flow=join`.

### Integration test

With a server on `127.0.0.1:7777`:

```bash
python tests/server_integration.py
```

It checks:

- host create and target join;
- match start;
- a third client joining a live room as a spectator;
- host kick;
- the kicked IP being banned from that room;
- flood handling closing the abusive connection.

### Network watches

`netmatch` registers `net phase`, `round`, `input seq`, `acked seq`, `local hp`
and `remote planes`. If the local plane disagrees with the server, compare
`input seq`/`acked seq`; prediction replays everything after the acknowledged
sequence.

The server is authoritative for damage, bullets and rounds. It clamps throttle
and pitch, ignores unknown fields, bounds messages and disconnect floods. See
[server/README.md](../server/README.md) for the deployment and security model.

---

## Smoke test

```bat
smoke.bat
```

Boots directly into solo, runs `god`, `ammo`, `spawn`, `stats`, opens the
console, captures screenshots, exercises pause/step/resume and debug draw, then
prints `SMOKE OK`. It exits 0 on success.

---

## Crash screen

`R` restart, `C` copy the traceback, `PgUp`/`PgDn` scroll, `Esc` quit. A crash
report is written with the last log lines.

Preview it:

```bat
tools\love\lovec.exe . --crash
```

Automated check (draws four frames, exits 1):

```bat
tools\love\lovec.exe . --crash --smoke
```

`--smoke`, `--test`, `--uitest` and `--shot` automatically fail fast on an
uncaught error instead of hanging on the crash screen.

---

## Unit tests

```bat
test.bat
```

56 tests cover:

- utility math/string wrapping;
- class inheritance;
- deterministic flight and stall behaviour;
- wrap-around;
- module damage;
- hitboxes;
- bullet damage/death;
- cloud line of sight;
- AI stall recovery;
- 5-round match lifecycle and champion;
- input clamping/ack;
- timeout winner;
- player removal.

Add a suite in `tests/test_*.lua`, return `{ name = "...", fn = function() ... end }`
cases, and register it in `tests/run.lua`.

---

## VS Code breakpoints

1. Install **Local Lua Debugger**
   (`tomblind.local-lua-debugger-vscode`).
2. `F5` â†’ **LÃ–VE: run + debug**.

The profile runs `love.exe`, sets `LOCAL_LUA_DEBUGGER_VSCODE=1` and disables the
extra console window in `conf.lua`. Breakpoints work in `main.lua`, scenes,
shared simulation and server code. `F5` scene reload is blocked in a live match;
restart the debugger after editing core files.

---

## Command-line flags

| Flag | Effect |
| --- | --- |
| `--test` | Unit tests and exit |
| `--smoke` | Solo smoke run and exit |
| `--uitest` | Scripted click/typing test |
| `--crash` | Deliberately raise an error |
| `--server` | Run the dedicated server headlessly |
| `--port=N` | Server port |
| `--seed=N` | Deterministic RNG seed |
| `--log=LEVEL` | `trace`â€¦`off` |
| `--scene=NAME` | Boot into a scene |
| `--shot=NAME` | Capture a screenshot and exit |
| `--frames=N` | Frames before the screenshot |
| `--flow=create/join/start` | Network test automation |
| `--autofire` | Hold fire in a network match (tracer test) |
| `--noclouds` | Disable cloud occlusion |
| `--no-console` | No Windows console window |
| `--nohud` | Hide the debug HUD |

---

## Practical tips

- Reproduce with `--seed=N`; procedural clouds and pickup drift are seeded.
- When a value matters every frame, add a watch instead of printing.
- Wrap a slow system in a profiler scope before optimizing.
- Use `F9` for visual bugs; the save folder is shown in `stats`.
- In multiplayer, trust the server state when in doubt; local prediction is only
  a display shortcut.
- If a client seems frozen, check `input seq` vs `acked seq`, then the server
  journal. A dead TCP connection closes the match scene back to the browser.

