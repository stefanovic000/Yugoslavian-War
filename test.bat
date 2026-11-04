@echo off
setlocal
cd /d "%~dp0"

if not exist "tools\love\lovec.exe" (
  echo.
  echo   LOVE runtime not found in tools\love.
  echo   Run: powershell -ExecutionPolicy Bypass -File tools\fetch-love.ps1
  echo.
  exit /b 1
)

"tools\love\lovec.exe" . --test %*
set "CODE=%ERRORLEVEL%"
echo.
if "%CODE%"=="0" (
  echo TEST SUITE PASSED
) else (
  echo TEST SUITE FAILED  ^(exit %CODE%^)
)
exit /b %CODE%

