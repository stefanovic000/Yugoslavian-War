#requires -Version 5.1
# Build the desktop-browser love.js package for Yugoslavian War.
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root "build\web"
$lovejs = "https://raw.githubusercontent.com/2dengine/love.js/main"

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Path $out | Out-Null
New-Item -ItemType Directory -Path (Join-Path $out "11.5") | Out-Null
New-Item -ItemType Directory -Path (Join-Path $out "lua") | Out-Null

function Fetch($url, $path) {
  Write-Host "fetch $url"
  Invoke-WebRequest -UseBasicParsing $url -OutFile $path
}

Fetch "$lovejs/player.js" (Join-Path $out "player.js")
Fetch "$lovejs/style.css" (Join-Path $out "style.css")
Fetch "$lovejs/11.5/love.js" (Join-Path $out "11.5/love.js")
Fetch "$lovejs/11.5/love.wasm" (Join-Path $out "11.5/love.wasm")
Fetch "$lovejs/lua/normalize1.lua" (Join-Path $out "lua/normalize1.lua")
Fetch "$lovejs/lua/normalize2.lua" (Join-Path $out "lua/normalize2.lua")

# Build the .love archive. Only runtime files, no tools/tests/docs/web.
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
if (-not $py) { throw "Python is required to create game.love" }
$love = Join-Path $out "game.love"
@'
import sys, zipfile
from pathlib import Path
root = Path(sys.argv[1])
out = Path(sys.argv[2])
files = ["main.lua", "conf.lua", "assets", "lib", "shared", "src"]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for name in files:
        p = root / name
        if p.is_file():
            z.write(p, p.name)
        else:
            for f in sorted(p.rglob("*")):
                if f.is_file():
                    z.write(f, f.relative_to(root).as_posix())
print("wrote", out)
'@ | & $py.Source - $root $love

Copy-Item (Join-Path $PSScriptRoot "site\template.html") (Join-Path $out "index.html") -Force
Copy-Item (Join-Path $PSScriptRoot "site\bridge.js") (Join-Path $out "bridge.js") -Force

# Simple cache-buster marker so deployments do not reuse an old package.
$stamp = [DateTime]::UtcNow.ToString("yyyyMMddHHmmss")
$idx = Get-Content (Join-Path $out "index.html") -Raw
$idx = $idx.Replace("__BUILD__", $stamp)
[System.IO.File]::WriteAllText((Join-Path $out "index.html"), $idx, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host "Built build/web"
Write-Host "Serve it over HTTPS; love.js does not run from file://"
