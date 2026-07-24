@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "ACTION=%~1"
if not defined ACTION set "ACTION=up"
if not defined LAB_START_TIMEOUT set "LAB_START_TIMEOUT=300"

if /I "%ACTION%"=="up" goto up
if /I "%ACTION%"=="start" goto up
if /I "%ACTION%"=="status" goto status
if /I "%ACTION%"=="verify" goto verify
if /I "%ACTION%"=="config" goto config
if /I "%ACTION%"=="topology" goto topology
if /I "%ACTION%"=="logs" goto logs
if /I "%ACTION%"=="down" goto down
if /I "%ACTION%"=="stop" goto down
if /I "%ACTION%"=="reset" goto reset
if /I "%ACTION%"=="regenerate-secrets" goto regenerate
goto usage

:check_docker
where docker >nul 2>nul || (call :fail "Docker CLI was not found. Install Docker Desktop." & exit /b 1)
docker info >nul 2>nul || (call :fail "Docker Desktop is not running or Linux containers are not enabled." & exit /b 1)
docker compose version >nul 2>nul || (call :fail "Docker Compose v2 is required." & exit /b 1)
exit /b 0

:ensure_env
if exist ".env" exit /b 0
where powershell >nul 2>nul || (call :fail "Windows PowerShell is required to generate the local database password." & exit /b 1)
set "DB_PASSWORD="
for /f "usebackq delims=" %%P in (`powershell -NoProfile -NonInteractive -Command "$r=[Security.Cryptography.RandomNumberGenerator]::Create();$b=New-Object byte[] 32;$r.GetBytes($b);$r.Dispose();($b|ForEach-Object{$_.ToString('x2')}) -join ''"`) do set "DB_PASSWORD=%%P"
if not defined DB_PASSWORD (call :fail "Could not generate the local database password." & exit /b 1)
> ".env" echo DB_PASSWORD=!DB_PASSWORD!
>> ".env" echo DEMO_EVIDENCE_ENABLED=true
>> ".env" echo DEMO_UI_PORT=8443
set "DB_PASSWORD="
echo Created local .env with a random database password.
exit /b 0

:ensure_secrets
if exist "secrets\pki\ca\ca.crt" if exist "secrets\wireguard\pos\wg0.conf" exit /b 0
echo Generating local PKI and WireGuard material inside Docker...
docker build -q -f docker/bootstrap.Dockerfile -t pci-segmentation-bootstrap:local . >nul || (call :fail "Secret bootstrap image build failed." & exit /b 1)
docker run --rm --mount "type=bind,source=%CD%,target=/workspace" -w /workspace pci-segmentation-bootstrap:local scripts/generate-lab-secrets.sh || (call :fail "Secret generation failed." & exit /b 1)
exit /b 0

:doctor
call :check_docker || exit /b 1
docker run --rm --cap-add NET_ADMIN --device /dev/net/tun alpine:3.22.5 sh -c "test -c /dev/net/tun" >nul 2>nul || (call :fail "Docker Desktop does not provide /dev/net/tun. Use the WSL 2 backend with Linux containers." & exit /b 1)
exit /b 0

:up
call :doctor || goto end_error
call :ensure_env || goto end_error
call :ensure_secrets || goto end_error
docker compose config -q || (call :fail "Compose configuration validation failed." & goto end_error)
docker compose up -d --build --remove-orphans --wait --wait-timeout %LAB_START_TIMEOUT% || (call :fail "The lab did not become healthy within %LAB_START_TIMEOUT% seconds." & goto end_error)
call :verify_running || goto end_error
goto end

:verify_running
docker compose ps
docker compose exec -T demo-ui curl --fail --silent --show-error --tlsv1.2 --tls-max 1.2 --cacert /etc/lab/pki/ca.crt https://localhost:8443/health >nul || (call :fail "Demo UI health check failed." & exit /b 1)
docker compose exec -T antimalware /usr/local/lib/lab/clamav-control.sh status >nul || (call :fail "Anti-malware service check failed." & exit /b 1)
set "DASHBOARD_PORT=8443"
for /f "tokens=1,* delims==" %%A in ('findstr /B /C:"DEMO_UI_PORT=" .env 2^>nul') do set "DASHBOARD_PORT=%%B"
echo Lab verification: PASS
echo Dashboard: https://localhost:!DASHBOARD_PORT!
exit /b 0

:verify
call :check_docker || goto end_error
call :verify_running || goto end_error
goto end

:status
call :check_docker || goto end_error
docker compose ps
goto end

:config
call :check_docker || goto end_error
call :ensure_env || goto end_error
docker compose config -q || (call :fail "Compose configuration validation failed." & goto end_error)
echo Compose configuration: PASS
goto end

:topology
call :check_docker || goto end_error
call :ensure_env || goto end_error
call :ensure_secrets || goto end_error
docker compose --profile topology up -d --build --remove-orphans --wait --wait-timeout %LAB_START_TIMEOUT% || (call :fail "Topology profile startup failed." & goto end_error)
docker compose --profile topology ps
goto end

:logs
call :check_docker || goto end_error
docker compose logs -f --tail=100
goto end

:down
call :check_docker || goto end_error
docker compose --profile topology down --remove-orphans
goto end

:reset
call :check_docker || goto end_error
if /I not "%~2"=="--yes" (call :fail "reset deletes all lab volumes. Run: lab.cmd reset --yes" & goto end_error)
docker compose --profile topology down --remove-orphans --volumes || (call :fail "Lab reset failed." & goto end_error)
echo Containers, networks, and persistent lab data were removed.
goto end

:regenerate
call :check_docker || goto end_error
if /I not "%~2"=="--yes" (call :fail "regenerate-secrets replaces all local lab keys. Run: lab.cmd regenerate-secrets --yes" & goto end_error)
docker compose --profile topology down --remove-orphans || (call :fail "Could not stop the lab." & goto end_error)
docker build -q -f docker/bootstrap.Dockerfile -t pci-segmentation-bootstrap:local . >nul || (call :fail "Secret bootstrap image build failed." & goto end_error)
docker run --rm --mount "type=bind,source=%CD%,target=/workspace" -w /workspace pci-segmentation-bootstrap:local scripts/generate-lab-secrets.sh || (call :fail "Secret regeneration failed." & goto end_error)
echo Lab certificates and WireGuard keys were regenerated.
goto end

:usage
echo Usage: lab.cmd [command]
echo.
echo Commands:
echo   up                  Generate local configuration, build, start, and verify
echo   status              Show container status
echo   verify              Verify the running lab
echo   config              Validate the Compose file
echo   topology            Start optional departmental placeholder networks
echo   logs                Follow container logs
echo   down                Stop the lab without deleting data
echo   reset --yes         Delete containers, networks, and persistent data
echo   regenerate-secrets --yes  Replace local PKI and WireGuard keys
exit /b 2

:fail
echo ERROR: %~1 1>&2
exit /b 1

:end
endlocal
exit /b 0

:end_error
endlocal
exit /b 1
