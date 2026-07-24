#!/usr/bin/env bash
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
set -euo pipefail

$DC exec -T db sh -lc 'psql -U cde_admin -d cde_db -P pager=off -c "
SELECT
  tx_id,
  tx_amount AS amount,
  authorization_status AS status,
  masked_pan,
  left(card_token, 28) || '\''...'\'' AS card_token,
  left(encrypted_chd, 48) || '\''...'\'' AS encrypted_chd,
  vault_key_version AS key_ver,
  to_char(tx_timestamp, '\''YYYY-MM-DD HH24:MI:SS'\'') AS created_at
FROM transactions
ORDER BY tx_id DESC
LIMIT 5;"'
