from __future__ import annotations

import asyncio
import base64
import hashlib
import json
import logging
import logging.handlers
import os
import socket
import ssl
import time
from contextlib import asynccontextmanager
from datetime import datetime
from decimal import Decimal
from pathlib import Path
from typing import Any

import asyncpg
import httpx
from fastapi import FastAPI, HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, EmailStr, Field
from app.cde_audit import CDEAuditMiddleware


def configure_logging() -> logging.Logger:
    host = os.getenv("APP_LOG_SERVER", "10.100.10.200")
    port = int(os.getenv("APP_LOG_PORT", "514"))
    handler = logging.handlers.SysLogHandler(
        address=(host, port),
        facility=logging.handlers.SysLogHandler.LOG_LOCAL4,
        socktype=socket.SOCK_DGRAM,
    )
    handler.setFormatter(logging.Formatter("payment-app %(levelname)s %(message)s"))

    root = logging.getLogger()
    root.handlers.clear()
    root.setLevel(logging.INFO)
    root.addHandler(handler)

    for name in ("uvicorn", "uvicorn.error", "fastapi"):
        child = logging.getLogger(name)
        child.handlers.clear()
        child.propagate = True

    return logging.getLogger("payment-app")


logger = configure_logging()


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


class ProcessingTraceStep(BaseModel):
    stage: str
    action: str
    protocol: str
    duration_ms: float


class TransactionResponse(BaseModel):
    tx_id: int
    customer_id: int
    amount: Decimal
    authorization_status: str
    masked_pan: str
    card_token: str
    tx_timestamp: datetime
    processing_trace: list[ProcessingTraceStep] = Field(default_factory=list)


class TransactionEvidenceResponse(BaseModel):
    tx_id: int
    amount: Decimal
    authorization_status: str
    masked_pan: str
    card_token: str
    encrypted_chd: str
    ciphertext_preview: str
    vault_key_version: int
    tx_timestamp: datetime
    raw_pan_stored: bool = False
    sad_stored: bool = False
    storage_protocol: str = "PostgreSQL TLS with client-certificate authentication"
    database_verification: str
    vault_decryption_verification: str
    postgresql_tls_verification: str
    cvv_column_present: bool
    decrypted_chd: dict[str, Any]
    cvv_present: bool
    pan_matches_masked: bool
    db_tls_version: str
    db_tls_cipher: str


class HealthResponse(BaseModel):
    status: str
    vault: str
    database: str


def tls12_context(*, ca: str, cert: str, key: str) -> ssl.SSLContext:
    context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cafile=ca)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.maximum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(certfile=cert, keyfile=key)
    context.check_hostname = True
    context.verify_mode = ssl.CERT_REQUIRED
    return context


