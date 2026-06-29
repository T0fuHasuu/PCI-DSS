#!/bin/sh
set -eu
. /usr/local/lib/lab/lib.sh

wg-quick up /etc/wireguard/wg0.conf

reset_firewall
allow_loopback_and_state
allow_infra_egress 10.0.10.1

# Outer WireGuard transport from the POS endpoint. Do not require a fixed
# client source port; this is more reliable across Docker Desktop kernels.
ipt -A INPUT  -p udp -s 192.168.10.20 -d 192.168.10.254 --dport 51820 -j ACCEPT
ipt -A OUTPUT -p udp -s 192.168.10.254 -d 192.168.10.20 --dport 51821 -j ACCEPT

# Accept only the authenticated POS tunnel address on the payment listener.
ipt -A INPUT -i wg0 -p tcp -s 10.255.0.2 -d 10.255.0.1 --dport 443 \
  -m conntrack --ctstate NEW -j ACCEPT

# The perimeter may open only the DMZ TLS listener on its DMZ-facing network.
ipt -A OUTPUT -p tcp -s 10.0.10.1 -d 10.0.10.10 --dport 443 \
  -m conntrack --ctstate NEW -j ACCEPT

start_chrony_client
start_syslog_forwarder peri-fw
logger -t peri-fw "default-deny perimeter rules loaded; TLS passthrough enabled"

# TCP passthrough only. The firewall does not terminate or inspect TLS;
# payment.gateway TLS remains end-to-end between POS and DMZ Nginx.
exec socat \
  TCP4-LISTEN:443,bind=10.255.0.1,reuseaddr,fork,nodelay \
  TCP4:10.0.10.10:443,nodelay
