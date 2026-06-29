@echo off
setlocal
pushd "%~dp0.."

docker run --rm -v "%CD%:/work" -w /work alpine:3.22 sh -lc "apk add --no-cache bash openssl > /dev/null && bash ./scripts/generate-dashboard-secrets.sh"
set "RC=%ERRORLEVEL%"

popd
if not "%RC%"=="0" exit /b %RC%
echo Generated dashboard TLS certificates.