class VaultTransitClient:
    def __init__(self) -> None:
        self.address = os.environ["VAULT_ADDR"].rstrip("/")
        self.role_id_path = Path(os.environ["VAULT_ROLE_ID_FILE"])
        self.secret_id_path = Path(os.environ["VAULT_SECRET_ID_FILE"])
        context = tls12_context(
            ca=os.environ["VAULT_CACERT"],
            cert=os.environ["VAULT_CLIENT_CERT"],
            key=os.environ["VAULT_CLIENT_KEY"],
        )
        self.client = httpx.AsyncClient(
            base_url=self.address,
            verify=context,
            timeout=httpx.Timeout(10.0),
            trust_env=False,
        )
        self._token: str | None = None
        self._expires_at = 0.0
        self._login_lock = asyncio.Lock()

    async def close(self) -> None:
        await self.client.aclose()

    async def _login(self, *, force: bool = False) -> str:
        if not force and self._token and time.monotonic() < self._expires_at:
            return self._token

        async with self._login_lock:
            if not force and self._token and time.monotonic() < self._expires_at:
                return self._token

            role_id = self.role_id_path.read_text(encoding="utf-8").strip()
            secret_id = self.secret_id_path.read_text(encoding="utf-8").strip()
            response = await self.client.post(
                "/v1/auth/approle/login",
                json={"role_id": role_id, "secret_id": secret_id},
            )
            response.raise_for_status()
            auth = response.json()["auth"]
            self._token = auth["client_token"]
            lease = int(auth.get("lease_duration", 900))
            self._expires_at = time.monotonic() + max(30, lease - 30)
            logger.info("Vault AppRole authentication succeeded")
            return self._token

    async def _post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        token = await self._login()
        response = await self.client.post(path, json=payload, headers={"X-Vault-Token": token})
        if response.status_code in (401, 403):
            token = await self._login(force=True)
            response = await self.client.post(path, json=payload, headers={"X-Vault-Token": token})
        response.raise_for_status()
        return response.json()["data"]

    async def encrypt_chd(self, plaintext: bytes) -> tuple[str, int]:
        encoded = base64.b64encode(plaintext).decode("ascii")
        data = await self._post("/v1/transit/encrypt/payment-chd", {"plaintext": encoded})
        ciphertext = str(data["ciphertext"])
        try:
            key_version = int(ciphertext.split(":", 2)[1].lstrip("v"))
        except (IndexError, ValueError):
            key_version = 1
        return ciphertext, key_version

    async def tokenize_pan(self, pan: str) -> str:
        encoded = base64.b64encode(pan.encode("ascii")).decode("ascii")
        data = await self._post(
            "/v1/transit/hmac/payment-token/sha2-256",
            {"input": encoded},
        )
        # The token is an opaque representation derived from a Vault-protected HMAC key.
        digest = hashlib.sha256(str(data["hmac"]).encode("utf-8")).hexdigest()
        return f"tok_{digest[:32]}"

    async def decrypt_chd(self, ciphertext: str) -> bytes:
        data = await self._post(
            "/v1/transit/decrypt/payment-chd",
            {"ciphertext": ciphertext},
        )
        return base64.b64decode(str(data["plaintext"]), validate=True)

    async def health(self) -> bool:
        try:
            response = await self.client.get("/v1/sys/health?standbyok=true")
            return response.status_code == 200
        except httpx.HTTPError:
            return False


vault_client: VaultTransitClient | None = None
db_pool: asyncpg.Pool | None = None


async def create_db_pool() -> asyncpg.Pool:
    context = tls12_context(
        ca=os.environ["DB_CACERT"],
        cert=os.environ["DB_CLIENT_CERT"],
        key=os.environ["DB_CLIENT_KEY"],
    )
    return await asyncpg.create_pool(
        host=os.environ["DB_HOST"],
        port=int(os.getenv("DB_PORT", "5432")),
        database=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        ssl=context,
        min_size=1,
        max_size=5,
        command_timeout=10,
        server_settings={"application_name": "payment-app"},
    )


dependency_task: asyncio.Task[None] | None = None


async def initialize_dependencies_forever() -> None:
    """Connect to Vault and PostgreSQL without terminating the API process.

    The application boundary starts immediately so /health can report a
    degraded state while dependencies are becoming ready. This avoids the
    previous 90-second Uvicorn restart loop on Docker Desktop.
    """
    global vault_client, db_pool
    attempt = 0

    while vault_client is None or db_pool is None:
        candidate_vault: VaultTransitClient | None = None
        candidate_pool: asyncpg.Pool | None = None
        try:
            candidate_vault = VaultTransitClient()
            await candidate_vault._login()
            candidate_pool = await create_db_pool()

            vault_client = candidate_vault
            db_pool = candidate_pool
            logger.info("Application initialized with Vault Transit and PostgreSQL TLS")
            return
        except asyncio.CancelledError:
            if candidate_pool is not None:
                await candidate_pool.close()
            if candidate_vault is not None:
                await candidate_vault.close()
            raise
        except Exception as exc:  # Startup must remain alive and keep retrying.
            attempt += 1
            if candidate_pool is not None:
                await candidate_pool.close()
            if candidate_vault is not None:
                await candidate_vault.close()
            if attempt == 1 or attempt % 5 == 0:
                logger.warning(
                    "Dependency connection pending attempt=%s error=%s",
                    attempt,
                    type(exc).__name__,
                )
            await asyncio.sleep(3)


