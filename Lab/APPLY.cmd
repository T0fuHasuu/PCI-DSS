@echo off
setlocal
pushd "%~dp0"
echo Copy this patch over the root of the existing lab, then run:
echo.
echo   docker compose down --remove-orphans
echo   docker compose build --no-cache log-server app pos
echo   docker compose up -d
echo   docker compose ps
echo   scripts\transaction-test.cmd
echo.
popd
