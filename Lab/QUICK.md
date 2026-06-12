# Quick Start Guide

## One-Step Deployment

```bash
# 1. Start all services
docker-compose up -d

# 2. Wait for services to initialize (30-60 seconds)
sleep 30

# 3. Run tests
chmod +x test.sh
./test.sh

# 4. Done! Services are running on:
#    - Application: http://localhost:8000
#    - KMS: http://localhost:8001
#    - Database: localhost:5432
```

## Verify Setup

```bash
# Check health
curl http://localhost:8000/health | jq

# Process a transaction
curl -X POST http://localhost:8000/process-transaction \
  -H "Content-Type: application/json" \
  -d '{
    "customer": {
      "full_name": "Test User",
      "email": "test@example.com",
      "phone_number": "+12025551234"
    },
    "card": {
      "pan": "4532123456789999",
      "exp_month": 12,
      "exp_year": 2026,
      "cvv": "123"
    },
    "amount": 99.99
  }' | jq
```

## Useful Commands

```bash
# View logs
docker-compose logs -f

# Access database
docker-compose exec postgres psql -U cde_user -d cde_db

# Query transactions
docker-compose exec postgres psql -U cde_user -d cde_db -c "SELECT * FROM transactions;"

# Stop services
docker-compose stop

# Restart services
docker-compose restart

# Remove everything
docker-compose down -v
```

## Expected Output

Health Check Response:
```json
{
  "status": "healthy",
  "kms_status": "healthy",
  "database_status": "healthy"
}
```

Transaction Response:
```json
{
  "tx_id": "1",
  "customer_id": 1,
  "amount": 99.99,
  "masked_pan": "************9999",
  "card_token": "tok_a1b2c3d4e5f6g7h8",
  "tx_timestamp": "2026-03-01T10:15:30.123456"
}
```

## Data Privacy

✓ PAN is masked (only last 4 digits in plain text)
✓ CVV is never stored
✓ Card data is encrypted before storage
✓ Only tokenized references in transaction logs

See README.md for detailed documentation.