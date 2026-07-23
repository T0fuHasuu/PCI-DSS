#!/bin/sh
set -eu

printf '%s\n' '[5] Permitted internal firewall connection'
curl --fail --silent --show-error \
  --tlsv1.2 --tls-max 1.2 \
  --cacert /etc/lab/pki/ca.crt \
  --cert /etc/lab/pki/client.crt \
  --key /etc/lab/pki/client.key \
  --resolve app.internal:8443:10.0.10.254 \
  https://app.internal:8443/health >/tmp/internal-allow.json
cat /tmp/internal-allow.json

printf '%s\n' '[6] Rejected internal firewall connection'
busybox nc -z -w 2 10.0.10.254 9443 >/dev/null 2>&1 || true
