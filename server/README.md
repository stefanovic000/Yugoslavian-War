# Yugoslavian War — dedicated server

Runs on Ubuntu with **Lua 5.1 + LuaSocket**. The server is authoritative: it
ticks flight, damage, bullets, ammo crates and rounds at 60 Hz, and broadcasts
20 Hz snapshots. Clients never decide their own damage.

## Install

```bash
sudo apt update
sudo apt install -y lua5.1 lua-socket
lua5.1 -e "print(require('socket')._VERSION)"   # must print LuaSocket ...
```

If that command cannot find `socket.core`, the distro's LuaSocket was built for
a different Lua version; install LuaSocket for 5.1 or use `luarocks --lua-version=5.1`.

The complete server is installed at `/home/ubuntu/Yugoslavian-planes`:

```bash
sudo mkdir -p /home/ubuntu/Yugoslavian-planes
sudo cp -r server shared lib README.md /home/ubuntu/Yugoslavian-planes/
sudo chown -R ubuntu:ubuntu /home/ubuntu/Yugoslavian-planes
chmod -R u=rwX,go=rX /home/ubuntu/Yugoslavian-planes
```

The server needs only `server/`, `shared/` and `lib/json.lua`. It writes no
files; logs go to stdout/journal.

Run in the foreground for the first test:

```bash
cd /home/ubuntu/Yugoslavian-planes
lua5.1 server/run.lua --port=7777
```

The client defaults to **SERVER ADDRESS `132.226.207.140`** and **SERVER PORT
`7777`**. You can override the address in **SETTINGS** if the deployment moves.

## systemd

```bash
sudo ln -sf /home/ubuntu/Yugoslavian-planes/server/yugoslavian-war.service /etc/systemd/system/yugoslavian-war.service
sudo systemctl daemon-reload
sudo systemctl enable --now yugoslavian-war
sudo systemctl status yugoslavian-war
journalctl -u yugoslavian-war -f
```

## Firewall / NAT

```bash
sudo ufw allow 7777/tcp
sudo ufw status
```

If the server is behind a home router or cloud NAT, forward TCP `7777` to it.
The game uses TCP only; no UDP port is needed.

For a public deployment, also consider:

- provider-level DDoS protection / firewall;
- limiting SSH to your own IP;
- `fail2ban` for repeated malformed connections (the server already rate-limits
  and closes floods);
- keeping the OS and LuaSocket updated.

## Security posture

This is a small public game server, not an account system.

- **No passwords, accounts or TLS.** Names are public; do not send secrets.
- **All input is validated and clamped.** Clients only send small JSON input
  packets; physics and damage stay on the server.
- **Resource limits:** 64 concurrent clients, 6 per IP, 16 rooms, 4 players and
  8 spectators per room, 4 KB messages, 16 KB receive buffer, 96 KB per-client
  send queue, 30 s idle timeout, 140 msg/s token bucket.
- **Kicks are bans for that room:** the kicked IP and client id cannot rejoin
  that room while it exists. Other rooms are unaffected.
- **Slow clients are disconnected** rather than allowed to block the loop.
- **No dynamic code execution.** JSON is decoded and whitelisted by message
  type; unknown fields are ignored.
- The systemd unit runs as an unprivileged user with `ProtectSystem=strict`,
  `ProtectHome=read-only`, `PrivateTmp=true`, `NoNewPrivileges=true`, no
  capabilities, and only IPv4/IPv6 socket families.
- The server does not need write access to the checkout. Keep it that way.

An open port is always subject to traffic abuse; provider-level protection is
the right tool for volumetric attacks. The in-process limits protect the game
loop from malformed/flooding clients, not from a saturated uplink.

## How a room works

- Create a room; it is immediately visible in the browser. There is no
  ready/accept step.
- The host starts when 2–4 pilots are present.
- Started rooms remain listed. Joining one puts you in as a spectator.
- The host can kick from the lobby; the kicked player is banned from that room
  for its lifetime.
- A match is 5 kill-scored rounds. Pilots respawn 3 seconds after being shot
  down; the first pilot to 5 kills wins the round. Rounds run back-to-back with
  a short break; after round 5 there is a 10-second preparation window in which
  spectators can join the next match. Then the next match starts automatically
  if 2+ pilots remain; otherwise the room returns to the lobby.
- Leaving the room with players still present transfers host to the next pilot.
  If the last pilot leaves, the room closes.

## Local testing

From the project root on Windows:

```bat
run.bat --server --port=7777
```

That starts the same server headless through LÖVE's bundled LuaSocket. On
Ubuntu use the Lua command above.

Useful checks:

```bash
python3 tests/server_integration.py   # spectator join, kick/ban, flood
```

Client smoke tests do not require the server; live network tests do.

## Troubleshooting

- **Client says connection failed:** check the IP/port in Settings, `ufw`, NAT
  forwarding, and that the process is listening (`ss -ltnp | grep 7777`).
- **Rooms list empty:** refresh; the server broadcasts the list every 2 seconds.
- **Kicked but can still see the room:** you are banned from that room only, and
  the browser may still show it until it refreshes; joining will be refused.
- **Server CPU high:** check room count and `journalctl`; the caps are in
  `server/server.lua` if you need tighter limits for a public box.
