@echo off
setlocal EnableExtensions
pushd "%~dp0.."

set "TMP_TX_ID=.lab-tx-id.txt"
set "TMP_CIPHER=.lab-ciphertext.txt"

del /q "%TMP_TX_ID%" "%TMP_CIPHER%" >nul 2>&1

echo ============================================================
echo POS transaction and encryption verification
echo ============================================================

echo.
echo [1/5] Copy and run the transaction script inside POS...
docker compose cp scripts/pos-transaction.sh pos:/tmp/pos-transaction.sh
if errorlevel 1 goto :fail

docker compose exec -T pos sh /tmp/pos-transaction.sh
if errorlevel 1 goto :fail

echo.
echo [2/5] Read the generated transaction ID...
docker compose cp pos:/tmp/last_tx_id "%TMP_TX_ID%"
if errorlevel 1 goto :fail
set /p TX_ID=<"%TMP_TX_ID%"
if not defined TX_ID goto :fail
echo tx_id=%TX_ID%

echo.
echo [3/5] Verify the persisted PostgreSQL row...
docker compose cp scripts/verify-db-row.sh db:/tmp/verify-db-row.sh
if errorlevel 1 goto :fail

docker compose exec -T db sh /tmp/verify-db-row.sh %TX_ID%
if errorlevel 1 goto :fail

echo.
echo [4/5] Copy the stored ciphertext from DB to Vault for controlled verification...
docker compose cp db:/tmp/last-ciphertext.txt "%TMP_CIPHER%"
if errorlevel 1 goto :fail

docker compose cp "%TMP_CIPHER%" kms:/tmp/last-ciphertext.txt
if errorlevel 1 goto :fail

docker compose cp scripts/verify-vault-ciphertext.sh kms:/tmp/verify-vault-ciphertext.sh
if errorlevel 1 goto :fail

docker compose exec -T kms sh /tmp/verify-vault-ciphertext.sh /tmp/last-ciphertext.txt
if errorlevel 1 goto :fail

echo.
echo [5/5] Confirm PostgreSQL used TLS 1.2 from the application network...
docker compose cp scripts/verify-db-tls.sh app:/tmp/verify-db-tls.sh
if errorlevel 1 goto :fail

docker compose exec -T app sh /tmp/verify-db-tls.sh
if errorlevel 1 goto :fail

echo.
echo ============================================================
echo PASS: POS transaction was processed and stored as expected.
echo - PAN stored only in masked form
echo - Card token stored as an opaque token
echo - CHD stored as Vault Transit ciphertext
echo - Decrypted CHD contains PAN and expiry, but no CVV/SAD
echo - App-to-PostgreSQL connection uses TLS 1.2
echo ============================================================

del /q "%TMP_TX_ID%" "%TMP_CIPHER%" >nul 2>&1
popd
exit /b 0

:fail
echo.
echo FAIL: transaction verification did not complete.
echo Check:
echo   docker compose ps
echo   docker compose logs --tail=100 pos dmz app kms db

del /q "%TMP_TX_ID%" "%TMP_CIPHER%" >nul 2>&1
popd
exit /b 1
