#!/usr/bin/env bash
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
set -euo pipefail

printf '%-16s %-22s %-12s %-12s\n' 'COMPONENT' 'UTC TIME' 'STRATUM' 'OFFSET'
for component in log-server pos peri-fw dmz int-fw app kms db; do
  $DC exec -T "$component" sh -lc '
    utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    tracking="$(chronyc -n tracking 2>/dev/null || true)"
    stratum="$(printf "%s\n" "$tracking" | awk -F: "/^Stratum/ {gsub(/^[[:space:]]+/,\"\",\$2); print \$2}")"
    offset="$(printf "%s\n" "$tracking" | awk -F: "/^Last offset/ {gsub(/^[[:space:]]+/,\"\",\$2); print \$2}")"
    printf "%-16s %-22s %-12s %-12s\n" "$(hostname)" "$utc" "${stratum:-n/a}" "${offset:-n/a}"
  '
done

echo
echo 'Containers share the Docker host clock. Chrony runs in monitor-only mode and verifies the configured lab NTP source without changing host time.'
