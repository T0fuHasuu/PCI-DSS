#!/bin/sh
set -eu

iptables -F
iptables -X
iptables -t nat -F
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# demo-ui -> demo-api over TLS 1.2 + mTLS.
iptables -A INPUT -p tcp -s 172.30.10.10 -d 172.30.10.20 --dport 9443 -j ACCEPT

# demo-api -> POS agent over TLS 1.2 + mTLS.
iptables -A OUTPUT -p tcp -s 192.168.10.30 -d 192.168.10.20 --dport 9444 -j ACCEPT

python /opt/demo-api/run.py &
APP_PID=$!

cleanup() {
  kill "$APP_PID" "$NGINX_PID" 2>/dev/null || true
  wait "$APP_PID" "$NGINX_PID" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

i=0
while [ "$i" -lt 30 ]; do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "[demo-api] FastAPI exited during startup" >&2
    wait "$APP_PID" || true
    exit 1
  fi

  if python - <<'PY'
import socket
import sys

s = socket.socket()
s.settimeout(0.5)
result = s.connect_ex(("127.0.0.1", 9000))
s.close()
sys.exit(0 if result == 0 else 1)
PY
  then
    break
  fi

  i=$((i + 1))
  sleep 1
done

if [ "$i" -ge 30 ]; then
  echo "[demo-api] FastAPI did not start on 127.0.0.1:9000" >&2
  exit 1
fi

nginx -t
nginx -g 'daemon off;' &
NGINX_PID=$!

while :; do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "[demo-api] FastAPI exited unexpectedly" >&2
    kill "$NGINX_PID" 2>/dev/null || true
    wait "$APP_PID" || true
    exit 1
  fi

  if ! kill -0 "$NGINX_PID" 2>/dev/null; then
    echo "[demo-api] Nginx exited unexpectedly" >&2
    kill "$APP_PID" 2>/dev/null || true
    wait "$NGINX_PID" || true
    exit 1
  fi

  sleep 2
done
