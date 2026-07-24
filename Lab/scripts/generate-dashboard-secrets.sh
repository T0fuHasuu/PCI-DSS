#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/secrets/pki"
CA_CERT="$OUT/ca/ca.crt"
CA_KEY="$OUT/ca/ca.key"
TMP="$ROOT/secrets/.dashboard-tmp"

if [[ ! -s "$CA_CERT" || ! -s "$CA_KEY" ]]; then
  echo "Existing lab CA was not found. Run scripts/generate-lab-secrets.sh first." >&2
  exit 1
fi

umask 077
rm -rf "$TMP" "$OUT/demo-ui" "$OUT/demo-api" "$OUT/pos-agent"
mkdir -p "$TMP" "$OUT/demo-ui" "$OUT/demo-api" "$OUT/pos-agent"

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
    -in "$csr" -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
    -extfile "$ext" -out "$crt"

  cp "$key" "$target.key"
  cp "$crt" "$target.crt"
  chmod 0600 "$target.key"
  chmod 0644 "$target.crt"
}

issue_cert dashboard-ui-server pci-demo.local serverAuth \
  "DNS:pci-demo.local,DNS:localhost,IP:127.0.0.1,IP:172.30.10.10" \
  "$OUT/demo-ui/server"
issue_cert dashboard-ui-client demo-ui-proxy clientAuth "" "$OUT/demo-ui/client"

issue_cert dashboard-api-server demo-api.internal serverAuth \
  "DNS:demo-api.internal,IP:172.30.10.20,IP:127.0.0.1" \
  "$OUT/demo-api/server"
issue_cert dashboard-api-client demo-api-controller clientAuth "" "$OUT/demo-api/client"

issue_cert pos-agent-server pos-agent.internal serverAuth \
  "DNS:pos-agent.internal,IP:192.168.10.20,IP:127.0.0.1" \
  "$OUT/pos-agent/server"

for service in demo-ui demo-api pos-agent; do
  cp "$CA_CERT" "$OUT/$service/ca.crt"
  chmod 0644 "$OUT/$service/ca.crt"
done

rm -rf "$TMP" "$OUT/ca/ca.srl"
echo "Generated dashboard certificates under: $OUT"
