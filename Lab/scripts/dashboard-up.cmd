@echo off
setlocal
pushd "%~dp0.."

call scripts\generate-dashboard-secrets.cmd
if errorlevel 1 goto :fail

docker compose build --no-cache pos app dmz pos-agent demo-api demo-ui
if errorlevel 1 goto :fail

docker compose up -d --force-recreate pos app dmz pos-agent demo-api demo-ui
if errorlevel 1 goto :fail

docker compose ps
echo.
echo Dashboard: https://localhost:8443
popd
exit /b 0

:fail
echo Dashboard startup failed.
popd
exit /b 1
