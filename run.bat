@echo off
setlocal
cd /d "%~dp0"

if not exist "tools\love\lovec.exe" (
  echo.
  echo   LOVE runtime not found in tools\love.
  echo   Run: powershell -ExecutionPolicy Bypass -File tools\fetch-love.ps1
  echo.
  pause
  exit /b 1
)

"tools\love\lovec.exe" . %*
if errorlevel 1 pause
endlocal
