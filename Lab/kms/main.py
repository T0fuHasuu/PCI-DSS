"""
PCI-DSS Compliant Key Management Service
Handles key generation, storage, and encryption/decryption operations
"""

import os
import logging
from datetime import datetime
from typing import Dict
from cryptography.fernet import Fernet
from fastapi import FastAPI, HTTPException, Body
from pydantic import BaseModel

# Configuration
MASTER_KEY = os.getenv("MASTER_KEY", None)
KEY_STORAGE_PATH = "/app/keys"

# Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="PCI-DSS KMS", version="1.0.0")

# In-memory key storage (in production, use HSM or secure vault)
key_store: Dict[str, str] = {}


class EncryptRequest(BaseModel):
    """Encryption request"""
    plaintext: str


class EncryptResponse(BaseModel):
    """Encryption response"""
    ciphertext: str
    key_id: str
    timestamp: str


class DecryptRequest(BaseModel):
    """Decryption request"""
    ciphertext: str
    key_id: str = "default"


class DecryptResponse(BaseModel):
    """Decryption response"""
    plaintext: str
    timestamp: str


class HealthResponse(BaseModel):
    """Health check response"""
    status: str
    key_count: int


def init_keys():
    """Initialize or load encryption keys"""
    global MASTER_KEY

    if MASTER_KEY:
        logger.info("Using environment MASTER_KEY")
        key_store["default"] = MASTER_KEY
    else:
        # Generate new key for development/testing
        new_key = Fernet.generate_key().decode()
        key_store["default"] = new_key
        logger.warning("Generated new encryption key - save this for production:")
        logger.warning(f"MASTER_KEY={new_key}")

    logger.info(f"KMS initialized with {len(key_store)} key(s)")


def get_key(key_id: str = "default") -> str:
    """Retrieve key from storage"""
    if key_id not in key_store:
        logger.error(f"Key not found: {key_id}")
        raise HTTPException(status_code=404, detail="Key not found")
    return key_store[key_id]


def encrypt_data(plaintext: str, key_id: str = "default") -> str:
    """Encrypt plaintext using specified key"""
    try:
        key = get_key(key_id)
        cipher = Fernet(key.encode())
        ciphertext = cipher.encrypt(plaintext.encode())
        return ciphertext.decode()
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Encryption failed: {e}")
        raise HTTPException(status_code=500, detail="Encryption failed")


def decrypt_data(ciphertext: str, key_id: str = "default") -> str:
    """Decrypt ciphertext using specified key"""
    try:
        key = get_key(key_id)
        cipher = Fernet(key.encode())
        plaintext = cipher.decrypt(ciphertext.encode())
        return plaintext.decode()
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Decryption failed: {e}")
        raise HTTPException(status_code=500, detail="Decryption failed")


@app.on_event("startup")
async def startup_event():
    """Initialize on startup"""
    init_keys()
    logger.info("KMS service started")


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint"""
    return HealthResponse(status="healthy", key_count=len(key_store))


@app.post("/encrypt", response_model=EncryptResponse)
async def encrypt(request: EncryptRequest = Body(...)):
    """
    Encrypt plaintext data
    
    Request:
        plaintext: Data to encrypt
        
    Response:
        ciphertext: Encrypted data
        key_id: Key identifier used
        timestamp: Encryption timestamp
    """
    try:
        logger.info("Encryption request received")

        key_id = "default"
        ciphertext = encrypt_data(request.plaintext, key_id)

        logger.info(f"Encryption successful with key: {key_id}")

        return EncryptResponse(
            ciphertext=ciphertext,
            key_id=key_id,
            timestamp=datetime.utcnow().isoformat(),
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Encryption endpoint failed: {e}")
        raise HTTPException(status_code=500, detail="Encryption failed")


@app.post("/decrypt", response_model=DecryptResponse)
async def decrypt(request: DecryptRequest = Body(...)):
    """
    Decrypt ciphertext data
    
    Request:
        ciphertext: Encrypted data
        key_id: Key identifier (default: "default")
        
    Response:
        plaintext: Decrypted data
        timestamp: Decryption timestamp
    """
    try:
        logger.info(f"Decryption request received for key: {request.key_id}")

        plaintext = decrypt_data(request.ciphertext, request.key_id)

        logger.info(f"Decryption successful with key: {request.key_id}")

        return DecryptResponse(
            plaintext=plaintext,
            timestamp=datetime.utcnow().isoformat(),
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Decryption endpoint failed: {e}")
        raise HTTPException(status_code=500, detail="Decryption failed")


@app.post("/keys/generate")
async def generate_key(key_id: str = "default"):
    """Generate and store new encryption key"""
    try:
        logger.info(f"Generating new key: {key_id}")

        if key_id in key_store:
            logger.warning(f"Key {key_id} already exists, overwriting")

        new_key = Fernet.generate_key().decode()
        key_store[key_id] = new_key

        logger.info(f"Key generated and stored: {key_id}")

        return {
            "key_id": key_id,
            "status": "generated",
            "timestamp": datetime.utcnow().isoformat(),
        }
    except Exception as e:
        logger.error(f"Key generation failed: {e}")
        raise HTTPException(status_code=500, detail="Key generation failed")


@app.get("/keys/list")
async def list_keys():
    """List all key IDs (not the keys themselves)"""
    return {
        "keys": list(key_store.keys()),
        "count": len(key_store),
        "timestamp": datetime.utcnow().isoformat(),
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8001)