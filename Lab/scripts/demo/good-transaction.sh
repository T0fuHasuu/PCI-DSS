#!/usr/bin/env bash
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
set -euo pipefail

$DC exec -T pos-agent python - <<'PY'
import httpx, json
payload = {
    "customer": {"full_name": "POS Demo Customer", "email": "pos-demo@example.com", "phone_number": "+85510000000"},
    "card": {"pan": "4111111111111111", "exp_month": 12, "exp_year": 2030, "cvv": "123"},
    "amount": "25.50",
}
with httpx.Client(base_url="https://payment.gateway", verify="/etc/lab/pki/ca.crt", timeout=30.0, trust_env=False) as client:
    health = client.get("/health")
    tx = client.post("/process-transaction", json=payload)
print("health_status=", health.status_code, health.text)
print("transaction_status=", tx.status_code)
print(tx.text)
if tx.status_code == 200:
    data = tx.json()
    print(f"tx_id={data['tx_id']}")
PY
