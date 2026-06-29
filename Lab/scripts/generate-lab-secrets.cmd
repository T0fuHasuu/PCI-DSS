@echo off
setlocal EnableExtensions

if not "%~1"=="" (
  set "PROJECT_ROOT=%~f1"
) else (
  for %%I in ("%~dp0..") do set "PROJECT_ROOT=%%~fI"
)

if not exist "%PROJECT_ROOT%\docker-compose.yml" (
  echo ERROR: docker-compose.yml was not found under:
  echo   %PROJECT_ROOT%
  echo.
  echo Run this script from the project copy, or pass the project path:
  echo   scripts\generate-lab-secrets.cmd D:\Workspaces\Sandbox\V6
  exit /b 1
)

pushd "%PROJECT_ROOT%"
docker run --rm -v "%PROJECT_ROOT%:/work" -w /work alpine:3.22 sh -lc "apk add --no-cache bash openssl wireguard-tools > /dev/null && bash ./scripts/generate-lab-secrets.sh"
set "RC=%ERRORLEVEL%"
popd

if not "%RC%"=="0" exit /b %RC%
echo Generated base lab certificates, WireGuard keys, and dashboard certificates when the dashboard generator is installed.
