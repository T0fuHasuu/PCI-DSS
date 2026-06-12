"""
PCI-DSS Compliant Transaction Processing Application
Handles transaction data, PAN masking, tokenization, and encryption
"""

import os
import json
import logging
from datetime import datetime
from typing import Optional
import httpx
import asyncpg
from fastapi import FastAPI, HTTPException, Body
from pydantic import BaseModel, EmailStr, Field
import secrets

# Configuration
KMS_HOST = os.getenv("KMS_HOST", "kms")
KMS_PORT = os.getenv("KMS_PORT", "8001")
DB_HOST = os.getenv("DB_HOST", "postgres")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "cde_db")
DB_USER = os.getenv("DB_USER", "cde_user")
DB_PASSWORD = os.getenv("DB_PASSWORD", "SecurePass123!")

# Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="PCI-DSS CDE Application", version="1.0.0")

# Database connection pool
db_pool = None


class CustomerData(BaseModel):
    """Customer information for transaction"""
    full_name: str = Field(..., min_length=1, max_length=255)
    email: EmailStr
    phone_number: str = Field(..., min_length=10, max_length=20)


class CardholderData(BaseModel):
    """Sensitive cardholder data"""
    pan: str = Field(..., regex=r"^\d{13,19}$")
    exp_month: int = Field(..., ge=1, le=12)
    exp_year: int = Field(..., ge=2024, le=2099)
    cvv: str = Field(..., regex=r"^\d{3,4}$")


class TransactionRequest(BaseModel):
    """Complete transaction request"""
    customer: CustomerData
    card: CardholderData
    amount: float = Field(..., gt=0, le=999999.99)


class TransactionResponse(BaseModel):
    """Transaction response - minimal sensitive data"""
    tx_id: str
    customer_id: int
    amount: float
    masked_pan: str
    card_token: str
    tx_timestamp: str


class HealthResponse(BaseModel):
    """Health check response"""
    status: str
    kms_status: str
    database_status: str


async def get_db():
    """Get database connection from pool"""
    async with db_pool.acquire() as conn:
        return conn


async def init_db():
    """Initialize database connection pool"""
    global db_pool
    db_pool = await asyncpg.create_pool(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME,
        min_size=1,
        max_size=10,
    )
    logger.info("Database pool initialized")


async def close_db():
    """Close database connection pool"""
    if db_pool:
        await db_pool.close()
        logger.info("Database pool closed")


async def encrypt_with_kms(plain_text: str) -> str:
    """Encrypt data using KMS service"""
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"http://{KMS_HOST}:{KMS_PORT}/encrypt",
                json={"plaintext": plain_text},
                timeout=10.0,
            )
            response.raise_for_status()
            return response.json()["ciphertext"]
    except Exception as e:
        logger.error(f"KMS encryption failed: {e}")
        raise HTTPException(status_code=503, detail="Encryption service unavailable")


def mask_pan(pan: str) -> str:
    """Mask PAN - keep only last 4 digits"""
    if len(pan) < 4:
        return "****"
    return "*" * (len(pan) - 4) + pan[-4:]


def generate_token() -> str:
    """Generate unique card token"""
    return f"tok_{secrets.token_hex(8)}"


async def create_or_get_customer(conn, customer_data: CustomerData) -> int:
    """Create customer if doesn't exist, return customer_id"""
    try:
        # Check if customer exists
        existing = await conn.fetchval(
            "SELECT customer_id FROM customers WHERE email = $1",
            customer_data.email,
        )
        if existing:
            return existing

        # Create new customer
        customer_id = await conn.fetchval(
            """
            INSERT INTO customers (full_name, email, phone_number, created_at)
            VALUES ($1, $2, $3, $4)
            RETURNING customer_id
            """,
            customer_data.full_name,
            customer_data.email,
            customer_data.phone_number,
            datetime.utcnow(),
        )
        logger.info(f"Created customer: {customer_id}")
        return customer_id
    except Exception as e:
        logger.error(f"Customer creation failed: {e}")
        raise HTTPException(status_code=500, detail="Customer processing failed")


