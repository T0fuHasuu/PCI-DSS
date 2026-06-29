#!/bin/sh
set -eu
. /usr/local/lib/lab/lib.sh


mkdir -p /vault/file /vault/bootstrap /vault/app-credentials /vault/tls
cp /etc/lab/pki/server.crt /vault/tls/server.crt
cp /etc/lab/pki/server.key /vault/tls/server.key
cp /etc/lab/pki/ca.crt /vault/tls/ca.crt
chown -R vault:vault /vault/file /vault/tls
chmod 0750 /vault/bootstrap /vault/app-credentials
chmod 0644 /vault/tls/server.crt /vault/tls/ca.crt
chmod 0600 /vault/tls/server.key

reset_firewall
allow_loopback_and_state
allow_infra_egress 10.100.20.10

# Vault accepts only the App's KMS-side address. Local bootstrap uses loopback.
ipt -A INPUT -p tcp -s 10.100.20.20 -d 10.100.20.10 --dport 8200 \
  -m conntrack --ctstate NEW -j ACCEPT

start_chrony_client
start_syslog_forwarder kms
logger -t kms "Vault TLS boundary starting"

rm -f /tmp/vault-operational.log.pipe
mkfifo /tmp/vault-operational.log.pipe
logger -t vault < /tmp/vault-operational.log.pipe &
VAULT_LOGGER_PID=$!

if command -v su-exec >/dev/null 2>&1; then
  su-exec vault:vault vault server -config=/vault/config/vault.hcl \
    > /tmp/vault-operational.log.pipe 2>&1 &
else
  vault server -config=/vault/config/vault.hcl \
    > /tmp/vault-operational.log.pipe 2>&1 &
fi
VAULT_PID=$!

cleanup() {
  kill "$VAULT_PID" "$VAULT_LOGGER_PID" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

# A non-2xx response still proves that the TLS listener is ready.
until curl --silent --show-error --output /dev/null \
  --cacert "$VAULT_CACERT" \
  --cert "$VAULT_CLIENT_CERT" \
  --key "$VAULT_CLIENT_KEY" \
  --resolve vault.internal:8200:127.0.0.1 \
  https://vault.internal:8200/v1/sys/health; do
  kill -0 "$VAULT_PID" 2>/dev/null || exit 1
  sleep 1
done

STATUS_JSON="$(vault status -format=json 2>/dev/null || true)"
if ! printf '%s' "$STATUS_JSON" | jq -e '.initialized == true' >/dev/null 2>&1; then
  umask 077
  vault operator init -key-shares=1 -key-threshold=1 -format=json \
    > /vault/bootstrap/init.json
  chmod 0600 /vault/bootstrap/init.json
  logger -t kms "Vault initialized for lab use"
fi

UNSEAL_KEY="$(jq -r '.unseal_keys_b64[0]' /vault/bootstrap/init.json)"
ROOT_TOKEN="$(jq -r '.root_token' /vault/bootstrap/init.json)"

STATUS_JSON="$(vault status -format=json 2>/dev/null || true)"
if printf '%s' "$STATUS_JSON" | jq -e '.sealed == true' >/dev/null 2>&1; then
  vault operator unseal "$UNSEAL_KEY" >/dev/null
  logger -t kms "Vault unsealed from the persistent lab bootstrap volume"
fi

export VAULT_TOKEN="$ROOT_TOKEN"

if ! vault secrets list -format=json | jq -e 'has("transit/")' >/dev/null; then
  vault secrets enable transit >/dev/null
fi

# Prevent callers from implicitly creating unknown encryption keys.
vault write transit/config/keys disable_upsert=true >/dev/null

if ! vault read transit/keys/payment-chd >/dev/null 2>&1; then
  vault write transit/keys/payment-chd \
    type=aes256-gcm96 \
    exportable=false \
    allow_plaintext_backup=false \
    auto_rotate_period=720h >/dev/null
fi

if ! vault read transit/keys/payment-token >/dev/null 2>&1; then
  vault write transit/keys/payment-token \
    type=hmac \
    exportable=false \
    allow_plaintext_backup=false >/dev/null
fi

vault policy write payment-app /vault/config/payment-app-policy.hcl >/dev/null

if ! vault auth list -format=json | jq -e 'has("approle/")' >/dev/null; then
  vault auth enable approle >/dev/null
fi

# Persistent SecretID is acceptable only for this self-contained lab.
vault write auth/approle/role/payment-app \
  token_policies=payment-app \
  token_type=batch \
  token_ttl=15m \
  token_max_ttl=30m \
  token_num_uses=0 \
  secret_id_ttl=0 \
  secret_id_num_uses=0 \
  secret_id_bound_cidrs=10.100.20.20/32 \
  token_bound_cidrs=10.100.20.20/32 >/dev/null

if [ ! -s /vault/app-credentials/role_id ]; then
  vault read -field=role_id auth/approle/role/payment-app/role-id \
    > /vault/app-credentials/role_id
fi
if [ ! -s /vault/app-credentials/secret_id ]; then
  vault write -field=secret_id -f auth/approle/role/payment-app/secret-id \
    > /vault/app-credentials/secret_id
fi
chmod 0640 /vault/app-credentials/role_id /vault/app-credentials/secret_id

if ! vault audit list -format=json | jq -e 'has("socket/")' >/dev/null; then
  vault audit enable socket \
    address=10.100.20.200:514 \
    socket_type=udp \
    write_timeout=2s >/dev/null
fi

logger -t kms "Vault Transit, AppRole, and UDP audit forwarding configured"
unset VAULT_TOKEN ROOT_TOKEN UNSEAL_KEY

wait "$VAULT_PID"
