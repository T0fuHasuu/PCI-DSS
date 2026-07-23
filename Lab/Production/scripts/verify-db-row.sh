#!/bin/sh
set -eu

TX_ID="${1:?Usage: verify-db-row.sh TX_ID}"
EXPECTED_PAN='4111111111111111'
EXPECTED_MASK='************1111'

ROW="$(psql -U cde_admin -d cde_db -v ON_ERROR_STOP=1 -At -F '|' -c "
SELECT authorization_status,
       masked_pan,
       card_token,
       encrypted_chd,
       vault_key_version,
       tx_amount::text
FROM transactions
WHERE tx_id = ${TX_ID};
")"

[ -n "$ROW" ] || {
  echo "FAIL: transaction $TX_ID was not found in PostgreSQL." >&2
  exit 1
}

IFS='|' read -r STATUS MASKED TOKEN CIPHERTEXT KEY_VERSION AMOUNT <<ROWEOF
$ROW
ROWEOF

[ "$STATUS" = 'approved' ] || {
  echo "FAIL: unexpected authorization status: $STATUS" >&2
  exit 1
}
[ "$MASKED" = "$EXPECTED_MASK" ] || {
  echo "FAIL: PAN masking is incorrect: $MASKED" >&2
  exit 1
}
printf '%s' "$TOKEN" | grep -Eq '^tok_[0-9a-f]{32}$' || {
  echo "FAIL: card token format is invalid: $TOKEN" >&2
  exit 1
}
printf '%s' "$CIPHERTEXT" | grep -Eq '^vault:v[0-9]+:' || {
  echo 'FAIL: encrypted_chd is not Vault Transit ciphertext.' >&2
  exit 1
}
case "$MASKED$TOKEN$CIPHERTEXT" in
  *"$EXPECTED_PAN"*)
    echo 'FAIL: raw PAN was found in a persisted transaction field.' >&2
    exit 1
    ;;
esac
case "$KEY_VERSION" in
  ''|*[!0-9]*|0)
    echo "FAIL: invalid Vault key version: $KEY_VERSION" >&2
    exit 1
    ;;
esac

SAD_COLUMNS="$(psql -U cde_admin -d cde_db -At -c "
SELECT count(*)
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'transactions'
  AND lower(column_name) IN ('cvv', 'cvc', 'cid', 'security_code');
")"
[ "$SAD_COLUMNS" = '0' ] || {
  echo 'FAIL: the transactions table contains a SAD/CVV column.' >&2
  exit 1
}

printf '%s\n' "$CIPHERTEXT" > /tmp/last-ciphertext.txt

echo 'Database verification: PASS'
echo "tx_id=$TX_ID"
echo "authorization_status=$STATUS"
echo "amount=$AMOUNT"
echo "masked_pan=$MASKED"
echo "card_token=$TOKEN"
printf 'encrypted_chd_prefix=%.80s\n' "$CIPHERTEXT"
echo "vault_key_version=$KEY_VERSION"
echo 'cvv_column_present=false'
