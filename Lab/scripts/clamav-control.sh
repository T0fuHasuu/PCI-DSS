#!/bin/sh
set -eu

LOG_SERVER="${LOG_SERVER:-172.31.10.200}"
FRESHCLAM_INTERVAL_SECONDS="${FRESHCLAM_INTERVAL_SECONDS:-43200}"
SCAN_INTERVAL_SECONDS="${SCAN_INTERVAL_SECONDS:-86400}"
INITIAL_UPDATE_DELAY_SECONDS="${INITIAL_UPDATE_DELAY_SECONDS:-60}"
DATABASE_DIR=/var/lib/clamav
LOG_DIR=/var/log/clamav
TEST_DIR=/var/lib/clamav-test

mkdir -p "$DATABASE_DIR" "$LOG_DIR" "$TEST_DIR" /run/antimalware
cp -f /opt/clamav/eicar.ndb "$DATABASE_DIR/eicar.ndb"
chown clamav:clamav "$DATABASE_DIR" "$DATABASE_DIR/eicar.ndb" 2>/dev/null || true
chmod 0750 "$LOG_DIR" "$TEST_DIR"

send_event() {
  message="$1"
  timestamp="$(date '+%b %d %H:%M:%S')"
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$message" >> "$LOG_DIR/events.log"
  printf '<134>%s %s antimalware: %s\n' "$timestamp" "$(hostname)" "$message" \
    | nc -u -w 1 "$LOG_SERVER" 514 >/dev/null 2>&1 || true
}

update_signatures() {
  if freshclam --config-file=/etc/clamav/freshclam.conf --stdout >> "$LOG_DIR/freshclam.log" 2>&1; then
    send_event 'CLAMAV_UPDATE status=SUCCESS source=official-database'
  else
    send_event 'CLAMAV_UPDATE status=DEGRADED source=fallback-eicar-signature'
  fi
  cp -f /opt/clamav/eicar.ndb "$DATABASE_DIR/eicar.ndb"
}

scan_repository() {
  output="$LOG_DIR/repository-scan.log"
  set +e
  nice -n 10 clamscan \
    --recursive \
    --infected \
    --no-summary \
    --exclude-dir='^/scan/configs/av$' \
    /scan > "$output" 2>&1
  result=$?
  set -e

  case "$result" in
    0) send_event 'CLAMAV_SCAN status=CLEAN target=repository-files mode=scheduled' ;;
    1) send_event 'CLAMAV_SCAN status=DETECTED target=repository-files mode=scheduled' ;;
    *) send_event "CLAMAV_SCAN status=ERROR target=repository-files code=$result" ;;
  esac
}

run_eicar_test() {
  test_file="$TEST_DIR/eicar.com"
  printf '%s%s' 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-' 'STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > "$test_file"
  set +e
  nice -n 10 clamscan --infected --no-summary "$test_file"
  result=$?
  set -e
  rm -f "$test_file"

  if [ "$result" -eq 1 ]; then
    send_event 'CLAMAV_EICAR status=DETECTED action=QUARANTINE_TEST_FILE result=PASS'
    echo 'EICAR detection: PASS'
    return 0
  fi

  send_event "CLAMAV_EICAR status=NOT_DETECTED result=FAIL code=$result"
  echo 'EICAR detection: FAIL' >&2
  return 1
}

show_status() {
  clamscan --version
  echo
  echo 'Signature files:'
  for file in "$DATABASE_DIR"/*; do [ -f "$file" ] && basename "$file"; done | sort
  echo
  echo 'Recent events:'
  tail -n 10 "$LOG_DIR/events.log" 2>/dev/null || true
}

run_update_loop() {
  sleep "$INITIAL_UPDATE_DELAY_SECONDS"
  while :; do
    update_signatures
    sleep "$FRESHCLAM_INTERVAL_SECONDS"
  done
}

run_scan_loop() {
  while :; do
    sleep "$SCAN_INTERVAL_SECONDS"
    scan_repository
  done
}

case "${1:-daemon}" in
  daemon)
    touch /run/antimalware/ready
    send_event 'CLAMAV_SERVICE status=READY mode=on-demand-and-scheduled'
    run_update_loop &
    update_pid=$!
    run_scan_loop &
    scan_pid=$!
    trap 'kill "$update_pid" "$scan_pid" 2>/dev/null || true; wait "$update_pid" "$scan_pid" 2>/dev/null || true' INT TERM EXIT
    wait "$update_pid" "$scan_pid"
    ;;
  update) update_signatures ;;
  scan) scan_repository ;;
  eicar) run_eicar_test ;;
  status) show_status ;;
  *)
    echo 'Usage: clamav-control.sh {daemon|update|scan|eicar|status}' >&2
    exit 2
    ;;
esac
