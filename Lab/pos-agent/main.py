from __future__ import annotations

import asyncio
import os
import socket
import ssl
import subprocess
import time
from decimal import Decimal
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, EmailStr, Field

from transaction_test import build_transaction_test_report

PAYMENT_HOST = os.getenv("PAYMENT_HOST", "payment.gateway")
PAYMENT_URL = os.getenv("PAYMENT_URL", f"https://{PAYMENT_HOST}")
CA_FILE = os.getenv("PAYMENT_CA", "/etc/lab/pki/ca.crt")


class CustomerData(BaseModel):
    full_name: str = Field(min_length=1, max_length=255)
    email: EmailStr
    phone_number: str = Field(min_length=7, max_length=20, pattern=r"^[0-9+() .-]+$")


class CardData(BaseModel):
    pan: str = Field(min_length=13, max_length=19, pattern=r"^[0-9]{13,19}$", repr=False)
    exp_month: int = Field(ge=1, le=12)
    exp_year: int = Field(ge=2026, le=2099)
    cvv: str = Field(min_length=3, max_length=4, pattern=r"^[0-9]{3,4}$", repr=False)


class TransactionRequest(BaseModel):
    customer: CustomerData
    card: CardData
    amount: Decimal = Field(gt=Decimal("0.00"), le=Decimal("999999.99"), decimal_places=2)


def client_context() -> ssl.SSLContext:
    context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cafile=CA_FILE)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.maximum_version = ssl.TLSVersion.TLSv1_2
    context.check_hostname = True
    context.verify_mode = ssl.CERT_REQUIRED
    return context


def run_command(*args: str) -> str:
    result = subprocess.run(args, check=True, capture_output=True, text=True, timeout=4)
    return result.stdout.strip()


def wireguard_snapshot() -> dict[str, Any]:
    try:
        latest_raw = run_command("wg", "show", "wg0", "latest-handshakes")
        endpoint_raw = run_command("wg", "show", "wg0", "endpoints")
        transfer_raw = run_command("wg", "show", "wg0", "transfer")
        now = int(time.time())
        latest_epoch = int(latest_raw.split()[-1]) if latest_raw else 0
        age = max(0, now - latest_epoch) if latest_epoch else None
        endpoint = endpoint_raw.split()[-1] if endpoint_raw else "unknown"
        transfer_fields = transfer_raw.split()
        received = int(transfer_fields[-2]) if len(transfer_fields) >= 2 else 0
        sent = int(transfer_fields[-1]) if len(transfer_fields) >= 1 else 0
        return {
            "interface": "wg0",
            "endpoint": endpoint,
            "latest_handshake_seconds": age,
            "received_bytes": received,
            "sent_bytes": sent,
            "status": "active" if age is not None and age < 180 else "stale",
        }
    except (subprocess.SubprocessError, ValueError, OSError) as exc:
        return {"interface": "wg0", "status": "unavailable", "error": type(exc).__name__}


def inspect_tls(address: str) -> dict[str, Any]:
    context = client_context()
    started = time.perf_counter()
    with socket.create_connection((address, 443), timeout=6) as raw:
        with context.wrap_socket(raw, server_hostname=PAYMENT_HOST) as secured:
            certificate = secured.getpeercert()
            subject = dict(item[0] for item in certificate.get("subject", []))
            return {
                "version": secured.version(),
                "cipher": secured.cipher()[0],
                "peer_common_name": subject.get("commonName", "unknown"),
                "handshake_ms": round((time.perf_counter() - started) * 1000, 2),
            }


async def payment_client() -> httpx.AsyncClient:
    return httpx.AsyncClient(
        base_url=PAYMENT_URL,
        verify=client_context(),
        timeout=httpx.Timeout(35.0, connect=8.0),
        trust_env=False,
    )


app = FastAPI(title="POS Agent", version="1.0.0", docs_url=None, redoc_url=None, openapi_url=None)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "healthy"}


@app.post("/preflight")
async def preflight() -> dict[str, Any]:
    started = time.perf_counter()
    try:
        address = await asyncio.to_thread(socket.gethostbyname, PAYMENT_HOST)
        tls = await asyncio.to_thread(inspect_tls, address)
        async with await payment_client() as client:
            response = await client.get("/health")
            response.raise_for_status()
            payment_health = response.json()
    except (OSError, ssl.SSLError, httpx.HTTPError) as exc:
        raise HTTPException(status_code=502, detail=f"POS preflight failed: {type(exc).__name__}") from exc

    return {
        "dns": {"hostname": PAYMENT_HOST, "address": address},
        "wireguard": wireguard_snapshot(),
        "tls": tls,
        "payment_health": payment_health,
        "total_ms": round((time.perf_counter() - started) * 1000, 2),
    }


@app.post("/purchase")
async def purchase(request: TransactionRequest) -> dict[str, Any]:
    try:
        async with await payment_client() as client:
            response = await client.post(
                "/process-transaction",
                json=request.model_dump(mode="json"),
            )
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Payment request failed: {type(exc).__name__}") from exc

    try:
        payload = response.json()
    except ValueError as exc:
        raise HTTPException(status_code=502, detail="Payment gateway returned invalid JSON") from exc

    if response.status_code != 200:
        raise HTTPException(status_code=response.status_code, detail=payload.get("detail", "Transaction failed"))
    return payload


@app.get("/evidence/{tx_id}")
async def evidence(tx_id: int) -> dict[str, Any]:
    try:
        async with await payment_client() as client:
            response = await client.get(f"/transaction/{tx_id}/evidence")
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Evidence request failed: {type(exc).__name__}") from exc

    try:
        payload = response.json()
    except ValueError as exc:
        raise HTTPException(status_code=502, detail="Evidence endpoint returned invalid JSON") from exc

    if response.status_code != 200:
        raise HTTPException(status_code=response.status_code, detail=payload.get("detail", "Evidence unavailable"))
    return payload


@app.post("/run-test")
async def run_transaction_test(request: TransactionRequest) -> dict[str, Any]:
    try:
        address = await asyncio.to_thread(socket.gethostbyname, PAYMENT_HOST)
        tls = await asyncio.to_thread(inspect_tls, address)
        async with await payment_client() as client:
            health_response = await client.get("/health")
            health_response.raise_for_status()

            purchase_response = await client.post(
                "/process-transaction",
                json=request.model_dump(mode="json"),
            )
            purchase_payload = purchase_response.json()
            if purchase_response.status_code != 200:
                raise HTTPException(
                    status_code=purchase_response.status_code,
                    detail=purchase_payload.get("detail", "Transaction failed"),
                )

            evidence_response = await client.get(
                f"/transaction/{purchase_payload['tx_id']}/evidence"
            )
            evidence_payload = evidence_response.json()
            if evidence_response.status_code != 200:
                raise HTTPException(
                    status_code=evidence_response.status_code,
                    detail=evidence_payload.get("detail", "Verification failed"),
                )
    except HTTPException:
        raise
    except (OSError, ssl.SSLError, httpx.HTTPError, ValueError, KeyError) as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Transaction test failed: {type(exc).__name__}",
        ) from exc

    preflight_result = {
        "dns": {"hostname": PAYMENT_HOST, "address": address},
        "wireguard": wireguard_snapshot(),
        "tls": tls,
        "payment_health": health_response.json(),
    }
    return build_transaction_test_report(
        preflight=preflight_result,
        transaction=purchase_payload,
        evidence=evidence_payload,
    )
