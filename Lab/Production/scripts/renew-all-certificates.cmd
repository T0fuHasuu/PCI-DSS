@echo off
setlocal EnableExtensions
for %%I in ("%~dp0..") do set "PROJECT_ROOT=%%~fI"

if not exist "%PROJECT_ROOT%\docker-compose.yml" (
  echo ERROR: docker-compose.yml was not found under %PROJECT_ROOT%.
  exit /b 1
)

pushd "%PROJECT_ROOT%"

echo ============================================================
echo Safe lab certificate renewal
echo ============================================================
echo.
echo [1/4] Stop and remove containers while preserving data volumes...
docker compose down --remove-orphans
if errorlevel 1 goto :fail

echo.
echo [2/4] Generate the base PKI and WireGuard material...
call scripts\generate-lab-secrets.cmd "%PROJECT_ROOT%"
if errorlevel 1 goto :fail

echo.
echo [3/4] Recreate every service so it mounts and loads the new PKI...
docker compose up -d --force-recreate
if errorlevel 1 goto :fail

echo.
echo [4/4] Current state...
docker compose ps

echo.
echo Certificate renewal completed.
echo Wait for all health checks, then run:
echo   scripts\transaction-test.cmd
echo.
echo Dashboard URL:
echo   https://localhost:8443
popd
exit /b 0

:fail
set "RC=%ERRORLEVEL%"
echo.
echo ERROR: Certificate renewal failed.
echo Check the command output above.
popd
exit /b %RC%
