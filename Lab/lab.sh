#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

COMPOSE=(docker compose)
START_TIMEOUT="${LAB_START_TIMEOUT:-300}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

check_prerequisites() {
  require_command docker
  docker info >/dev/null 2>&1 || fail 'Docker engine is not available.'
  docker compose version >/dev/null 2>&1 || fail 'Docker Compose v2 is required.'
}

ensure_env() {
  if [[ ! -f .env ]]; then
    require_command openssl
    password="$(openssl rand -hex 32)"
    printf 'DB_PASSWORD=%s\nDEMO_EVIDENCE_ENABLED=true\nDEMO_UI_PORT=8443\n' "$password" > .env
    chmod 0600 .env
    echo 'Created local .env with a generated database password.'
  fi
}

ensure_secrets() {
  if [[ ! -s secrets/pki/ca/ca.crt || ! -s secrets/wireguard/pos/wg0.conf ]]; then
    require_command openssl
    bash scripts/generate-lab-secrets.sh
  fi
}

verify_lab() {
  local dashboard_port=8443
  "${COMPOSE[@]}" ps
  "${COMPOSE[@]}" exec -T demo-ui curl --fail --silent --show-error \
    --tlsv1.2 --tls-max 1.2 --cacert /etc/lab/pki/ca.crt \
    https://localhost:8443/health >/dev/null \
    || fail 'Demo UI health endpoint failed.'
  "${COMPOSE[@]}" exec -T antimalware /usr/local/lib/lab/clamav-control.sh status >/dev/null \
    || fail 'Anti-malware service check failed.'
  if [[ -f .env ]]; then
    dashboard_port="$(awk -F= '$1 == "DEMO_UI_PORT" {print $2; exit}' .env)"
    dashboard_port="${dashboard_port:-8443}"
  fi
  echo 'Lab verification: PASS'
  echo "Dashboard: https://localhost:${dashboard_port}"
}

up() {
  check_prerequisites
  ensure_env
  ensure_secrets
  "${COMPOSE[@]}" up -d --build --remove-orphans --wait --wait-timeout "$START_TIMEOUT"
  verify_lab
}

case "${1:-up}" in
  up|start) up ;;
  verify) check_prerequisites; verify_lab ;;
  config) check_prerequisites; ensure_env; "${COMPOSE[@]}" config -q; echo 'Compose configuration: PASS' ;;
  topology) check_prerequisites; ensure_env; ensure_secrets; "${COMPOSE[@]}" --profile topology up -d --build --remove-orphans --wait --wait-timeout "$START_TIMEOUT"; "${COMPOSE[@]}" --profile topology ps ;;
  status) check_prerequisites; "${COMPOSE[@]}" ps ;;
  demo) check_prerequisites; bash scripts/demo/good-transaction.sh ;;
  deny-test) check_prerequisites; bash scripts/demo/bad-source-test.sh ;;
  av-test) check_prerequisites; bash scripts/demo/av-eicar-test.sh ;;
  av-scan) check_prerequisites; "${COMPOSE[@]}" exec -T antimalware /usr/local/lib/lab/clamav-control.sh scan ;;
  time) check_prerequisites; bash scripts/demo/show-time-sync.sh ;;
  logs) check_prerequisites; "${COMPOSE[@]}" logs -f --tail=100 ;;
  down|stop) check_prerequisites; "${COMPOSE[@]}" --profile topology down --remove-orphans ;;
  reset)
    check_prerequisites
    [[ "${2:-}" == "--yes" ]] || fail 'reset deletes all lab volumes. Run: ./lab.sh reset --yes'
    "${COMPOSE[@]}" --profile topology down --remove-orphans --volumes
    echo 'Containers, networks, and persistent lab data were removed.'
    ;;
  regenerate-secrets)
    check_prerequisites
    [[ "${2:-}" == "--yes" ]] || fail 'regenerate-secrets replaces all local lab keys. Run: ./lab.sh regenerate-secrets --yes'
    "${COMPOSE[@]}" --profile topology down --remove-orphans
    require_command openssl
    bash scripts/generate-lab-secrets.sh
    echo 'Lab certificates and WireGuard keys were regenerated.'
    ;;
  *)
    cat <<'USAGE'
Usage: ./lab.sh [command]

Commands:
  up                 Generate local configuration, build, start, and verify the lab
  status             Show container status
  verify             Verify the running lab
  config             Validate the Compose file
  topology           Start optional departmental placeholder networks
  demo               Run a successful transaction
  deny-test          Run real unauthorized firewall tests
  av-test            Run the controlled EICAR test
  av-scan            Run an on-demand repository scan
  time               Show time-source validation
  logs               Follow service logs
  down               Stop the lab without deleting data
  reset --yes        Delete containers, networks, and persistent data
  regenerate-secrets --yes  Regenerate local PKI and WireGuard material
USAGE
    exit 2
    ;;
esac
