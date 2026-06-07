#!/bin/sh
set -eu

echo "FW_ROLE=${FW_ROLE:-unset}"
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true

iptables -F || true
iptables -t nat -F || true
iptables -t mangle -F || true
iptables -X || true

ROLE="${FW_ROLE:-internal}"

if [ "$ROLE" = "perimeter" ]; then
  sh /perimeter-rules.sh
elif [ "$ROLE" = "internal" ]; then
  sh /internal-rules.sh
else
  echo "Unknown FW_ROLE: $ROLE"
  exit 1
fi

echo "Firewall rules loaded"
tail -f /dev/null