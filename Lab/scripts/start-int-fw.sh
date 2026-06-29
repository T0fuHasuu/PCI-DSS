#!/bin/sh
set -eu
. /usr/local/lib/lab/lib.sh

reset_firewall
allow_loopback_and_state
allow_infra_egress 10.100.10.1

# DMZ Nginx may connect only to the internal firewall's TLS passthrough.
ipt -A INPUT -p tcp -s 10.0.10.10 -d 10.0.10.254 --dport 8443 \
  -m conntrack --ctstate NEW -j ACCEPT

# The internal firewall may open only the App TLS listener.
ipt -A OUTPUT -p tcp -s 10.100.10.1 -d 10.100.10.10 --dport 8443 \
  -m conntrack --ctstate NEW -j ACCEPT

start_chrony_client
start_syslog_forwarder int-fw
logger -t int-fw "default-deny internal firewall rules loaded; App TLS passthrough enabled"

# TCP passthrough only. TLS remains end-to-end from DMZ Nginx to App Nginx.
exec socat \
  TCP4-LISTEN:8443,bind=10.0.10.254,reuseaddr,fork,nodelay \
  TCP4:10.100.10.10:8443,nodelay
