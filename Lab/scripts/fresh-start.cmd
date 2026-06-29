@echo off
setlocal
pushd "%~dp0.."

echo [1/5] Removing old containers, networks, and lab volumes...
docker compose down --remove-orphans --volumes
for %%C in (pos peri-fw dmz int-fw app kms db log-server) do docker rm -f %%C 2>nul
for %%N in (store_net dmz_net app_net kms_net db_net) do docker network rm pci-segmentation-core_%%N 2>nul

echo [2/5] Generating TLS certificates and WireGuard keys...
call scripts\generate-lab-secrets.cmd
if errorlevel 1 goto :fail

echo [3/5] Building images...
docker compose build
if errorlevel 1 goto :fail

echo [4/5] Starting lab...
docker compose up -d
if errorlevel 1 goto :diagnose

echo [5/5] Current status:
docker compose ps
popd
exit /b 0

:diagnose
echo.
echo Startup failed. Relevant logs:
docker compose logs --tail=200 kms db log-server
set "RC=1"
popd
exit /b %RC%

:fail
set "RC=1"
popd
exit /b %RC%
