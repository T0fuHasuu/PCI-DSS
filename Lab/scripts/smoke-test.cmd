@echo off
setlocal
pushd "%~dp0.."
call scripts\transaction-test.cmd
set "RC=%ERRORLEVEL%"
popd
exit /b %RC%
