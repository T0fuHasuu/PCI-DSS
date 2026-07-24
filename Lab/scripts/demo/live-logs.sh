#!/usr/bin/env bash
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
set -euo pipefail

$DC exec -T log-server sh -lc '
  tail -n 0 -F \
    /var/log/remote/perimeter-firewall.log \
    /var/log/remote/internal-firewall.log \
    /var/log/remote/cde-transactions.log \
    /var/log/remote/antimalware.log \
  | grep -E "PERI_FW_|INT_FW_|CDE_TRANSACTION|CLAMAV_|EICAR"
'
