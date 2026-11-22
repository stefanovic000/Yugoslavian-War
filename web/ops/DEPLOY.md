# Deploying `yugowar.stef000.dev`

## VPS folders

You need **three** paths, not a second checkout:

| Purpose | Path |
|---|---|
| Lua game server | `/home/ubuntu/Yugoslavian-planes` |
| Static browser build | `/srv/yugoslavian-war-web` |
| Node WS gateway | `/opt/yugoslavian-war-gateway` |
| Caddy config | `/etc/caddy/Caddyfile` |

The web client and desktop EXE still share the existing Lua server.

## 1. Build locally

```powershell
powershell -ExecutionPolicy Bypass -File web/build.ps1
```

Output: `build/web/`.

## 2. Copy static files

```bash
sudo mkdir -p /srv/yugoslavian-war-web
sudo rsync -a --delete build/web/ ubuntu@YOUR_VPS:/tmp/yugoslavian-war-web/
ssh ubuntu@YOUR_VPS 'sudo rsync -a --delete /tmp/yugoslavian-war-web/ /srv/yugoslavian-war-web/'
```

## 3. Gateway

```bash
sudo mkdir -p /opt/yugoslavian-war-gateway
sudo cp -r web/gateway/* /opt/yugoslavian-war-gateway/
cd /opt/yugoslavian-war-gateway
sudo npm install --omit=dev
```

Install the unit:

```bash
sudo cp web/ops/yugoslavian-war-gateway.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now yugoslavian-war-gateway
systemctl status yugoslavian-war-gateway
```

## 4. Caddy

Add the site block from `web/ops/Caddyfile.example` to
`/etc/caddy/Caddyfile`. If Caddy already hosts other sites, append the block;
do not replace the file.

```bash
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

Caddy obtains the certificate for `yugowar.stef000.dev` automatically once the
DNS record points at the VPS and ports 80/443 are open.

## 5. Firewall

Public:

- 22 (SSH, restricted if possible)
- 80
- 443
- 7777/TCP for the desktop client

Loopback only:

- 9001 gateway
- 7777 from the gateway

If you later proxy desktop play through Caddy as well, you can close 7777.

## 6. Verify

```bash
curl -I https://yugowar.stef000.dev/
systemctl is-active yugoslavian-war
systemctl is-active yugoslavian-war-gateway
```

Then open `https://yugowar.stef000.dev/` in Chrome.

The current web transport is a bridge into the same server; desktop and web
will share rooms once the browser bridge is verified end-to-end.
