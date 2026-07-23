#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

docker compose up -d log-server peri-fw int-fw app dmz pos
docker compose exec -T log-server /usr/local/lib/lab/health-log-server.sh

docker compose exec -T app python - <<'PY'
import socket

message = (
    b"<165>1 2026-06-30T00:00:00Z app payment-app - - - "
    b"CDE_TRANSACTION event=collector_probe action=TEST result=SUCCESS "
    b"status=200 request_id=probe src_ip=10.100.10.10 "
    b"dst_ip=10.100.10.10 protocol=UDP dst_port=514 service=payment-app"
)
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.sendto(message, ("10.100.10.200", 514))
sock.close()
PY

sleep 1
docker compose exec -T log-server grep -q event=collector_probe /var/log/remote/cde-transactions.log

docker compose cp scripts/test-logging-pos.sh pos:/tmp/test-logging-pos.sh
docker compose exec -T pos sh /tmp/test-logging-pos.sh

docker compose cp scripts/test-logging-dmz.sh dmz:/tmp/test-logging-dmz.sh
docker compose exec -T dmz sh /tmp/test-logging-dmz.sh

sleep 5

docker compose exec -T log-server tail -n 30 /var/log/remote/perimeter-firewall.log
docker compose exec -T log-server tail -n 30 /var/log/remote/internal-firewall.log
docker compose exec -T log-server tail -n 30 /var/log/remote/cde-transactions.log

docker compose exec -T log-server sh -lc "
  grep -q PERI_FW_ALLOW /var/log/remote/perimeter-firewall.log &&
  grep -q PERI_FW_DROP /var/log/remote/perimeter-firewall.log &&
  grep -q INT_FW_ALLOW /var/log/remote/internal-firewall.log &&
  grep -q 'action=REJECT' /var/log/remote/internal-firewall.log &&
  grep -q 'event=transaction_created' /var/log/remote/cde-transactions.log &&
  grep -q 'event=transaction_approved' /var/log/remote/cde-transactions.log &&
  grep -q 'event=transaction_declined' /var/log/remote/cde-transactions.log
"

echo 'PASS: all required centralized log events were found.'
