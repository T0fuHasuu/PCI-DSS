#!/usr/bin/env bash
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
set -euo pipefail

echo '[POS WireGuard]'
$DC exec -T pos sh -lc 'ip -br addr show wg0; wg show wg0 listen-port; wg show wg0 endpoints; wg show wg0 latest-handshakes'
echo
echo '[Perimeter WireGuard]'
$DC exec -T peri-fw sh -lc 'ip -br addr show wg0; wg show wg0 listen-port; wg show wg0 peers'