@asynccontextmanager
async def lifespan(_: FastAPI):
    global vault_client, db_pool, dependency_task
    dependency_task = asyncio.create_task(initialize_dependencies_forever())
    try:
        yield
    finally:
        if dependency_task is not None:
            dependency_task.cancel()
            try:
                await dependency_task
            except asyncio.CancelledError:
                pass
            dependency_task = None
        if db_pool is not None:
            await db_pool.close()
            db_pool = None
        if vault_client is not None:
            await vault_client.close()
            vault_client = None
        logger.info("Application shutdown completed")


app = FastAPI(
    title="PCI Segmentation Payment Lab",
    version="3.4.0",
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
    lifespan=lifespan,
)
app.add_middleware(CDEAuditMiddleware)
app.add_middleware(TrustedHostMiddleware, allowed_hosts=["app.internal", "127.0.0.1", "localhost"])


@app.exception_handler(RequestValidationError)
async def validation_error_handler(_, __):
    logger.warning("Rejected invalid transaction payload")
    return JSONResponse(status_code=422, content={"detail": "Invalid request payload"})


@app.exception_handler(Exception)
async def unhandled_error_handler(_, exc: Exception):
    logger.error("Unhandled application error: %s", type(exc).__name__)
    return JSONResponse(status_code=500, content={"detail": "Internal processing error"})


def mask_pan(pan: str) -> str:
    return "*" * (len(pan) - 4) + pan[-4:]


def simulated_authorization(cvv: str) -> str:
    # The lab has no acquiring bank. CVV is checked only as an in-memory simulation
    # and is never included in the Vault plaintext or database write.
    return "approved" if len(cvv) in (3, 4) and cvv.isdigit() else "declined"


@app.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    vault_status = False
    db_status = False

    if vault_client is not None:
        vault_status = await vault_client.health()
    if db_pool is not None:
        try:
            async with db_pool.acquire() as connection:
                db_status = bool(await connection.fetchval("SELECT 1"))
        except asyncpg.PostgresError:
            db_status = False

    return HealthResponse(
        status="healthy" if vault_status and db_status else "degraded",
        vault="healthy" if vault_status else "unavailable",
        database="healthy" if db_status else "unavailable",
    )


