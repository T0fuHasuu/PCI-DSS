import json
import sqlite3
import uuid
from datetime import datetime, timezone
from typing import Dict, Optional

from cryptography.fernet import Fernet
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
import uvicorn

# =============================================================================
# Database setup (SQLite)
# =============================================================================
DATABASE = "chd_secure.db"

def get_db() -> sqlite3.Connection:
    """Return a new database connection (check_same_thread=False for dev)."""
    conn = sqlite3.connect(DATABASE, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    """Create the tables if they do not exist."""
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS customers (
            Customer_ID INTEGER PRIMARY KEY AUTOINCREMENT,
            Full_Name TEXT NOT NULL,
            Email TEXT NOT NULL,
            Phone_Number TEXT NOT NULL,
            Created_At TEXT NOT NULL
        )
    """)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS transactions (
            Tx_ID INTEGER PRIMARY KEY AUTOINCREMENT,
            Customer_ID INTEGER NOT NULL,
            Tx_Amount REAL NOT NULL,
            Masked_PAN TEXT NOT NULL,
            Card_Token TEXT NOT NULL,
            Encrypted_CHD TEXT NOT NULL,
            Tx_Timestamp TEXT NOT NULL,
            FOREIGN KEY (Customer_ID) REFERENCES customers(Customer_ID)
        )
    """)
    conn.commit()
    conn.close()

# Initialize DB on import
init_db()

# =============================================================================
# Mini KMS (Key Management Service / Encryption Component)
# =============================================================================
class MiniKMS:
    """
    Simulates a separate KMS responsible for:
    - Tokenization of PAN (Primary Account Number)
    - AES-256 encryption/decryption of cardholder data (CHD)
    """

    def __init__(self):
        # In a real deployment this key would be securely stored and rotated.
        # For this demo we generate a new key each time the server starts.
        self.fernet = Fernet(Fernet.generate_key())
        # Persistent token vault: PAN -> token (in memory only for demo)
        self.token_map: Dict[str, str] = {}

    def tokenize(self, pan: str) -> str:
        """
        Return a surrogate token for the given PAN.
        Always returns the same token for the same PAN (token vault behaviour).
        """
        if pan in self.token_map:
            return self.token_map[pan]

        # Generate a unique token prefixed with 'tok_'
        token = f"tok_{uuid.uuid4().hex[:12]}"
        self.token_map[pan] = token
        return token

    def encrypt(self, chd: dict) -> str:
        """
        Encrypt a dictionary containing CHD (e.g. PAN, expiry, CVV).
        Returns a base64‑encoded Fernet token string.
        """
        plaintext = json.dumps(chd).encode("utf-8")
        encrypted = self.fernet.encrypt(plaintext)
        return encrypted.decode("utf-8")  # returns string like "gAAAAABkX1..."

    def decrypt(self, encrypted_chd: str) -> dict:
        """
        Decrypt a previously encrypted CHD token.
        Returns the original dictionary of card data.
        """
        decrypted_bytes = self.fernet.decrypt(encrypted_chd.encode("utf-8"))
        return json.loads(decrypted_bytes.decode("utf-8"))

# Instantiate the KMS – this is our "separate" component
kms = MiniKMS()

# =============================================================================
# Pydantic models for API
# =============================================================================
class CustomerCreate(BaseModel):
    full_name: str = Field(..., alias="full_name")
    email: str
    phone_number: str

class CustomerOut(BaseModel):
    customer_id: int
    full_name: str
    email: str
    phone_number: str
    created_at: str

class CardDetails(BaseModel):
    pan: str = Field(..., description="Primary Account Number")
    expiry: str = Field(..., description="Expiry date (MM/YY)")
    cvv: Optional[str] = None
    cardholder_name: Optional[str] = None

class TransactionCreate(BaseModel):
    customer_id: int
    amount: float
    card_details: CardDetails

class TransactionOut(BaseModel):
    tx_id: int
    customer_id: int
    tx_amount: float
    masked_pan: str
    card_token: str
    encrypted_chd: str
    tx_timestamp: str

# =============================================================================
# FastAPI app
# =============================================================================
app = FastAPI(title="Secure CHD Processor", version="1.0.0")

