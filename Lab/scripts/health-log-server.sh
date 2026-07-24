#!/bin/sh
set -eu

PID_FILE="${RSYSLOG_PID_FILE:-/run/rsyslogd.pid}"
UDP_TABLE="${PROC_UDP_FILE:-/proc/net/udp}"
LOG_DIR="${LOG_DIR:-/var/log/remote}"

test -s "$PID_FILE"
RSYSLOG_PID="$(cat "$PID_FILE")"
kill -0 "$RSYSLOG_PID" 2>/dev/null

# Verify the real listeners rather than relying on process-name matching.
# 0035 = UDP/53, 007B = UDP/123, 0202 = UDP/514.
grep -qi ':0035 ' "$UDP_TABLE"
grep -qi ':007B ' "$UDP_TABLE"
grep -qi ':0202 ' "$UDP_TABLE"

test -f "$LOG_DIR/perimeter-firewall.log"
test -f "$LOG_DIR/internal-firewall.log"
test -f "$LOG_DIR/cde-transactions.log"
test -f "$LOG_DIR/antimalware.log"
test -f "$LOG_DIR/other.log"
