#!/bin/sh
set -eu
. /usr/local/lib/lab/lib.sh

# Docker's embedded resolver did not reliably forward this isolated lab zone on
# Docker Desktop. Point the POS directly at the combined DNS/NTP/log server.
cat > /etc/resolv.conf <<RESOLV
nameserver ${LOG_SERVER:?LOG_SERVER is required}
search lab.internal
options ndots:1 timeout:2 attempts:3
RESOLV

wg-quick up /etc/wireguard/wg0.conf

# Export only the non-secret tunnel evidence needed by the POS agent. This
# avoids granting NET_ADMIN to the application container that shares this
# network namespace.
mkdir -p /run/pos-status
chmod 0750 /run/pos-status
write_wireguard_status() {
  umask 027
  for field in latest-handshakes endpoints transfer; do
    tmp="/run/pos-status/${field}.tmp"
    wg show wg0 "$field" > "$tmp"
    mv "$tmp" "/run/pos-status/${field}"
  done
}
write_wireguard_status
(
  while sleep 5; do
    write_wireguard_status || true
  done
) &

reset_firewall
allow_loopback_and_state
allow_infra_egress 192.168.10.20

# Outer WireGuard transport. No plaintext application traffic is allowed on store_net.
ipt -A OUTPUT -p udp -s 192.168.10.20 -d 192.168.10.254 --sport 51821 --dport 51820 -j ACCEPT
ipt -A INPUT  -p udp -s 192.168.10.254 -d 192.168.10.20 --sport 51820 --dport 51821 -j ACCEPT

# The payment API is reachable only through the authenticated VPN interface.
ipt -A OUTPUT -o wg0 -p tcp -s 10.255.0.2 -d 10.255.0.1 --dport 443 \
  -m conntrack --ctstate NEW -j ACCEPT

# The simulation controller may reach only the POS agent HTTPS listener.
# Card data on this control hop is protected with TLS 1.2 and mutual certificates.
ipt -A INPUT -p tcp -s 192.168.10.30 -d 192.168.10.20 --dport 9444 \
  -m conntrack --ctstate NEW -j ACCEPT

start_chrony_client
start_syslog_forwarder pos
logger -t pos "WireGuard POS endpoint started with lab DNS ${LOG_SERVER}"

exec sleep infinity
