#!/bin/sh
set -eu
. /usr/local/lib/lab/lib.sh

reset_firewall
allow_loopback_and_state
allow_infra_egress 10.100.10.10

# int-fw is a TCP passthrough. Nginx still authenticates the DMZ client
# certificate with mTLS before forwarding any request to FastAPI.
ipt -A INPUT -p tcp -s 10.100.10.1 -d 10.100.10.10 --dport 8443 \
  -m conntrack --ctstate NEW -j ACCEPT

# App -> Vault TLS/mTLS and AppRole authentication.
ipt -A OUTPUT -p tcp -s 10.100.20.20 -d 10.100.20.10 --dport 8200 \
  -m conntrack --ctstate NEW -j ACCEPT

# App -> PostgreSQL TLS with certificate authentication.
ipt -A OUTPUT -p tcp -s 10.100.30.20 -d 10.100.30.10 --dport 5432 \
  -m conntrack --ctstate NEW -j ACCEPT

start_chrony_client
start_syslog_forwarder app
logger -t app "application boundary starting"

attempt=0
while [ "$attempt" -lt 90 ]; do
  if [ -s /run/vault-approle/role_id ] && [ -s /run/vault-approle/secret_id ]; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 1
done

if [ ! -s /run/vault-approle/role_id ] || [ ! -s /run/vault-approle/secret_id ]; then
  logger -t app "AppRole credential files were not created by KMS"
  echo "[app] FATAL: AppRole credential files are missing" >&2
  exit 1
fi

nginx -t
exec supervisord -c /etc/supervisord.conf
