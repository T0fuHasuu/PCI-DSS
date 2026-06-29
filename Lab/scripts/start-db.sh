#!/bin/sh
set -eu
. /usr/local/lib/lab/lib.sh

mkdir -p /var/lib/postgresql/tls
cp /run/lab-pki/server.crt /var/lib/postgresql/tls/server.crt
cp /run/lab-pki/server.key /var/lib/postgresql/tls/server.key
cp /run/lab-pki/ca.crt /var/lib/postgresql/tls/ca.crt
chown -R postgres:postgres /var/lib/postgresql/tls
chmod 0644 /var/lib/postgresql/tls/server.crt /var/lib/postgresql/tls/ca.crt
chmod 0600 /var/lib/postgresql/tls/server.key

reset_firewall
allow_loopback_and_state
allow_infra_egress 10.100.30.10

# DB accepts only the App's DB-side address.
ipt -A INPUT -p tcp -s 10.100.30.20 -d 10.100.30.10 --dport 5432 \
  -m conntrack --ctstate NEW -j ACCEPT

start_chrony_client
start_syslog_forwarder db
logger -t db "PostgreSQL TLS boundary starting"

exec /usr/local/bin/docker-entrypoint.sh "$@"
