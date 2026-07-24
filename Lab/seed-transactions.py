#!/usr/bin/env python3
import base64
import json
import subprocess
import sys
from pathlib import Path

TRANSACTION_FILE = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("transactions.json")

INNER_POS_SCRIPT = r'''
import base64
import json
import os
import sys
import httpx

tx = json.loads(base64.b64decode(os.environ["TX_B64"]).decode())

payload = {
    "customer": {
        "full_name": tx["fullname"],
        "email": tx["email"],
        "phone_number": tx["phone_number"],
    },
    "card": {
        "pan": tx["card_num"],
        "exp_month": int(tx["exp_month"]),
        "exp_year": int(tx["exp_year"]),
        "cvv": str(tx["cvv"]),
    },
    "amount": str(tx["amount"]),
}

try:
    with httpx.Client(
        base_url="https://payment.gateway",
        verify="/etc/lab/pki/ca.crt",
        timeout=30.0,
        trust_env=False,
    ) as client:
        response = client.post("/process-transaction", json=payload)

    try:
        body = response.json()
    except Exception:
        body = {"raw": response.text}

    print(json.dumps({
        "http_status": response.status_code,
        "fullname": tx["fullname"],
        "amount": tx["amount"],
        "tx_id": body.get("tx_id"),
        "authorization_status": body.get("authorization_status"),
        "masked_pan": body.get("masked_pan"),
        "card_token": body.get("card_token"),
        "detail": body.get("detail"),
    }))

except Exception as e:
    print(json.dumps({
        "http_status": 0,
        "fullname": tx.get("fullname", "unknown"),
        "amount": tx.get("amount", "unknown"),
        "tx_id": None,
        "authorization_status": "ERROR",
        "masked_pan": "-",
        "card_token": "-",
        "detail": type(e).__name__,
    }))
'''

def short_token(token):
    if not token:
        return "-"
    return token[:24] + "..."

def submit_transaction(tx):
    tx_b64 = base64.b64encode(json.dumps(tx).encode()).decode()

    cmd = [
        "docker",
        "compose",
        "exec",
        "-T",
        "-e",
        f"TX_B64={tx_b64}",
        "pos-agent",
        "python",
        "-c",
        INNER_POS_SCRIPT,
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        return {
            "http_status": 0,
            "fullname": tx.get("fullname", "unknown"),
            "amount": tx.get("amount", "unknown"),
            "tx_id": None,
            "authorization_status": "ERROR",
            "masked_pan": "-",
            "card_token": "-",
            "detail": result.stderr.strip()[:80],
        }

    return json.loads(result.stdout.strip())

def print_table(rows):
    headers = ["No", "HTTP", "TX ID", "Customer", "Amount", "Status", "Masked PAN", "Token Preview"]
    widths = [4, 6, 7, 18, 10, 10, 18, 30]

    def line():
        print("+" + "+".join("-" * w for w in widths) + "+")

    def row(values):
        print("|" + "|".join(str(v)[:w].ljust(w) for v, w in zip(values, widths)) + "|")

    line()
    row(headers)
    line()

    for i, r in enumerate(rows, 1):
        row([
            i,
            r.get("http_status", "-"),
            r.get("tx_id") or "-",
            r.get("fullname", "-"),
            r.get("amount", "-"),
            r.get("authorization_status") or r.get("detail") or "-",
            r.get("masked_pan") or "-",
            short_token(r.get("card_token")),
        ])

    line()

def main():
    if not TRANSACTION_FILE.exists():
        print(f"Missing file: {TRANSACTION_FILE}")
        sys.exit(1)

    transactions = json.loads(TRANSACTION_FILE.read_text())

    print(f"[Loaded] {TRANSACTION_FILE}")
    print(f"[Submitting] {len(transactions)} demo transactions through POS -> VPN -> DMZ -> Internal FW -> CDE")
    print()

    results = [submit_transaction(tx) for tx in transactions]
    print_table(results)

    failed = [r for r in results if r.get("http_status") != 200]
    if failed:
        print("\n[Warning] Some transactions failed:")
        for r in failed:
            print(f"- {r.get('fullname')}: {r.get('detail')}")

if __name__ == "__main__":
    main()
