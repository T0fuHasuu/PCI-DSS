#!/usr/bin/env bash
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
set -euo pipefail

$DC exec -T antimalware /usr/local/lib/lab/clamav-control.sh eicar

echo
echo '[Anti-malware status]'
$DC exec -T antimalware /usr/local/lib/lab/clamav-control.sh status

echo
echo '[Centralized anti-malware event]'
$DC exec -T log-server sh -lc 'grep -E "CLAMAV_EICAR|CLAMAV_SCAN|CLAMAV_UPDATE" /var/log/remote/antimalware.log | tail -n 10'
