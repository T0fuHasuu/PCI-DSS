#!/bin/sh
set -eu
. /usr/local/lib/lab/lib.sh

mkdir -p /var/log/remote /run/rsyslog /run/chrony /var/lib/chrony

reset_firewall
allow_loopback_and_state

# Central logging accepts UDP 514 only from known crucial components.
for source in \
  192.168.10.20 \
  10.0.10.1 10.0.10.10 \
  10.100.10.1 10.100.10.10 \
  10.100.20.10 \
  10.100.30.10; do
  ipt -A INPUT -p udp -s "$source" --dport 514 -j ACCEPT
done

# DNS and NTP are built into this same infrastructure endpoint.
for subnet in \
  192.168.10.0/24 \
  10.0.10.0/24 \
  10.100.10.0/24 \
  10.100.20.0/24 \
  10.100.30.0/24; do
  ipt -A INPUT -p udp -s "$subnet" --dport 53 -j ACCEPT
  ipt -A INPUT -p tcp -s "$subnet" --dport 53 -m conntrack --ctstate NEW -j ACCEPT
  ipt -A INPUT -p udp -s "$subnet" --dport 123 -j ACCEPT
done

rsyslogd -n -f /etc/rsyslog.conf &
RSYSLOG_PID=$!
dnsmasq --keep-in-foreground --conf-file=/etc/dnsmasq.conf &
DNS_PID=$!
chronyd -x -d -f /etc/chrony/chrony.conf &
NTP_PID=$!

stop_all() {
  kill "$RSYSLOG_PID" "$DNS_PID" "$NTP_PID" 2>/dev/null || true
}
trap stop_all INT TERM EXIT

while :; do
  kill -0 "$RSYSLOG_PID" "$DNS_PID" "$NTP_PID" 2>/dev/null || exit 1
  sleep 5
done