@app.post("/customers/", response_model=CustomerOut, status_code=201)
def create_customer(customer: CustomerCreate):
    """Create a new customer record."""
    conn = get_db()
    cursor = conn.cursor()
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    try:
        cursor.execute(
            "INSERT INTO customers (Full_Name, Email, Phone_Number, Created_At) VALUES (?, ?, ?, ?)",
            (customer.full_name, customer.email, customer.phone_number, now)
        )
        conn.commit()
        new_id = cursor.lastrowid
    except Exception as e:
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))
    conn.close()
    return CustomerOut(
        customer_id=new_id,
        full_name=customer.full_name,
        email=customer.email,
        phone_number=customer.phone_number,
        created_at=now,
    )

@app.get("/customers/{customer_id}", response_model=CustomerOut)
def get_customer(customer_id: int):
    """Retrieve a customer by ID."""
    conn = get_db()
    row = conn.execute(
        "SELECT * FROM customers WHERE Customer_ID = ?", (customer_id,)
    ).fetchone()
    conn.close()
    if row is None:
        raise HTTPException(status_code=404, detail="Customer not found")
    return CustomerOut(
        customer_id=row["Customer_ID"],
        full_name=row["Full_Name"],
        email=row["Email"],
        phone_number=row["Phone_Number"],
        created_at=row["Created_At"],
    )

@app.post("/transactions/", response_model=TransactionOut, status_code=201)
def create_transaction(txn: TransactionCreate):
    """
    Process a transaction:
    1. Mask the PAN (show only last 4 digits).
    2. Obtain a token for the PAN from KMS.
    3. Encrypt the full CHD (PAN, expiry, CVV, name) using KMS.
    4. Store everything in the Transactions table.
    """
    # Validate customer exists
    conn = get_db()
    customer_row = conn.execute(
        "SELECT Customer_ID FROM customers WHERE Customer_ID = ?", (txn.customer_id,)
    ).fetchone()
    if customer_row is None:
        conn.close()
        raise HTTPException(status_code=404, detail="Customer not found")

    card = txn.card_details

    # 1. Mask PAN: keep last 4 digits, replace the rest with '*'
    pan = card.pan
    if len(pan) < 4:
        masked = "*" * len(pan)
    else:
        masked = "*" * (len(pan) - 4) + pan[-4:]

    # 2. Tokenization via KMS
    token = kms.tokenize(pan)

    # 3. Encryption of full CHD via KMS
    chd_dict = {
        "pan": pan,
        "expiry": card.expiry,
        "cvv": card.cvv,
        "cardholder_name": card.cardholder_name,
    }
    encrypted_chd = kms.encrypt(chd_dict)

    # 4. Store transaction
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    try:
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO transactions (Customer_ID, Tx_Amount, Masked_PAN, Card_Token, Encrypted_CHD, Tx_Timestamp) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (txn.customer_id, txn.amount, masked, token, encrypted_chd, now)
        )
        conn.commit()
        tx_id = cursor.lastrowid
    except Exception as e:
        conn.close()
        raise HTTPException(status_code=400, detail=str(e))
    conn.close()

    return TransactionOut(
        tx_id=tx_id,
        customer_id=txn.customer_id,
        tx_amount=txn.amount,
        masked_pan=masked,
        card_token=token,
        encrypted_chd=encrypted_chd,
        tx_timestamp=now,
    )

# Optional: decryption endpoint for testing (normally NOT exposed in production)
@app.get("/transactions/{tx_id}/decrypt")
def decrypt_transaction(tx_id: int):
    """Decrypt and return the original CHD for a given transaction (for demo purposes)."""
    conn = get_db()
    row = conn.execute(
        "SELECT Encrypted_CHD FROM transactions WHERE Tx_ID = ?", (tx_id,)
    ).fetchone()
    conn.close()
    if row is None:
        raise HTTPException(status_code=404, detail="Transaction not found")
    try:
        decrypted = kms.decrypt(row["Encrypted_CHD"])
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Decryption failed: {str(e)}")
    # DO NOT return CVV or full PAN in a production API – this is only for verification
    return {"decrypted_chd": decrypted}

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)