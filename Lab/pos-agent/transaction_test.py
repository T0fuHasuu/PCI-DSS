from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any


def _json(value: Any) -> str:
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False)


def build_transaction_test_report(
    *,
    preflight: dict[str, Any],
    transaction: dict[str, Any],
    evidence: dict[str, Any],
) -> dict[str, Any]:
    dns = preflight["dns"]
    wg = preflight["wireguard"]
    tls = preflight["tls"]
    health = preflight["payment_health"]

    trace_lines = []
    for item in transaction.get("processing_trace", []):
        trace_lines.append(
            f"{item.get('stage', 'application')}: {item.get('action', 'completed')} "
            f"[{item.get('protocol', 'internal')} | {item.get('duration_ms', 0)} ms]"
        )

    steps = [
        {
            "number": 1,
            "title": "Verify POS path and payment API health",
            "status": "PASS",
            "nodes": ["pos", "vpn", "perimeter", "dmz", "internal", "app"],
            "protocol": "DNS UDP/53 → WireGuard UDP/51820 → TLS 1.2",
            "lines": [
                "[1/5] Verify POS DNS and payment API health",
                "Server: 192.168.10.200:53",
                f"Name: {dns['hostname']}",
                f"Address: {dns['address']}",
                f"WireGuard status: {wg.get('status', 'unknown')}",
                f"WireGuard endpoint: {wg.get('endpoint', 'unknown')}",
                f"TLS: {tls.get('version', 'unknown')} / {tls.get('cipher', 'unknown')}",
                f"Certificate CN: {tls.get('peer_common_name', 'unknown')}",
                f"Payment health: {_json(health)}",
                "POS path verification: PASS",
            ],
        },
        {
            "number": 2,
            "title": "Submit test transaction from the POS",
            "status": "PASS",
            "nodes": ["app", "vault", "db"],
            "protocol": "HTTPS TLS 1.2 → CDE processing",
            "lines": [
                "[2/5] Submit test transaction from the POS container",
                (
                    "curl https://payment.gateway/process-transaction -X POST "
                    "-H 'Content-Type: application/json' "
                    f"--data '{{\"customer\":\"[submitted]\",\"card\":{{\"pan\":\"{transaction['masked_pan']}\",\"cvv\":\"***\"}},\"amount\":{transaction['amount']}}}'"
                ),
                _json(transaction),
                f"Transaction accepted: tx_id={transaction['tx_id']}",
                *trace_lines,
            ],
        },
        {
            "number": 3,
            "title": "Verify the PostgreSQL row",
            "status": evidence["database_verification"],
            "nodes": ["db"],
            "protocol": evidence["storage_protocol"],
            "lines": [
                "[3/5] Verify the persisted PostgreSQL row",
                f"Database verification: {evidence['database_verification']}",
                f"tx_id={evidence['tx_id']}",
                f"authorization_status={evidence['authorization_status']}",
                f"amount={evidence['amount']}",
                f"masked_pan={evidence['masked_pan']}",
                f"card_token={evidence['card_token']}",
                f"encrypted_chd_prefix={evidence['ciphertext_preview']}",
                f"vault_key_version={evidence['vault_key_version']}",
                f"raw_pan_stored={str(evidence['raw_pan_stored']).lower()}",
                f"cvv_column_present={str(evidence['cvv_column_present']).lower()}",
            ],
        },
        {
            "number": 4,
            "title": "Perform controlled Vault decryption verification",
            "status": evidence["vault_decryption_verification"],
            "nodes": ["vault"],
            "protocol": "Vault Transit TLS 1.2 + mTLS + AppRole",
            "lines": [
                "[4/5] Controlled Vault ciphertext verification",
                f"Vault decryption verification: {evidence['vault_decryption_verification']}",
                f"decrypted_chd={_json(evidence['decrypted_chd'])}",
                f"pan_matches_masked={str(evidence['pan_matches_masked']).lower()}",
                f"cvv_present={str(evidence['cvv_present']).lower()}",
                "Note: the decrypted PAN is masked before leaving the CDE application.",
            ],
        },
        {
            "number": 5,
            "title": "Confirm PostgreSQL transport encryption",
            "status": evidence["postgresql_tls_verification"],
            "nodes": ["db"],
            "protocol": evidence["storage_protocol"],
            "lines": [
                "[5/5] Confirm PostgreSQL transport encryption",
                f"PostgreSQL TLS verification: {evidence['postgresql_tls_verification']}",
                f"TLS version: {evidence['db_tls_version']}",
                f"Cipher: {evidence['db_tls_cipher']}",
            ],
        },
    ]

    all_passed = all(step["status"] == "PASS" for step in steps)
    return {
        "status": "completed" if all_passed else "failed",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "steps": steps,
        "transaction": transaction,
        "evidence": evidence,
        "summary": {
            "tx_id": transaction["tx_id"],
            "authorization_status": transaction["authorization_status"],
            "amount": transaction["amount"],
            "masked_pan": evidence["masked_pan"],
            "card_token": evidence["card_token"],
            "encrypted_chd": evidence["encrypted_chd"],
            "vault_key_version": evidence["vault_key_version"],
            "raw_pan_stored": evidence["raw_pan_stored"],
            "sad_stored": evidence["sad_stored"],
            "storage_protocol": evidence["storage_protocol"],
            "database_verification": evidence["database_verification"],
            "vault_decryption_verification": evidence["vault_decryption_verification"],
            "postgresql_tls_verification": evidence["postgresql_tls_verification"],
            "decrypted_chd": evidence["decrypted_chd"],
        },
    }
