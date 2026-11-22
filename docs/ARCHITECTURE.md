# Architecture

## Repository shape

```text
main.lua, conf.lua     desktop LÖVE entry point
src/                   client presentation, scenes, input, rendering
shared/                authoritative rules shared by client and server
server/                dedicated Lua multiplayer server
web/                   browser target and deployment assets
tests/                 shared/match regression tests
tools/                 development tools and LÖVE runtime fetcher
docs/                  design and debugging notes
build/                 generated Windows and web output (ignored)
```

## Runtime paths

### Desktop

```text
LÖVE → src/scenes → src/net/client.lua → TCP → server/
```

### Browser

```text
love.js → src/scenes → WebSocket client bridge
        → WSS /ws → Caddy → web/gateway → TCP → server/
```

The browser cannot open raw TCP sockets. The gateway is transport-only and must
not contain game rules.

## Shared code

- `shared/flight.lua` — flight model
- `shared/combat.lua` — hitboxes and damage
- `shared/sim.lua` — deterministic simulation step
- `shared/clouds.lua` — cloud generation and visibility geometry
- `shared/terrain.lua` — ground height used by rendering and collision
- `shared/ai.lua` — bots
- `shared/aircraft/` — aircraft registry

The server and Solo use these directly. The networked client uses the same
combat/aircraft definitions for prediction and rendering.

## Server authority

The server owns:

- plane positions and flight results
- bullets and hit registration
- damage, deaths and respawns
- rounds, sides and match outcome
- clouds and visibility
- room and spectator state

Clients send inputs only. Any browser or desktop client is treated the same.

## Platform-specific code

Desktop:

- `src/net/client.lua` uses LuaSocket
- native window/fullscreen/cursor
- filesystem settings

Browser:

- WebSocket transport
- IndexedDB settings
- browser fullscreen/audio unlock
- no software fullscreen cursor
- no touch UI in the first web target

## Build outputs

- Desktop: `build/Yugoslavian War/`, `build/Yugoslavian-War-Windows.zip`
- Web: `build/web/` (love.js player + `game.love`)

Generated output is ignored. Source stays at the repository root so LÖVE can
run the desktop game directly from the checkout.
