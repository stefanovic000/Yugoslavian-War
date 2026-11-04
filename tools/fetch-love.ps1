<#
.SYNOPSIS
  Downloads the portable LOVE 11.5 runtime into tools/love.
.DESCRIPTION
  The game project itself is self-contained. This script only restores the
  runtime if it is missing (for example after cloning the project fresh).
#>
param(
  [string]$Version = "11.5"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $root "tools\love"
$zip = Join-Path $env:TEMP "love-$Version-win64.zip"
$url = "https://github.com/love2d/love/releases/download/$Version/love-$Version-win64.zip"

if (Test-Path (Join-Path $dest "lovec.exe")) {
  Write-Host "LOVE already present at $dest"
  exit 0
}

Write-Host "Downloading $url"
Invoke-WebRequest -Uri $url -OutFile $zip
Write-Host "Extracting to $dest"
$temp = Join-Path $env:TEMP "love-extract-$Version"
if (Test-Path $temp) { Remove-Item -Recurse -Force $temp }
Expand-Archive -Path $zip -DestinationPath $temp
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item -Path (Join-Path $temp "love-$Version-win64\*") -Destination $dest -Recurse -Force
Remove-Item -Recurse -Force $temp
Remove-Item -Force $zip

& (Join-Path $dest "lovec.exe") --version
Write-Host "Done: $dest"

