#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/secrets"
STAGE="$OUT/.lab-pki-stage"
TMP="$STAGE/.tmp"

umask 077
rm -rf "$STAGE"
mkdir -p "$TMP" \
  "$STAGE/pki/ca" "$STAGE/pki/pos" "$STAGE/pki/dmz" "$STAGE/pki/app" \
  "$STAGE/pki/kms" "$STAGE/pki/db" \
  "$STAGE/wireguard/pos" "$STAGE/wireguard/peri-fw"

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 \
  -out "$STAGE/pki/ca/ca.key"
openssl req -x509 -new -sha256 -days 3650 \
  -key "$STAGE/pki/ca/ca.key" \
  -subj "/C=KH/O=PCI Segmentation Lab/CN=PCI Lab Root CA" \
  -out "$STAGE/pki/ca/ca.crt"

issue_cert() {
  local filename="$1"
  local cn="$2"
  local eku="$3"
  local san="$4"
  local target="$5"
  local key="$TMP/${filename}.key"
  local csr="$TMP/${filename}.csr"
  local crt="$TMP/${filename}.crt"
  local ext="$TMP/${filename}.ext"

  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$key"
  openssl req -new -sha256 -key "$key" \
    -subj "/C=KH/O=PCI Segmentation Lab/CN=${cn}" -out "$csr"

  {
    echo "basicConstraints=critical,CA:FALSE"
    echo "keyUsage=critical,digitalSignature,keyEncipherment"
    echo "extendedKeyUsage=${eku}"
    echo "subjectKeyIdentifier=hash"
    echo "authorityKeyIdentifier=keyid,issuer"
    [[ -n "$san" ]] && echo "subjectAltName=${san}"
  } > "$ext"

  openssl x509 -req -sha256 -days 825 \
    -in "$csr" \
    -CA "$STAGE/pki/ca/ca.crt" \
    -CAkey "$STAGE/pki/ca/ca.key" \
    -CAcreateserial \
    -extfile "$ext" \
    -out "$crt"

  cp "$key" "$target.key"
  cp "$crt" "$target.crt"
  chmod 0600 "$target.key"
  chmod 0644 "$target.crt"
}

issue_cert dmz-server payment.gateway serverAuth \
  "DNS:payment.gateway,IP:10.0.10.10,IP:10.255.0.1" \
  "$STAGE/pki/dmz/server"
issue_cert dmz-client dmz-proxy clientAuth "" "$STAGE/pki/dmz/client"

issue_cert app-server app.internal serverAuth \
  "DNS:app.internal,IP:10.100.10.10,IP:127.0.0.1" \
  "$STAGE/pki/app/server"
issue_cert app-vault-client payment-app clientAuth "" "$STAGE/pki/app/vault-client"
issue_cert app-db-client cde_user clientAuth "" "$STAGE/pki/app/db-client"
issue_cert app-health-client app-healthcheck clientAuth "" "$STAGE/pki/app/health-client"

issue_cert vault-server vault.internal serverAuth \
  "DNS:vault.internal,IP:10.100.20.10,IP:127.0.0.1" \
  "$STAGE/pki/kms/server"
issue_cert vault-admin-client vault-bootstrap clientAuth "" "$STAGE/pki/kms/admin-client"

issue_cert db-server db.internal serverAuth \
  "DNS:db.internal,IP:10.100.30.10" \
  "$STAGE/pki/db/server"

for service in pos dmz app kms db; do
  cp "$STAGE/pki/ca/ca.crt" "$STAGE/pki/$service/ca.crt"
  chmod 0644 "$STAGE/pki/$service/ca.crt"
done

wg_pair() {
  local dir="$1"
  if command -v wg >/dev/null 2>&1; then
    wg genkey > "$dir/private.key"
    wg pubkey < "$dir/private.key" > "$dir/public.key"
  else
    local pem="$TMP/$(basename "$dir")-wg.pem"
    openssl genpkey -algorithm X25519 -out "$pem"
    openssl pkey -in "$pem" -outform DER \
      | tail -c 32 \
      | openssl base64 -A > "$dir/private.key"
    printf '\n' >> "$dir/private.key"
    openssl pkey -in "$pem" -pubout -outform DER \
      | tail -c 32 \
      | openssl base64 -A > "$dir/public.key"
    printf '\n' >> "$dir/public.key"
  fi
  chmod 0600 "$dir/private.key"
  chmod 0644 "$dir/public.key"
}

wg_pair "$STAGE/wireguard/pos"
wg_pair "$STAGE/wireguard/peri-fw"

POS_PRIVATE="$(tr -d '\n' < "$STAGE/wireguard/pos/private.key")"
POS_PUBLIC="$(tr -d '\n' < "$STAGE/wireguard/pos/public.key")"
PERI_PRIVATE="$(tr -d '\n' < "$STAGE/wireguard/peri-fw/private.key")"
PERI_PUBLIC="$(tr -d '\n' < "$STAGE/wireguard/peri-fw/public.key")"

cat > "$STAGE/wireguard/peri-fw/wg0.conf" <<WGEOF
[Interface]
Address = 10.255.0.1/24
ListenPort = 51820
PrivateKey = ${PERI_PRIVATE}

[Peer]
PublicKey = ${POS_PUBLIC}
AllowedIPs = 10.255.0.2/32
WGEOF

cat > "$STAGE/wireguard/pos/wg0.conf" <<WGEOF
[Interface]
Address = 10.255.0.2/24
ListenPort = 51821
PrivateKey = ${POS_PRIVATE}

[Peer]
PublicKey = ${PERI_PUBLIC}
Endpoint = 192.168.10.254:51820
AllowedIPs = 10.255.0.1/32
PersistentKeepalive = 25
WGEOF

chmod 0600 "$STAGE/wireguard/pos/wg0.conf" "$STAGE/wireguard/peri-fw/wg0.conf"
rm -rf "$TMP" "$STAGE/pki/ca/ca.srl"

# Copy into existing bind-mounted directories instead of deleting those
# directories. This avoids stale/empty mounts on Docker Desktop.
install_dir() {
  local source="$1"
  local destination="$2"
  mkdir -p "$destination"
  find "$destination" -mindepth 1 -maxdepth 1 -type f -delete
  cp -a "$source/." "$destination/"
}

mkdir -p "$OUT/pki" "$OUT/wireguard"
for service in ca pos dmz app kms db; do
  install_dir "$STAGE/pki/$service" "$OUT/pki/$service"
done
for service in pos peri-fw; do
  install_dir "$STAGE/wireguard/$service" "$OUT/wireguard/$service"
done
touch "$OUT/.gitkeep"
rm -rf "$STAGE"

echo "Generated base PKI and WireGuard material under: $OUT"

# A new CA invalidates dashboard certificates. Regenerate them automatically
# when the dashboard extension is installed in this same project.
if [[ -f "$ROOT/scripts/generate-dashboard-secrets.sh" ]]; then
  echo "Dashboard extension detected; generating dashboard certificates with the new CA."
  bash "$ROOT/scripts/generate-dashboard-secrets.sh"
fi