@app.post("/process-transaction", response_model=TransactionResponse)
async def process_transaction(request: TransactionRequest) -> TransactionResponse:
    if vault_client is None or db_pool is None:
        raise HTTPException(status_code=503, detail="Service unavailable")

    total_started = time.perf_counter()
    trace: list[ProcessingTraceStep] = []

    authorization_started = time.perf_counter()
    cvv = request.card.cvv
    authorization_status = simulated_authorization(cvv)
    request.card.cvv = ""
    cvv = ""  # Best-effort reference removal; Python cannot guarantee memory zeroization.
    authorization_ms = (time.perf_counter() - authorization_started) * 1000
    trace.append(
        ProcessingTraceStep(
            stage="application",
            action="Validated the request, used CVV for simulated authorization, then discarded SAD",
            protocol="In-memory processing",
            duration_ms=round(authorization_ms, 2),
        )
    )

    if authorization_status != "approved":
        logger.warning("Transaction declined during simulated authorization")
        raise HTTPException(status_code=402, detail="Transaction declined")

    pan = request.card.pan
    masked_pan = mask_pan(pan)
    chd = {
        "pan": pan,
        "exp_month": request.card.exp_month,
        "exp_year": request.card.exp_year,
    }
    plaintext = json.dumps(chd, separators=(",", ":"), sort_keys=True).encode("utf-8")

    try:
        encrypt_started = time.perf_counter()
        encrypted_chd, key_version = await vault_client.encrypt_chd(plaintext)
        encrypt_ms = (time.perf_counter() - encrypt_started) * 1000
        trace.append(
            ProcessingTraceStep(
                stage="vault",
                action="Encrypted CHD with the Vault Transit payment-chd key",
                protocol="TLS 1.2 + mTLS + AppRole",
                duration_ms=round(encrypt_ms, 2),
            )
        )

        token_started = time.perf_counter()
        card_token = await vault_client.tokenize_pan(pan)
        token_ms = (time.perf_counter() - token_started) * 1000
        trace.append(
            ProcessingTraceStep(
                stage="vault",
                action="Derived an opaque PAN token with a Vault-protected HMAC key",
                protocol="TLS 1.2 + mTLS + AppRole",
                duration_ms=round(token_ms, 2),
            )
        )
    except (httpx.HTTPError, KeyError, OSError) as exc:
        logger.error("Vault operation failed: %s", type(exc).__name__)
        raise HTTPException(status_code=503, detail="Cryptographic service unavailable") from exc
    finally:
        plaintext = b""
        chd.clear()
        request.card.pan = ""
        pan = ""

    database_started = time.perf_counter()
    try:
        async with db_pool.acquire() as connection:
            async with connection.transaction():
                customer_id = await connection.fetchval(
                    """
                    INSERT INTO customers (full_name, email, phone_number)
                    VALUES ($1, $2, $3)
                    ON CONFLICT (email) DO UPDATE
                    SET full_name = EXCLUDED.full_name,
                        phone_number = EXCLUDED.phone_number
                    RETURNING customer_id
                    """,
                    request.customer.full_name,
                    str(request.customer.email),
                    request.customer.phone_number,
                )
                row = await connection.fetchrow(
                    """
                    INSERT INTO transactions (
                        customer_id,
                        tx_amount,
                        authorization_status,
                        masked_pan,
                        card_token,
                        encrypted_chd,
                        vault_key_version
                    )
                    VALUES ($1, $2, $3, $4, $5, $6, $7)
                    RETURNING tx_id, tx_timestamp
                    """,
                    customer_id,
                    request.amount,
                    authorization_status,
                    masked_pan,
                    card_token,
                    encrypted_chd,
                    key_version,
                )
    except asyncpg.PostgresError as exc:
        logger.error("Database transaction failed: %s", type(exc).__name__)
        raise HTTPException(status_code=503, detail="Persistence service unavailable") from exc

    database_ms = (time.perf_counter() - database_started) * 1000
    trace.append(
        ProcessingTraceStep(
            stage="database",
            action="Stored masked PAN, token, Vault ciphertext, and key version",
            protocol="PostgreSQL TLS 1.2 + client certificate",
            duration_ms=round(database_ms, 2),
        )
    )
    trace.append(
        ProcessingTraceStep(
            stage="application",
            action="Completed transaction processing",
            protocol="CDE application workflow",
            duration_ms=round((time.perf_counter() - total_started) * 1000, 2),
        )
    )

    logger.info("Transaction stored tx_id=%s customer_id=%s", row["tx_id"], customer_id)
    return TransactionResponse(
        tx_id=row["tx_id"],
        customer_id=customer_id,
        amount=request.amount,
        authorization_status=authorization_status,
        masked_pan=masked_pan,
        card_token=card_token,
        tx_timestamp=row["tx_timestamp"],
        processing_trace=trace,
    )


@app.get("/transaction/{tx_id}", response_model=TransactionResponse)
async def get_transaction(tx_id: int) -> TransactionResponse:
    if db_pool is None:
        raise HTTPException(status_code=503, detail="Service unavailable")

    try:
        async with db_pool.acquire() as connection:
            row = await connection.fetchrow(
                """
                SELECT tx_id, customer_id, tx_amount, authorization_status,
                       masked_pan, card_token, tx_timestamp
                FROM transactions
                WHERE tx_id = $1
                """,
                tx_id,
            )
    except asyncpg.PostgresError as exc:
        logger.error("Transaction lookup failed: %s", type(exc).__name__)
        raise HTTPException(status_code=503, detail="Persistence service unavailable") from exc

    if row is None:
        raise HTTPException(status_code=404, detail="Transaction not found")

    return TransactionResponse(
        tx_id=row["tx_id"],
        customer_id=row["customer_id"],
        amount=row["tx_amount"],
        authorization_status=row["authorization_status"],
        masked_pan=row["masked_pan"],
        card_token=row["card_token"],
        tx_timestamp=row["tx_timestamp"],
    )


