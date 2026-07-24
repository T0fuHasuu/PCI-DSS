#!/usr/bin/env bash
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
set -euo pipefail

echo '[Perimeter firewall - minimum relevant rules]'
$DC exec -T peri-fw sh -lc "iptables -S INPUT | grep -E 'wg0|51820|PERI_FW|DROP' | sed -E 's/ -m limit.*--nflog-prefix / --nflog-prefix /'"
echo
echo '[Internal firewall - minimum relevant rules]'
$DC exec -T int-fw sh -lc "iptables -S INPUT | grep -E '8443|9443|INT_FW|DROP|REJECT' | sed -E 's/ -m limit.*--nflog-prefix / --nflog-prefix /'"
