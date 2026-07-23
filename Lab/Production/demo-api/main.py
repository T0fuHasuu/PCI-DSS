from __future__ import annotations

import os
import ssl
from decimal import Decimal
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, EmailStr, Field

POS_AGENT_URL = os.getenv("POS_AGENT_URL", "https://192.168.10.20:9444")
CA_FILE = os.getenv("POS_AGENT_CA", "/etc/lab/pki/ca.crt")
CLIENT_CERT = os.getenv("POS_AGENT_CLIENT_CERT", "/etc/lab/pki/client.crt")
CLIENT_KEY = os.getenv("POS_AGENT_CLIENT_KEY", "/etc/lab/pki/client.key")


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


def tls12_context() -> ssl.SSLContext:
    context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cafile=CA_FILE)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.maximum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(CLIENT_CERT, CLIENT_KEY)
    context.check_hostname = True
    context.verify_mode = ssl.CERT_REQUIRED
    return context


app = FastAPI(
    title="PCI Transaction Test API",
    version="2.0.0",
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "healthy"}


@app.post("/simulations")
async def run_simulation(request: TransactionRequest) -> dict[str, Any]:
    try:
        async with httpx.AsyncClient(
            base_url=POS_AGENT_URL,
            verify=tls12_context(),
            timeout=httpx.Timeout(75.0, connect=8.0),
            trust_env=False,
        ) as client:
            response = await client.post(
                "/run-test",
                json=request.model_dump(mode="json"),
            )
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=502,
            detail=f"POS transaction test unavailable: {type(exc).__name__}",
        ) from exc

    try:
        payload = response.json()
    except ValueError as exc:
        raise HTTPException(status_code=502, detail="POS test returned invalid JSON") from exc

    if response.status_code != 200:
        raise HTTPException(
            status_code=response.status_code,
            detail=payload.get("detail", "Transaction test failed"),
        )
    return payload
