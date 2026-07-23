#!/bin/sh
set -eu

CA=/etc/lab/pki/ca.crt
BASE=https://payment.gateway
CURL="curl --silent --show-error --tlsv1.2 --tls-max 1.2 --cacert $CA --connect-timeout 5 --max-time 30"

printf '%s\n' '[1] Permitted perimeter connection'
# shellcheck disable=SC2086
$CURL --fail "$BASE/health" >/tmp/log-test-health.json
cat /tmp/log-test-health.json

printf '%s\n' '[2] Dropped perimeter connection'
iptables -I OUTPUT 1 -o wg0 -p tcp -d 10.255.0.1 --dport 9443 -j ACCEPT
busybox nc -z -w 2 10.255.0.1 9443 >/dev/null 2>&1 || true
iptables -D OUTPUT -o wg0 -p tcp -d 10.255.0.1 --dport 9443 -j ACCEPT

cat >/tmp/log-success.json <<'JSON'
{
  "customer": {
    "full_name": "Central Logging Test",
    "email": "central-logging@example.com",
    "phone_number": "+85510000000"
  },
  "card": {
    "pan": "4111111111111111",
    "exp_month": 12,
    "exp_year": 2030,
    "cvv": "123"
  },
  "amount": 25.50
}
JSON

printf '%s\n' '[3] Successful CDE transaction'
# shellcheck disable=SC2086
$CURL --fail -H 'Content-Type: application/json' --data-binary @/tmp/log-success.json \
  "$BASE/process-transaction" >/tmp/log-success.out
cat /tmp/log-success.out

cat >/tmp/log-decline.json <<'JSON'
{
  "customer": {
    "full_name": "Declined Logging Test",
    "email": "declined-logging@example.com",
    "phone_number": "+85510000001"
  },
  "card": {
    "pan": "4111111111111111",
    "exp_month": 12,
    "exp_year": 2030,
    "cvv": "123"
  },
  "amount": 0
}
JSON

printf '%s\n' '[4] Declined CDE transaction through validation failure'
# shellcheck disable=SC2086
status="$($CURL -o /tmp/log-decline.out -w '%{http_code}' -H 'Content-Type: application/json' \
  --data-binary @/tmp/log-decline.json "$BASE/process-transaction" || true)"
cat /tmp/log-decline.out
printf '\nHTTP status=%s\n' "$status"
[ "$status" = "422" ] || {
  echo "Expected HTTP 422 for the declined test, got $status" >&2
  exit 1
}