async def store_transaction(
    conn,
    customer_id: int,
    amount: float,
    masked_pan: str,
    card_token: str,
    encrypted_chd: str,
) -> str:
    """Store transaction in database"""
    try:
        tx_id = await conn.fetchval(
            """
            INSERT INTO transactions 
            (customer_id, tx_amount, masked_pan, card_token, encrypted_chd, tx_timestamp)
            VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING tx_id
            """,
            customer_id,
            amount,
            masked_pan,
            card_token,
            encrypted_chd,
            datetime.utcnow(),
        )
        logger.info(f"Transaction stored: {tx_id}")
        return tx_id
    except Exception as e:
        logger.error(f"Transaction storage failed: {e}")
        raise HTTPException(status_code=500, detail="Transaction storage failed")


@app.on_event("startup")
async def startup_event():
    """Initialize on startup"""
    await init_db()
    logger.info("Application started")


@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    await close_db()
    logger.info("Application shutdown")


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint"""
    kms_status = "unavailable"
    db_status = "unavailable"

    # Check KMS
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"http://{KMS_HOST}:{KMS_PORT}/health", timeout=5.0
            )
            if response.status_code == 200:
                kms_status = "healthy"
    except Exception as e:
        logger.warning(f"KMS health check failed: {e}")

    # Check Database
    try:
        async with db_pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
            db_status = "healthy"
    except Exception as e:
        logger.warning(f"Database health check failed: {e}")

    return HealthResponse(
        status="healthy" if kms_status == "healthy" and db_status == "healthy" else "degraded",
        kms_status=kms_status,
        database_status=db_status,
    )


@app.post("/process-transaction", response_model=TransactionResponse)
async def process_transaction(request: TransactionRequest = Body(...)):
    """
    Process transaction with tokenization and encryption
    
    Flow:
    1. Validate input
    2. Mask PAN
    3. Generate card token
    4. Encrypt CHD+SAD
    5. Create/get customer
    6. Store transaction
    7. Return minimal data
    """
    try:
        logger.info(f"Processing transaction for {request.customer.email}")

        # Prepare CHD for encryption (sensitive data)
        chd = {
            "pan": request.card.pan,
            "exp_month": request.card.exp_month,
            "exp_year": request.card.exp_year,
            "cvv": request.card.cvv,
        }
        chd_json = json.dumps(chd)

        # Encrypt CHD
        logger.info("Encrypting CHD with KMS")
        encrypted_chd = await encrypt_with_kms(chd_json)

        # Mask PAN
        masked_pan = mask_pan(request.card.pan)

        # Generate token
        card_token = generate_token()

        # Get database connection
        conn = await get_db()

        # Create/get customer
        customer_id = await create_or_get_customer(conn, request.customer)

        # Store transaction
        tx_id = await store_transaction(
            conn,
            customer_id,
            request.amount,
            masked_pan,
            card_token,
            encrypted_chd,
        )

        logger.info(f"Transaction completed: {tx_id}")

        # Return response with minimal sensitive data
        return TransactionResponse(
            tx_id=tx_id,
            customer_id=customer_id,
            amount=request.amount,
            masked_pan=masked_pan,
            card_token=card_token,
            tx_timestamp=datetime.utcnow().isoformat(),
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Transaction processing failed: {e}")
        raise HTTPException(status_code=500, detail="Transaction processing failed")


@app.get("/transaction/{tx_id}")
async def get_transaction(tx_id: str):
    """Retrieve transaction details (masked data only)"""
    try:
        conn = await get_db()
        transaction = await conn.fetchrow(
            """
            SELECT tx_id, customer_id, tx_amount, masked_pan, card_token, tx_timestamp
            FROM transactions
            WHERE tx_id = $1
            """,
            tx_id,
        )

        if not transaction:
            raise HTTPException(status_code=404, detail="Transaction not found")

        return {
            "tx_id": transaction["tx_id"],
            "customer_id": transaction["customer_id"],
            "amount": float(transaction["tx_amount"]),
            "masked_pan": transaction["masked_pan"],
            "card_token": transaction["card_token"],
            "tx_timestamp": transaction["tx_timestamp"].isoformat(),
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Transaction retrieval failed: {e}")
        raise HTTPException(status_code=500, detail="Retrieval failed")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)