#!/bin/sh
set -eu

mkdir -p /var/log/remote /var/lib/rsyslog /run/chrony
chmod 0750 /var/log/remote
chown chrony:chrony /run/chrony 2>/dev/null || true
chmod 0750 /run/chrony 2>/dev/null || true

for file in \
  /var/log/remote/perimeter-firewall.log \
  /var/log/remote/internal-firewall.log \
  /var/log/remote/cde-transactions.log \
  /var/log/remote/other.log
do
  touch "$file"
  chmod 0640 "$file"
done

# Fail immediately on invalid receiver configuration.
rsyslogd -N1 -f /etc/rsyslog.conf

iptables -F
iptables -X
iptables -t nat -F
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Permit only lab networks attached to this existing multi-homed service.
for subnet in \
  192.168.10.0/24 \
  10.0.10.0/24 \
  10.100.10.0/24 \
  10.100.20.0/24 \
  10.100.30.0/24
do
  iptables -A INPUT -s "$subnet" -p udp --dport 53 -j ACCEPT
  iptables -A INPUT -s "$subnet" -p tcp --dport 53 -j ACCEPT
  iptables -A INPUT -s "$subnet" -p udp --dport 123 -j ACCEPT
  iptables -A INPUT -s "$subnet" -p udp --dport 514 -j ACCEPT
done

rsyslogd -n -i /run/rsyslogd.pid -f /etc/rsyslog.conf &
RSYSLOG_PID=$!
dnsmasq --keep-in-foreground --conf-file=/etc/dnsmasq.conf &
DNS_PID=$!
chronyd -d -x -f /etc/chrony/chrony.conf &
CHRONY_PID=$!

cleanup() {
  kill "$RSYSLOG_PID" "$DNS_PID" "$CHRONY_PID" 2>/dev/null || true
  wait "$RSYSLOG_PID" "$DNS_PID" "$CHRONY_PID" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

sleep 2
for pid in "$RSYSLOG_PID" "$DNS_PID" "$CHRONY_PID"; do
  kill -0 "$pid" 2>/dev/null || {
    echo "[log-server] required infrastructure process failed during startup" >&2
    exit 1
  }
done

echo "[log-server] DNS, NTP, and UDP syslog receiver started"

while :; do
  for pid in "$RSYSLOG_PID" "$DNS_PID" "$CHRONY_PID"; do
    kill -0 "$pid" 2>/dev/null || {
      echo "[log-server] required infrastructure process exited" >&2
      exit 1
    }
  done
  sleep 2
done
