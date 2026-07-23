@echo off
setlocal EnableExtensions
pushd "%~dp0.."

echo ============================================================
echo PCI centralized logging test
echo ============================================================

echo [0] Ensure required services are running...
docker compose up -d log-server peri-fw int-fw app dmz pos
if errorlevel 1 goto :diagnose

echo [0] Verify the real receiver health check...
docker compose exec -T log-server /usr/local/lib/lab/health-log-server.sh
if errorlevel 1 goto :diagnose

echo [0] Send receiver probe from the application network...
docker compose exec -T app python -c "import socket; m=b'\x3c165\x3e1 2026-06-30T00:00:00Z app payment-app - - - CDE_TRANSACTION event=collector_probe action=TEST result=SUCCESS status=200 request_id=probe src_ip=10.100.10.10 dst_ip=10.100.10.10 protocol=UDP dst_port=514 service=payment-app'; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.sendto(m,('10.100.10.200',514)); s.close()"
if errorlevel 1 goto :diagnose

ping 127.0.0.1 -n 2 >nul
docker compose exec -T log-server sh -lc "grep -q 'event=collector_probe' /var/log/remote/cde-transactions.log"
if errorlevel 1 goto :diagnose

docker compose cp scripts/test-logging-pos.sh pos:/tmp/test-logging-pos.sh
if errorlevel 1 goto :fail
docker compose exec -T pos sh /tmp/test-logging-pos.sh
if errorlevel 1 goto :fail

docker compose cp scripts/test-logging-dmz.sh dmz:/tmp/test-logging-dmz.sh
if errorlevel 1 goto :fail
docker compose exec -T dmz sh /tmp/test-logging-dmz.sh
if errorlevel 1 goto :fail

echo Waiting briefly for UDP syslog delivery...
ping 127.0.0.1 -n 6 >nul

echo.
echo --- perimeter-firewall.log ---
docker compose exec -T log-server sh -lc "tail -n 30 /var/log/remote/perimeter-firewall.log"

echo.
echo --- internal-firewall.log ---
docker compose exec -T log-server sh -lc "tail -n 30 /var/log/remote/internal-firewall.log"

echo.
echo --- cde-transactions.log ---
docker compose exec -T log-server sh -lc "tail -n 30 /var/log/remote/cde-transactions.log"

echo.
echo Verifying required events...
docker compose exec -T log-server sh -lc "grep -q PERI_FW_ALLOW /var/log/remote/perimeter-firewall.log && grep -q PERI_FW_DROP /var/log/remote/perimeter-firewall.log && grep -q INT_FW_ALLOW /var/log/remote/internal-firewall.log && grep -q 'action=REJECT' /var/log/remote/internal-firewall.log && grep -q 'event=transaction_created' /var/log/remote/cde-transactions.log && grep -q 'event=transaction_approved' /var/log/remote/cde-transactions.log && grep -q 'event=transaction_declined' /var/log/remote/cde-transactions.log"
if errorlevel 1 goto :diagnose

echo.
echo PASS: all required centralized log events were found.
popd
exit /b 0

:diagnose
echo.
echo --- Receiver diagnostics ---
docker compose exec -T log-server sh -lc "echo HEALTH; /usr/local/lib/lab/health-log-server.sh || true; echo PROCESSES; ps -ef; echo UDP; cat /proc/net/udp; echo IPTABLES; iptables -S INPUT; echo FILES; ls -la /var/log/remote; echo OTHER; if [ -f /var/log/remote/other.log ]; then tail -n 30 /var/log/remote/other.log; fi"

echo.
echo --- Firewall diagnostics ---
docker compose exec -T peri-fw sh -lc "echo RULES; iptables -L INPUT -n -v --line-numbers; echo ULOGD; if [ -f /var/log/ulogd-status.log ]; then cat /var/log/ulogd-status.log; fi; echo EVENTS; if [ -f /var/log/firewall-events.log ]; then tail -n 20 /var/log/firewall-events.log; fi"
docker compose exec -T int-fw sh -lc "echo RULES; iptables -L INPUT -n -v --line-numbers; echo ULOGD; if [ -f /var/log/ulogd-status.log ]; then cat /var/log/ulogd-status.log; fi; echo EVENTS; if [ -f /var/log/firewall-events.log ]; then tail -n 20 /var/log/firewall-events.log; fi"
goto :fail

:fail
echo.
echo FAIL: centralized logging test failed.
echo Check:
echo   docker compose logs --tail=150 log-server peri-fw int-fw app
popd
exit /b 1
