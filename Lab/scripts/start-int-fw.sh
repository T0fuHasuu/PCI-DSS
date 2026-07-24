#!/bin/sh
set -eu
. /usr/local/lib/lab/lib.sh
. /usr/local/lib/lab/firewall-log-forwarder.sh

start_firewall_log_forwarder int-fw

reset_firewall
allow_loopback_and_state
allow_infra_egress 10.100.10.1

# Log one record for a new permitted DMZ-to-CDE application connection.
ipt -A INPUT -p tcp -s 10.0.10.10 -d 10.0.10.254 --dport 8443 \
  -m conntrack --ctstate NEW \
  -m limit --limit 30/minute --limit-burst 20 \
  -j NFLOG --nflog-group 2 --nflog-threshold 1 \
  --nflog-prefix "INT_FW_ALLOW action=ALLOW service=app-tls "
ipt -A INPUT -p tcp -s 10.0.10.10 -d 10.0.10.254 --dport 8443 \
  -m conntrack --ctstate NEW -j ACCEPT

# Explicit test-only reject port. No service listens on 9443 and no host port is exposed.
ipt -A INPUT -p tcp -s 10.0.10.10 -d 10.0.10.254 --dport 9443 \
  -m conntrack --ctstate NEW \
  -m limit --limit 12/minute --limit-burst 6 \
  -j NFLOG --nflog-group 2 --nflog-threshold 1 \
  --nflog-prefix "INT_FW_DROP action=REJECT service=test-reject "
ipt -A INPUT -p tcp -s 10.0.10.10 -d 10.0.10.254 --dport 9443 \
  -m conntrack --ctstate NEW -j REJECT --reject-with tcp-reset

# Internal firewall may initiate only the App TLS connection.
ipt -A OUTPUT -p tcp -s 10.100.10.1 -d 10.100.10.10 --dport 8443 \
  -m conntrack --ctstate NEW -j ACCEPT

# Rate-limited metadata for all other new denied attempts.
ipt -A INPUT -m conntrack --ctstate NEW \
  -m limit --limit 12/minute --limit-burst 6 \
  -j NFLOG --nflog-group 2 --nflog-threshold 1 \
  --nflog-prefix "INT_FW_DROP action=DENY service=default-deny "
ipt -A INPUT -j DROP

start_chrony_client
logger -t int-fw "internal firewall started with rate-limited NFLOG forwarding"

exec socat \
  TCP4-LISTEN:8443,bind=10.0.10.254,reuseaddr,fork,nodelay \
  TCP4:10.100.10.10:8443,nodelay
