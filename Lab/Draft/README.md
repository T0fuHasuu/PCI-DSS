# PCI-DSS Compliant CDE Simulation

A secure, containerized Cardholder Data Environment (CDE) simulation demonstrating PCI-DSS compliance best practices.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    PCI-DSS CDE Environment                  │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────┐ │
│  │ Application      │  │ Key Management   │  │ Database   │ │
│  │ Server (app.py)  │  │ Service (kms.py) │  │ PostgreSQL │ │
│  │                  │  │                  │  │            │ │
│  │ VLAN 110         │  │ VLAN 120         │  │ VLAN 130   │ │
│  │ 10.100.10.10/24  │  │ 10.100.20.10/24  │  │ 10.100.30. │ │
│  │ Port: 8000       │  │ Port: 8001       │  │ Port: 5432 │ │
│  └──────────────────┘  └──────────────────┘  └────────────┘ │
│         ↓                      ↑                      ↑       │
│         └──────────────────────┴──────────────────────┘       │
│              Segmented Networks (Docker)                      │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. Application Server (app.py)
- **Purpose**: Process transaction data, handle PAN masking, tokenization, and encryption
- **Framework**: FastAPI with async/await
- **Port**: 8000
- **Functions**:
  - Accept transaction requests with customer and card data
  - Validate input data
  - Mask PAN (keep only last 4 digits)
  - Generate unique card tokens
  - Encrypt sensitive cardholder data via KMS
  - Store transactions with minimal sensitive data
  - Retrieve transaction details (masked data only)

### 2. Key Management Service (kms.py)
- **Purpose**: Handle encryption/decryption and key management
- **Framework**: FastAPI
- **Port**: 8001
- **Functions**:
  - Generate encryption keys
  - Store keys securely
  - Encrypt plaintext data
  - Decrypt ciphertext data
  - List key identifiers

### 3. PostgreSQL Database
- **Port**: 5432
- **Database**: cde_db
- **User**: cde_user
- **Tables**:
  - `customers`: Customer information (not sensitive)
  - `transactions`: Transaction records with encrypted CHD

### 4. Network Segmentation (Docker Networks)
Three isolated Docker networks simulate VLANs:
- **VLAN 110 (vlan110)**: Application Server network (10.100.10.0/24)
- **VLAN 120 (vlan120)**: KMS network (10.100.20.0/24)
- **VLAN 130 (vlan130)**: Database network (10.100.30.0/24)

## Setup and Deployment

### Prerequisites
- Docker
- Docker Compose
- curl (for testing)
- jq (for JSON parsing in tests)
- Bash

### Installation

1. **Clone or download the project**
```bash
cd pci-dss-cde
```

2. **Make test script executable**
```bash
chmod +x test.sh
```

3. **Build and start services**
```bash
docker-compose up -d
```

4. **Wait for services to be ready** (first startup may take 30-60 seconds)
```bash
docker-compose logs -f app
```

### Services Status

```bash
# Check all services
docker-compose ps

# View logs
docker-compose logs app      # Application logs
docker-compose logs kms      # KMS logs
docker-compose logs postgres # Database logs

# Access database
docker-compose exec postgres psql -U cde_user -d cde_db
```

## API Endpoints

### Health Check
```
GET /health
Response: {
  "status": "healthy",
  "kms_status": "healthy",
  "database_status": "healthy"
}
```

### Process Transaction
```
POST /process-transaction
Content-Type: application/json

Request:
{
  "customer": {
    "full_name": "John Doe",
    "email": "john@example.com",
    "phone_number": "+1-202-555-1234"
  },
  "card": {
    "pan": "4532123456789999",
    "exp_month": 12,
    "exp_year": 2026,
    "cvv": "123"
  },
  "amount": 99.99
}

Response:
{
  "tx_id": "1001",
  "customer_id": 1,
  "amount": 99.99,
  "masked_pan": "************9999",
  "card_token": "tok_a91f33d7e2c4f891",
  "tx_timestamp": "2026-03-01T10:10:00.123456"
}
```

### Retrieve Transaction
```
GET /transaction/{tx_id}

Response:
{
  "tx_id": "1001",
  "customer_id": 1,
  "amount": 99.99,
  "masked_pan": "************9999",
  "card_token": "tok_a91f33d7e2c4f891",
  "tx_timestamp": "2026-03-01T10:10:00.123456"
}
```

## Testing

### Run Full Test Suite
```bash
./test.sh
```

This will run:
1. Health check
2. Valid transaction processing
3. Transaction retrieval
4. Invalid input validation
5. Duplicate customer handling
6. PAN masking verification
7. Card token generation

### Manual Testing with curl

**Health Check:**
```bash
curl http://localhost:8000/health | jq
```

**Process Transaction:**
```bash
curl -X POST http://localhost:8000/process-transaction \
  -H "Content-Type: application/json" \
  -d '{
    "customer": {
      "full_name": "Srey Neang",
      "email": "neang@mail.com",
      "phone_number": "+85512345604"
    },
    "card": {
      "pan": "4532123456789999",
      "exp_month": 12,
      "exp_year": 2026,
      "cvv": "123"
    },
    "amount": 120.50
  }' | jq
```

