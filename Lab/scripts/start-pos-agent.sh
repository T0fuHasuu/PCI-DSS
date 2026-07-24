#!/bin/sh
set -eu

python /opt/pos-agent/run.py &
APP_PID=$!

cleanup() {
  kill "${APP_PID:-}" "${NGINX_PID:-}" 2>/dev/null || true
  wait "${APP_PID:-}" "${NGINX_PID:-}" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

attempt=0
while [ "$attempt" -lt 30 ]; do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "[pos-agent] FastAPI exited during startup" >&2
    wait "$APP_PID" || true
    exit 1
  fi

  if python - <<'PY'
import socket
import sys

sock = socket.socket()
sock.settimeout(0.5)
result = sock.connect_ex(("127.0.0.1", 9001))
sock.close()
sys.exit(0 if result == 0 else 1)
PY
  then
    break
  fi

  attempt=$((attempt + 1))
  sleep 1
done

if [ "$attempt" -ge 30 ]; then
  echo "[pos-agent] FastAPI did not start on 127.0.0.1:9001" >&2
  exit 1
fi

nginx -t
nginx -g 'daemon off;' &
NGINX_PID=$!

while :; do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "[pos-agent] FastAPI exited unexpectedly" >&2
    kill "$NGINX_PID" 2>/dev/null || true
    wait "$APP_PID" || true
    exit 1
  fi

  if ! kill -0 "$NGINX_PID" 2>/dev/null; then
    echo "[pos-agent] Nginx exited unexpectedly" >&2
    kill "$APP_PID" 2>/dev/null || true
    wait "$NGINX_PID" || true
    exit 1
  fi

  sleep 2
done
