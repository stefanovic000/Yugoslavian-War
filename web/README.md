# Web target

Desktop-browser port of Yugoslavian War using LÖVE 11.5 via
[love.js](https://github.com/2dengine/love.js).

This is intentionally **desktop browser only**. It does not include the touch UI.

## Layout

```text
web/
  build.ps1            builds build/web and downloads love.js
  site/template.html   browser entry page
  gateway/             WebSocket -> TCP bridge
  ops/Caddyfile.example
```

## Build the browser client

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File web/build.ps1
```

Then serve `build/web` over HTTPS. Do not open `index.html` from disk:
love.js will not run from `file://`.

## Network path

```text
Browser
  │ WSS /ws
  ▼
Caddy
  │ reverse_proxy
  ▼
gateway (127.0.0.1:9001)
  │ TCP 127.0.0.1:7777
  ▼
existing Lua game server
```

The browser cannot open raw TCP sockets, so the gateway is required.

## Gateway

```powershell
cd web/gateway
npm install
npm start
```

Environment:

- `GAME_HOST` default `127.0.0.1`
- `GAME_PORT` default `7777`
- `GATEWAY_PORT` default `9001`
- `GATEWAY_HOST` default `127.0.0.1`
- `TRUST_PROXY` default `1`

Behind Caddy, the gateway reads `X-Forwarded-For`. The Lua server must be
changed to trust the forwarded identity before this is safe for public use;
see the note in `gateway/server.js`.

## Caddy

Copy `ops/Caddyfile.example` to the Caddy configuration and change
`game.example.com` and `/srv/yugoslavian-war-web`.

Only expose ports **80** and **443** publicly. The gateway and the Lua server
should listen on loopback.

## Current status

- [x] love.js build pipeline
- [x] static browser entry
- [x] WebSocket/TCP gateway
- [x] Caddy reverse-proxy configuration
- [ ] browser WebSocket transport in the Lua client
- [ ] IndexedDB settings/audio unlock
- [ ] tab visibility / reconnect
- [ ] client IP forwarding in the Lua server
