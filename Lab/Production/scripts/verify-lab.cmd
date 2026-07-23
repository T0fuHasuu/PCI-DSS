@echo off
setlocal
pushd "%~dp0.."

echo Container status:
docker compose ps

echo.
echo KMS bootstrap summary:
docker compose logs --tail=80 kms

echo.
echo Running end-to-end smoke test...
call scripts\smoke-test.cmd
set "RC=%ERRORLEVEL%"

popd
exit /b %RC%