**Retrieve Transaction:**
```bash
curl http://localhost:8000/transaction/1 | jq
```

## Data Flow

### Transaction Processing Flow

```
1. POS System sends transaction request
           ↓
2. Application validates input
           ↓
3. PAN is masked (show only last 4 digits)
           ↓
4. Card token is generated
           ↓
5. Sensitive CHD is encrypted via KMS
           ↓
6. Customer record is created/retrieved from DB
           ↓
7. Transaction is stored in DB with:
   - Masked PAN (safe to store)
   - Card Token (for reference)
   - Encrypted CHD (cryptographically protected)
           ↓
8. Response returns only masked/tokenized data
```

### Database Storage

**Customers Table:**
```
customer_id | full_name    | email           | phone_number    | created_at
1           | Srey Neang   | neang@mail.com  | +85512345604    | 2026-02-15...
```

**Transactions Table:**
```
tx_id | customer_id | tx_amount | masked_pan        | card_token    | encrypted_chd         | tx_timestamp
1001  | 1           | 120.50    | ************4242  | tok_a91f33... | gAAAAABkX1...Q29u... | 2026-03-01...
```

## Security Features

✓ **Input Validation**: Strict Pydantic models validate all inputs
✓ **PAN Masking**: Only last 4 digits stored in plain text
✓ **Tokenization**: Each card gets a unique token
✓ **Encryption**: Sensitive CHD encrypted using Fernet (symmetric encryption)
✓ **Key Management**: Separate KMS service handles encryption keys
✓ **Network Segmentation**: Docker networks simulate VLAN isolation
✓ **Database Security**: Row-level security enabled, proper permissions
✓ **Logging**: Comprehensive logging for audit trails
✓ **Health Checks**: Services self-health reporting

## Configuration

### Environment Variables

Set in docker-compose.yml or .env file:

```
KMS_HOST=kms              # KMS service hostname
KMS_PORT=8001             # KMS service port
DB_HOST=postgres          # Database hostname
DB_PORT=5432              # Database port
DB_NAME=cde_db            # Database name
DB_USER=cde_user          # Database user
DB_PASSWORD=SecurePass123!# Database password
```

### Master Key (KMS)

On first run, KMS generates a new encryption key. For production:
```bash
export MASTER_KEY="your-fernet-key-here"
docker-compose up -d
```

## Database Queries

```sql
-- View all customers
SELECT * FROM customers;

-- View all transactions
SELECT tx_id, customer_id, tx_amount, masked_pan, tx_timestamp FROM transactions;

-- View transactions for a customer
SELECT * FROM transactions WHERE customer_id = 1;

-- Count transactions
SELECT COUNT(*) FROM transactions;
```

## Stopping Services

```bash
# Stop all services (data persists)
docker-compose stop

# Stop and remove containers (data persists in volumes)
docker-compose down

# Stop and remove everything including data
docker-compose down -v
```

## Troubleshooting

**Connection refused errors:**
- Services take 10-30 seconds to start. Wait longer before testing.
- Check logs: `docker-compose logs`

**Database connection errors:**
- Ensure postgres service is running: `docker-compose ps`
- Check database credentials in docker-compose.yml

**Encryption failures:**
- Verify KMS is healthy: `curl http://localhost:8001/health`
- Check KMS logs: `docker-compose logs kms`

**Test script issues:**
- Ensure script is executable: `chmod +x test.sh`
- Install jq: `apt-get install jq` or `brew install jq`

## Performance Considerations

- Connection pooling enabled (min: 1, max: 10)
- Async/await for non-blocking I/O
- Indexed database queries on frequently accessed columns
- Keep-alive enabled on HTTP connections

## Files Structure

```
.
├── app.py                 # FastAPI application server
├── kms.py                 # Key Management Service
├── requirements.txt       # Python dependencies
├── Dockerfile             # Container image definition
├── docker-compose.yml     # Multi-container orchestration
├── init_db.sql           # Database schema initialization
├── test.sh               # Automated test suite
├── .env.example          # Environment configuration template
└── README.md             # This file
```

## Compliance References

- **PCI-DSS 3.2.1**: Render PAN unreadable (masking implemented)
- **PCI-DSS 3.4**: Render CHD unreadable (encryption implemented)
- **PCI-DSS 6.5.10**: Input validation (Pydantic validation)
- **PCI-DSS 8.2**: Strong authentication (future enhancement)
- **PCI-DSS 12.3**: Network segmentation (Docker networks)

## Future Enhancements

- [ ] TLS/SSL certificate support
- [ ] API authentication (API keys, OAuth)
- [ ] Advanced logging and monitoring
- [ ] Database encryption at rest
- [ ] Hardware Security Module (HSM) integration
- [ ] PCI-DSS audit reporting
- [ ] Backup and disaster recovery
- [ ] Load balancing
- [ ] Rate limiting
- [ ] Request signing and verification

## License

This project is provided as-is for educational and testing purposes.

## Support

For issues or questions, review the logs:
```bash
docker-compose logs -f
```

Check individual service logs:
```bash
docker-compose logs app
docker-compose logs kms
docker-compose logs postgres
```
