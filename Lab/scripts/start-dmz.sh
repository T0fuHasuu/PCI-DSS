#!/bin/sh
set -eu
. /usr/local/lib/lab/lib.sh

reset_firewall
allow_loopback_and_state
allow_infra_egress 10.0.10.10

# The perimeter firewall is the only system allowed to reach the public TLS
# listener. TLS terminates here at DMZ Nginx.
ipt -A INPUT -p tcp -s 10.0.10.1 -d 10.0.10.10 --dport 443 \
  -m conntrack --ctstate NEW -j ACCEPT

# DMZ Nginx may initiate only mTLS through the internal firewall passthrough.
ipt -A OUTPUT -p tcp -s 10.0.10.10 -d 10.0.10.254 --dport 8443 \
  -m conntrack --ctstate NEW -j ACCEPT

start_chrony_client
start_syslog_forwarder dmz
logger -t dmz "DMZ Nginx starting"

nginx -t
exec nginx -g 'daemon off;'
