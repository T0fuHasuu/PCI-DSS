#!/bin/sh
set -eu
. /usr/local/lib/lab/lib.sh
. /usr/local/lib/lab/firewall-log-forwarder.sh

wg-quick up /etc/wireguard/wg0.conf
start_firewall_log_forwarder peri-fw

reset_firewall
allow_loopback_and_state
allow_infra_egress 10.0.10.1

# WireGuard transport. Keepalive packets are allowed but not logged.
ipt -A INPUT  -p udp -s 192.168.10.20 -d 192.168.10.254 --dport 51820 -j ACCEPT
ipt -A OUTPUT -p udp -s 192.168.10.254 -d 192.168.10.20 --dport 51821 -j ACCEPT

# Log one record for a new permitted payment connection, then accept it.
ipt -A INPUT -i wg0 -p tcp -s 10.255.0.2 -d 10.255.0.1 --dport 443 \
  -m conntrack --ctstate NEW \
  -m limit --limit 30/minute --limit-burst 20 \
  -j NFLOG --nflog-group 2 --nflog-threshold 1 \
  --nflog-prefix "PERI_FW_ALLOW action=ALLOW service=payment-gateway "
ipt -A INPUT -i wg0 -p tcp -s 10.255.0.2 -d 10.255.0.1 --dport 443 \
  -m conntrack --ctstate NEW -j ACCEPT

# The perimeter proxy may initiate only the DMZ TLS connection.
ipt -A OUTPUT -p tcp -s 10.0.10.1 -d 10.0.10.10 --dport 443 \
  -m conntrack --ctstate NEW -j ACCEPT

# Log only new denied attempts and rate-limit the log action, not the drop itself.
ipt -A INPUT -m conntrack --ctstate NEW \
  -m limit --limit 12/minute --limit-burst 6 \
  -j NFLOG --nflog-group 2 --nflog-threshold 1 \
  --nflog-prefix "PERI_FW_DROP action=DROP service=default-deny "
ipt -A INPUT -j DROP

start_chrony_client
logger -t peri-fw "perimeter firewall started with rate-limited NFLOG forwarding"

# TLS passthrough only. TLS still terminates at the DMZ.
exec socat \
  TCP4-LISTEN:443,bind=10.255.0.1,reuseaddr,fork,nodelay \
  TCP4:10.0.10.10:443,nodelay
