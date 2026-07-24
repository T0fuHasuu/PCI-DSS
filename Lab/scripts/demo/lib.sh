# shellcheck shell=sh

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: Docker Compose v2 is required" >&2
  exit 1
fi

DC="docker compose"
