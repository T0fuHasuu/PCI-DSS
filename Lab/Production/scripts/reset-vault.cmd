@echo off
setlocal

echo [1/4] Stopping the Compose project...
docker compose down --remove-orphans
if errorlevel 1 exit /b 1

echo [2/4] Removing only Vault state and AppRole credential volumes...
docker volume rm pci-segmentation-core_vault_data 2>nul
docker volume rm pci-segmentation-core_vault_bootstrap 2>nul
docker volume rm pci-segmentation-core_app_vault_credentials 2>nul

echo [3/4] Rebuilding the patched KMS image...
docker compose build --no-cache kms
if errorlevel 1 exit /b 1

echo [4/4] Starting the complete lab...
docker compose up -d
if errorlevel 1 exit /b 1

docker compose ps
echo.
echo If KMS still fails, run: docker compose logs --tail=200 kms
endlocal
