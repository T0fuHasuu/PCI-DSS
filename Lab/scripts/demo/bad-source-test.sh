#!/usr/bin/env bash
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
set -euo pipefail

read_line_count() {
  local file="$1"
  $DC exec -T log-server sh -lc "wc -l < '$file'"
}

wait_for_log() {
  local file="$1"
  local start_line="$2"
  local pattern="$3"
  local attempt
  for attempt in $(seq 1 15); do
    if $DC exec -T log-server sh -lc "tail -n +$((start_line + 1)) '$file' | grep -E '$pattern' | tail -n 1"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

PERIMETER_LOG=/var/log/remote/perimeter-firewall.log
INTERNAL_LOG=/var/log/remote/internal-firewall.log
perimeter_before="$(read_line_count "$PERIMETER_LOG")"
internal_before="$(read_line_count "$INTERNAL_LOG")"

cleanup() {
  $DC exec -T demo-api sh -lc 'iptables -D OUTPUT -p tcp -s 192.168.10.30 -d 192.168.10.254 --dport 443 -j ACCEPT' >/dev/null 2>&1 || true
  $DC exec -T dmz sh -lc 'iptables -D OUTPUT -p tcp -s 10.0.10.10 -d 10.0.10.254 --dport 9443 -j ACCEPT' >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo '[1/2] Unauthorized Store-side source attempts direct perimeter HTTPS'
$DC exec -T demo-api sh -lc 'iptables -I OUTPUT 1 -p tcp -s 192.168.10.30 -d 192.168.10.254 --dport 443 -j ACCEPT'
$DC exec -T demo-api python - <<'PY'
import socket
sock = socket.socket()
sock.settimeout(2)
try:
    sock.connect(("192.168.10.254", 443))
    print("unexpected_connection=established")
except (TimeoutError, ConnectionError, OSError) as exc:
    print(f"connection_blocked={type(exc).__name__}")
finally:
    sock.close()
PY

if wait_for_log "$PERIMETER_LOG" "$perimeter_before" 'PERI_FW_DROP.*SRC=192\.168\.10\.30.*DPT=443'; then
  echo 'Perimeter default-deny verification: PASS'
else
  echo 'Perimeter default-deny verification: FAIL' >&2
  exit 1
fi

echo
echo '[2/2] DMZ attempts the internal firewall reject-test port'
$DC exec -T dmz sh -lc 'iptables -I OUTPUT 1 -p tcp -s 10.0.10.10 -d 10.0.10.254 --dport 9443 -j ACCEPT'
$DC exec -T dmz sh -lc 'curl --silent --show-error --connect-timeout 2 http://10.0.10.254:9443/ >/dev/null 2>&1 || true'

if wait_for_log "$INTERNAL_LOG" "$internal_before" 'INT_FW_DROP action=REJECT.*SRC=10\.0\.10\.10.*DPT=9443'; then
  echo 'Internal firewall reject verification: PASS'
else
  echo 'Internal firewall reject verification: FAIL' >&2
  exit 1
fi
