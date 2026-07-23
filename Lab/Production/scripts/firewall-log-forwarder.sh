#!/bin/sh
set -eu

start_firewall_log_forwarder() {
  service_name="${1:?firewall service name is required}"
  : "${LOG_SERVER:?LOG_SERVER is required}"

  for command_name in rsyslogd ulogd pgrep; do
    command -v "$command_name" >/dev/null 2>&1 || {
      echo "[$service_name] FATAL: $command_name is not installed" >&2
      exit 1
    }
  done

  for plugin in \
    /usr/lib/ulogd/ulogd_inppkt_NFLOG.so \
    /usr/lib/ulogd/ulogd_raw2packet_BASE.so \
    /usr/lib/ulogd/ulogd_filter_IFINDEX.so \
    /usr/lib/ulogd/ulogd_filter_IP2STR.so \
    /usr/lib/ulogd/ulogd_filter_PRINTPKT.so \
    /usr/lib/ulogd/ulogd_output_LOGEMU.so
  do
    test -r "$plugin" || {
      echo "[$service_name] FATAL: missing ulogd plugin $plugin" >&2
      exit 1
    }
  done

  mkdir -p /var/log /var/lib/rsyslog /run
  touch /var/log/firewall-events.log
  chmod 0640 /var/log/firewall-events.log

  cat > /tmp/rsyslog-firewall.conf <<EOF2
global(workDirectory="/var/lib/rsyslog")
module(load="imfile")
input(
  type="imfile"
  File="/var/log/firewall-events.log"
  Tag="${service_name}:"
  Facility="local4"
  Severity="notice"
  PersistStateInterval="1"
  reopenOnTruncate="on"
  addMetadata="off"
)
action(
  type="omfwd"
  Target="${LOG_SERVER}"
  Port="514"
  Protocol="udp"
  Template="RSYSLOG_SyslogProtocol23Format"
  action.resumeRetryCount="-1"
  queue.type="LinkedList"
  queue.size="1000"
)
EOF2

  rsyslogd -N1 -f /tmp/rsyslog-firewall.conf
  rsyslogd -n -i "/run/rsyslog-${service_name}.pid" -f /tmp/rsyslog-firewall.conf &
  RSYSLOG_FORWARDER_PID=$!

  ulogd -d -c /etc/ulogd.conf
  sleep 2

  kill -0 "$RSYSLOG_FORWARDER_PID" 2>/dev/null || {
    echo "[$service_name] FATAL: local rsyslog forwarder failed" >&2
    exit 1
  }
  pgrep -x ulogd >/dev/null || {
    echo "[$service_name] FATAL: ulogd failed to start" >&2
    cat /var/log/ulogd-status.log >&2 || true
    exit 1
  }

  echo "[$service_name] NFLOG group 2 and UDP syslog forwarding started"
}
