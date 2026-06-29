#!/bin/sh
set -eu

API_URL='https://payment.gateway'
DNS_SERVER='192.168.10.200'
EXPECTED_IP='10.255.0.1'
PAN='4111111111111111'
CVV='123'
PAYLOAD_FILE='/tmp/transaction.json'
RESPONSE_FILE='/tmp/transaction-response.json'
TX_ID_FILE='/tmp/last_tx_id'

cat > "$PAYLOAD_FILE" <<JSON
{
  "customer": {
    "full_name": "POS Lab Customer",
    "email": "pos-lab@example.com",
    "phone_number": "+85510000000"
  },
  "card": {
    "pan": "$PAN",
    "exp_month": 12,
    "exp_year": 2030,
    "cvv": "$CVV"
  },
  "amount": 25.50
}
JSON

CURL_COMMON='--show-error --silent --tlsv1.2 --tls-max 1.2 --cacert /etc/lab/pki/ca.crt --connect-timeout 5 --max-time 30'

echo '[1/4] Verify POS DNS'
# BusyBox nslookup may return nonzero when an IPv4-only name has no AAAA record.
# The authoritative A answer is the requirement for this IPv4-only lab.
set +e
DNS_OUTPUT="$(busybox nslookup payment.gateway "$DNS_SERVER" 2>&1)"
DNS_STATUS=$?
set -e
printf '%s\n' "$DNS_OUTPUT"
printf '%s\n' "$DNS_OUTPUT" | grep -Eq "(^|[[:space:]])${EXPECTED_IP}([[:space:]]|$)" || {
  echo "FAIL: payment.gateway did not resolve to $EXPECTED_IP (nslookup status=$DNS_STATUS)." >&2
  exit 1
}

echo '[2/4] Verify payment API health through WireGuard and TLS 1.2'
# shellcheck disable=SC2086
HEALTH="$(curl $CURL_COMMON --fail "$API_URL/health")"
printf '%s\n' "$HEALTH"
printf '%s\n' "$HEALTH" | grep -q '"status":"healthy"' || {
  echo 'FAIL: payment API is not healthy.' >&2
  exit 1
}

echo '[3/4] Submit test transaction from the POS container'
# Do not use curl --fail here: preserve the API response body for diagnostics.
# shellcheck disable=SC2086
HTTP_STATUS="$(curl $CURL_COMMON \
  --output "$RESPONSE_FILE" \
  --write-out '%{http_code}' \
  --header 'Content-Type: application/json' \
  --data-binary "@$PAYLOAD_FILE" \
  "$API_URL/process-transaction")"
cat "$RESPONSE_FILE"
echo

[ "$HTTP_STATUS" = "200" ] || {
  echo "FAIL: transaction API returned HTTP $HTTP_STATUS." >&2
  exit 1
}

TX_ID="$(sed -n 's/.*"tx_id":\([0-9][0-9]*\).*/\1/p' "$RESPONSE_FILE" | head -n 1)"
[ -n "$TX_ID" ] || {
  echo 'FAIL: API response did not contain tx_id.' >&2
  exit 1
}
printf '%s\n' "$TX_ID" > "$TX_ID_FILE"

echo '[4/4] POS transaction accepted'
echo "tx_id=$TX_ID"
