#!/bin/sh

ipt() {
  iptables -w 5 "$@"
}

reset_firewall() {
  ipt -F
  ipt -X
  ipt -t nat -F
  ipt -t nat -X 2>/dev/null || true
  ipt -P INPUT DROP
  ipt -P FORWARD DROP
  ipt -P OUTPUT DROP
}

allow_loopback_and_state() {
  ipt -A INPUT -i lo -j ACCEPT
  ipt -A OUTPUT -o lo -j ACCEPT
  ipt -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  ipt -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
}

allow_infra_egress() {
  src_ip="$1"
  infra_ip="${LOG_SERVER:?LOG_SERVER is required}"

  # Centralized log forwarding: UDP only.
  ipt -A OUTPUT -p udp -s "$src_ip" -d "$infra_ip" --dport 514 -j ACCEPT

  # DNS is provided by the combined log/DNS/NTP infrastructure container.
  ipt -A OUTPUT -p udp -s "$src_ip" -d "$infra_ip" --dport 53 -j ACCEPT
  ipt -A OUTPUT -p tcp -s "$src_ip" -d "$infra_ip" --dport 53 \
    -m conntrack --ctstate NEW -j ACCEPT

  # NTP is UDP only.
  ipt -A OUTPUT -p udp -s "$src_ip" -d "${NTP_SERVER:?NTP_SERVER is required}" --dport 123 -j ACCEPT
}

start_chrony_client() {
  mkdir -p /run/chrony /var/lib/chrony /tmp/chrony
  cat > /tmp/chrony-client.conf <<CHRONY
server ${NTP_SERVER:?NTP_SERVER is required} iburst minpoll 4 maxpoll 6
pidfile /run/chrony/chronyd.pid
driftfile /var/lib/chrony/drift
logdir /tmp/chrony
bindcmdaddress 127.0.0.1
CHRONY
  chronyd -x -f /tmp/chrony-client.conf >/tmp/chronyd.log 2>&1 &
}

start_syslog_forwarder() {
  tag="$1"
  mkdir -p /tmp
  # BusyBox syslogd receives local /dev/log messages and forwards only by UDP.
  syslogd -R "${LOG_SERVER:?LOG_SERVER is required}:514" -L -O /tmp/local-messages
  logger -t "$tag" "central UDP logging initialized"
}
