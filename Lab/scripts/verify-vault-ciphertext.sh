#!/bin/sh
set -eu

CIPHERTEXT_FILE="${1:-/tmp/last-ciphertext.txt}"
EXPECTED_PAN='4111111111111111'

[ -s "$CIPHERTEXT_FILE" ] || {
  echo "FAIL: ciphertext file is missing: $CIPHERTEXT_FILE" >&2
  exit 1
}

CIPHERTEXT="$(tr -d '\r\n' < "$CIPHERTEXT_FILE")"
ROOT_TOKEN="$(jq -er '.root_token' /vault/bootstrap/init.json)"
export VAULT_TOKEN="$ROOT_TOKEN"

DECRYPT_JSON="$(vault write -format=json transit/decrypt/payment-chd ciphertext="$CIPHERTEXT")"
PLAINTEXT_B64="$(printf '%s' "$DECRYPT_JSON" | jq -er '.data.plaintext')"
PLAINTEXT="$(printf '%s' "$PLAINTEXT_B64" | base64 -d)"

printf '%s' "$PLAINTEXT" | jq -e --arg pan "$EXPECTED_PAN" '
  (.pan == $pan) and
  (.exp_month == 12) and
  (.exp_year == 2030) and
  (has("cvv") | not) and
  (has("cvc") | not)
' >/dev/null || {
  echo 'FAIL: decrypted CHD did not match the expected PAN/expiry or contained SAD.' >&2
  exit 1
}

unset VAULT_TOKEN ROOT_TOKEN PLAINTEXT_B64

echo 'Vault decryption verification: PASS'
echo "decrypted_chd=$PLAINTEXT"
echo 'cvv_present=false'
