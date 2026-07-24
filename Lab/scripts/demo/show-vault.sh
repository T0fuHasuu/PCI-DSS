#!/usr/bin/env bash
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
set -euo pipefail

$DC exec -T kms sh -s <<'VAULT_SH'
set -eu

export VAULT_TOKEN="$(jq -r .root_token /vault/bootstrap/init.json)"

echo "[Vault status]"
vault status -format=json | jq '{
  initialized,
  sealed,
  version,
  storage_type,
  cluster_name
}'

echo
echo "[Transit key: payment-chd]"
vault read -format=json transit/keys/payment-chd | jq '{
  purpose: "Encrypt cardholder data before database storage",
  engine: "Vault Transit",
  key: "payment-chd",
  method: .data.type,
  latest_version: .data.latest_version,
  exportable: .data.exportable,
  allow_plaintext_backup: .data.allow_plaintext_backup,
  auto_rotate_period: .data.auto_rotate_period
}'

echo
echo "[Transit key: payment-token]"
vault read -format=json transit/keys/payment-token | jq '{
  purpose: "Derive opaque PAN token using HMAC",
  engine: "Vault Transit",
  key: "payment-token",
  method: .data.type,
  exportable: .data.exportable,
  allow_plaintext_backup: .data.allow_plaintext_backup
}'

echo
echo "[AppRole boundary]"
vault read -format=json auth/approle/role/payment-app | jq '{
  auth_method: "AppRole",
  role: "payment-app",
  token_type: .data.token_type,
  token_ttl: .data.token_ttl,
  token_max_ttl: .data.token_max_ttl,
  secret_id_ttl: .data.secret_id_ttl,
  token_bound_cidrs: .data.token_bound_cidrs,
  secret_id_bound_cidrs: .data.secret_id_bound_cidrs,
  policies: .data.token_policies
}'
VAULT_SH