@app.get("/transaction/{tx_id}/evidence", response_model=TransactionEvidenceResponse)
async def get_transaction_evidence(tx_id: int) -> TransactionEvidenceResponse:
    if db_pool is None or vault_client is None:
        raise HTTPException(status_code=503, detail="Service unavailable")

    try:
        async with db_pool.acquire() as connection:
            row = await connection.fetchrow(
                """
                SELECT tx_id, tx_amount, authorization_status, masked_pan, card_token,
                       encrypted_chd, vault_key_version, tx_timestamp
                FROM transactions
                WHERE tx_id = $1
                """,
                tx_id,
            )
            cvv_column_present = bool(
                await connection.fetchval(
                    """
                    SELECT EXISTS (
                        SELECT 1
                        FROM information_schema.columns
                        WHERE table_schema = 'public'
                          AND table_name = 'transactions'
                          AND column_name IN ('cvv', 'cvc', 'security_code')
                    )
                    """
                )
            )
            tls_row = await connection.fetchrow(
                """
                SELECT ssl, COALESCE(version, 'unknown') AS version,
                       COALESCE(cipher, 'unknown') AS cipher
                FROM pg_stat_ssl
                WHERE pid = pg_backend_pid()
                """
            )
    except asyncpg.PostgresError as exc:
        logger.error("Transaction evidence lookup failed: %s", type(exc).__name__)
        raise HTTPException(status_code=503, detail="Persistence service unavailable") from exc

    if row is None:
        raise HTTPException(status_code=404, detail="Transaction not found")

    ciphertext = str(row["encrypted_chd"])
    preview = ciphertext if len(ciphertext) <= 96 else f"{ciphertext[:72]}...{ciphertext[-20:]}"

    decrypted_bytes = b""
    try:
        decrypted_bytes = await vault_client.decrypt_chd(ciphertext)
        decrypted = json.loads(decrypted_bytes.decode("utf-8"))
        decrypted_pan = str(decrypted.get("pan", ""))
        cvv_present = any(key.lower() in {"cvv", "cvc", "security_code"} for key in decrypted)
        pan_matches_masked = bool(decrypted_pan) and mask_pan(decrypted_pan) == row["masked_pan"]
        safe_decrypted = {
            "pan": mask_pan(decrypted_pan) if decrypted_pan else "unavailable",
            "exp_month": decrypted.get("exp_month"),
            "exp_year": decrypted.get("exp_year"),
        }
    except (httpx.HTTPError, ValueError, KeyError, OSError) as exc:
        logger.error("Controlled Vault verification failed: %s", type(exc).__name__)
        raise HTTPException(status_code=503, detail="Controlled decryption verification unavailable") from exc
    finally:
        decrypted_bytes = b""

    db_tls_enabled = bool(tls_row and tls_row["ssl"])
    db_tls_version = str(tls_row["version"]) if tls_row else "unknown"
    db_tls_cipher = str(tls_row["cipher"]) if tls_row else "unknown"
    raw_pan_stored = bool(
        decrypted_pan
        and (
            decrypted_pan in ciphertext
            or decrypted_pan in str(row["card_token"])
            or decrypted_pan == str(row["masked_pan"])
        )
    )

    database_pass = not raw_pan_stored and not cvv_column_present and ciphertext.startswith("vault:v")
    vault_pass = pan_matches_masked and not cvv_present
    tls_pass = db_tls_enabled and db_tls_version.startswith("TLSv1.2")

    return TransactionEvidenceResponse(
        tx_id=row["tx_id"],
        amount=row["tx_amount"],
        authorization_status=row["authorization_status"],
        masked_pan=row["masked_pan"],
        card_token=row["card_token"],
        encrypted_chd=ciphertext,
        ciphertext_preview=preview,
        vault_key_version=row["vault_key_version"],
        tx_timestamp=row["tx_timestamp"],
        raw_pan_stored=raw_pan_stored,
        sad_stored=cvv_present or cvv_column_present,
        database_verification="PASS" if database_pass else "FAIL",
        vault_decryption_verification="PASS" if vault_pass else "FAIL",
        postgresql_tls_verification="PASS" if tls_pass else "FAIL",
        cvv_column_present=cvv_column_present,
        decrypted_chd=safe_decrypted,
        cvv_present=cvv_present,
        pan_matches_masked=pan_matches_masked,
        db_tls_version=db_tls_version,
        db_tls_cipher=db_tls_cipher,
        storage_protocol=f"PostgreSQL {db_tls_version} with client-certificate authentication",
    )

