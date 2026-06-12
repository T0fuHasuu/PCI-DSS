#!/bin/bash

# PCI-DSS CDE Simulation - Transaction Flow Test Script
# Simulates POS traffic and verifies complete transaction processing

set -e

# Configuration
APP_URL="http://localhost:8000"
TIMEOUT=10
VERBOSE=true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Check if application is ready
check_health() {
    log_info "Checking application health..."
    
    for i in {1..30}; do
        if curl -s "${APP_URL}/health" > /dev/null 2>&1; then
            log_success "Application is ready"
            return 0
        fi
        log_warning "Waiting for application... attempt $i/30"
        sleep 2
    done
    
    log_error "Application health check failed after 60 seconds"
    return 1
}

# Display health status
display_health() {
    log_info "Application Health Status:"
    HEALTH=$(curl -s "${APP_URL}/health")
    echo "$HEALTH" | jq '.'
}

# Test 1: Health Check
test_health_check() {
    log_info "TEST 1: Health Check"
    
    RESPONSE=$(curl -s -w "\n%{http_code}" "${APP_URL}/health")
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ]; then
        log_success "Health check passed (HTTP $HTTP_CODE)"
        echo "$BODY" | jq '.'
        return 0
    else
        log_error "Health check failed (HTTP $HTTP_CODE)"
        echo "$BODY"
        return 1
    fi
}

# Test 2: Process Transaction (Valid)
test_valid_transaction() {
    log_info "TEST 2: Process Valid Transaction"
    
    TRANSACTION_PAYLOAD=$(cat <<'EOF'
{
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
}
EOF
)
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        "${APP_URL}/process-transaction" \
        -H "Content-Type: application/json" \
        -d "$TRANSACTION_PAYLOAD")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ]; then
        log_success "Transaction processed successfully (HTTP $HTTP_CODE)"
        echo "$BODY" | jq '.'
        
        # Extract TX_ID for later use
        TX_ID=$(echo "$BODY" | jq -r '.tx_id')
        echo "TX_ID=$TX_ID"
        return 0
    else
        log_error "Transaction processing failed (HTTP $HTTP_CODE)"
        echo "$BODY" | jq '.'
        return 1
    fi
}

# Test 3: Retrieve Transaction
test_retrieve_transaction() {
    log_info "TEST 3: Retrieve Transaction Details"
    
    # Get the TX_ID from the previous test
    TRANSACTION_PAYLOAD=$(cat <<'EOF'
{
  "customer": {
    "full_name": "John Doe",
    "email": "john@example.com",
    "phone_number": "+12025551234"
  },
  "card": {
    "pan": "5425233010103010",
    "exp_month": 6,
    "exp_year": 2027,
    "cvv": "456"
  },
  "amount": 99.99
}
EOF
)
    
    TX_RESPONSE=$(curl -s -X POST \
        "${APP_URL}/process-transaction" \
        -H "Content-Type: application/json" \
        -d "$TRANSACTION_PAYLOAD")
    
    TX_ID=$(echo "$TX_RESPONSE" | jq -r '.tx_id')
    
    if [ -z "$TX_ID" ] || [ "$TX_ID" = "null" ]; then
        log_error "Failed to create transaction for retrieval test"
        return 1
    fi
    
    log_info "Retrieving transaction: $TX_ID"
    
    RESPONSE=$(curl -s -w "\n%{http_code}" "${APP_URL}/transaction/${TX_ID}")
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ]; then
        log_success "Transaction retrieved successfully (HTTP $HTTP_CODE)"
        echo "$BODY" | jq '.'
        return 0
    else
        log_error "Transaction retrieval failed (HTTP $HTTP_CODE)"
        echo "$BODY"
        return 1
    fi
}

# Test 4: Invalid Input Validation
test_invalid_transaction() {
    log_info "TEST 4: Invalid Transaction (Input Validation)"
    
    INVALID_PAYLOAD=$(cat <<'EOF'
{
  "customer": {
    "full_name": "",
    "email": "invalid-email",
    "phone_number": "123"
  },
  "card": {
    "pan": "1234",
    "exp_month": 13,
    "exp_year": 2023,
    "cvv": "12"
  },
  "amount": -50.00
}
EOF
)
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        "${APP_URL}/process-transaction" \
        -H "Content-Type: application/json" \
        -d "$INVALID_PAYLOAD")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "422" ]; then
        log_success "Invalid input properly rejected (HTTP $HTTP_CODE)"
        echo "$BODY" | jq '.'
        return 0
    else
        log_error "Invalid input validation failed (Expected 422, got $HTTP_CODE)"
        echo "$BODY"
        return 1
    fi
}

# Test 5: Duplicate Customer Handling
test_duplicate_customer() {
    log_info "TEST 5: Duplicate Customer Handling"
    
    CUSTOMER_EMAIL="duplicate@mail.com"
    
    # First transaction
    PAYLOAD1=$(cat <<EOF
{
  "customer": {
    "full_name": "Test User",
    "email": "$CUSTOMER_EMAIL",
    "phone_number": "+12025551111"
  },
  "card": {
    "pan": "4111111111111111",
    "exp_month": 3,
    "exp_year": 2028,
    "cvv": "789"
  },
  "amount": 50.00
}
EOF
)
    
    TX1=$(curl -s -X POST "${APP_URL}/process-transaction" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD1")
    
    CUSTOMER_ID_1=$(echo "$TX1" | jq -r '.customer_id')
    
    # Second transaction with same email
    PAYLOAD2=$(cat <<EOF
{
  "customer": {
    "full_name": "Test User Updated",
    "email": "$CUSTOMER_EMAIL",
    "phone_number": "+12025552222"
  },
  "card": {
    "pan": "4222222222222222",
    "exp_month": 9,
    "exp_year": 2029,
    "cvv": "321"
  },
  "amount": 75.00
}
EOF
)
    
    TX2=$(curl -s -X POST "${APP_URL}/process-transaction" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD2")
    
    CUSTOMER_ID_2=$(echo "$TX2" | jq -r '.customer_id')
    
    if [ "$CUSTOMER_ID_1" = "$CUSTOMER_ID_2" ]; then
        log_success "Duplicate customer correctly identified (Customer ID: $CUSTOMER_ID_1)"
        echo "$TX1" | jq '{tx_id, customer_id, masked_pan}'
        echo "$TX2" | jq '{tx_id, customer_id, masked_pan}'
        return 0
    else
        log_error "Duplicate customer handling failed (IDs: $CUSTOMER_ID_1 vs $CUSTOMER_ID_2)"
        return 1
    fi
}

# Test 6: PAN Masking Verification
test_pan_masking() {
    log_info "TEST 6: PAN Masking Verification"
    
    PAN="6011123456789012"
    EXPECTED_MASKED="************9012"
    
    PAYLOAD=$(cat <<EOF
{
  "customer": {
    "full_name": "Mask Test",
    "email": "mask@test.com",
    "phone_number": "+12025559999"
  },
  "card": {
    "pan": "$PAN",
    "exp_month": 11,
    "exp_year": 2025,
    "cvv": "654"
  },
  "amount": 25.00
}
EOF
)
    
    RESPONSE=$(curl -s -X POST "${APP_URL}/process-transaction" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD")
    
    MASKED_PAN=$(echo "$RESPONSE" | jq -r '.masked_pan')
    
    if [ "$MASKED_PAN" = "$EXPECTED_MASKED" ]; then
        log_success "PAN correctly masked: $MASKED_PAN"
        return 0
    else
        log_error "PAN masking incorrect. Expected: $EXPECTED_MASKED, Got: $MASKED_PAN"
        return 1
    fi
}

# Test 7: Card Token Generation
test_card_token() {
    log_info "TEST 7: Card Token Generation"
    
    PAYLOAD=$(cat <<'EOF'
{
  "customer": {
    "full_name": "Token Test",
    "email": "token@test.com",
    "phone_number": "+12025558888"
  },
  "card": {
    "pan": "3782822463100005",
    "exp_month": 7,
    "exp_year": 2030,
    "cvv": "987"
  },
  "amount": 150.75
}
EOF
)
    
    RESPONSE=$(curl -s -X POST "${APP_URL}/process-transaction" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD")
    
    CARD_TOKEN=$(echo "$RESPONSE" | jq -r '.card_token')
    
    if [[ $CARD_TOKEN =~ ^tok_[0-9a-f]{16}$ ]]; then
        log_success "Card token correctly generated: $CARD_TOKEN"
        return 0
    else
        log_error "Card token format invalid: $CARD_TOKEN"
        return 1
    fi
}

# Main execution
main() {
    clear
    echo "=========================================="
    echo "PCI-DSS CDE Simulation - Test Suite"
    echo "=========================================="
    echo ""
    
    # Check health before running tests
    if ! check_health; then
        log_error "Cannot proceed without healthy application"
        exit 1
    fi
    
    echo ""
    display_health
    echo ""
    
    # Run tests
    FAILED=0
    PASSED=0
    
    # Run each test
    if test_health_check; then ((PASSED++)); else ((FAILED++)); fi
    echo ""
    
    if test_valid_transaction; then ((PASSED++)); else ((FAILED++)); fi
    echo ""
    
    if test_retrieve_transaction; then ((PASSED++)); else ((FAILED++)); fi
    echo ""
    
    if test_invalid_transaction; then ((PASSED++)); else ((FAILED++)); fi
    echo ""
    
    if test_duplicate_customer; then ((PASSED++)); else ((FAILED++)); fi
    echo ""
    
    if test_pan_masking; then ((PASSED++)); else ((FAILED++)); fi
    echo ""
    
    if test_card_token; then ((PASSED++)); else ((FAILED++)); fi
    echo ""
    
    # Summary
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    log_success "Passed: $PASSED"
    
    if [ $FAILED -gt 0 ]; then
        log_error "Failed: $FAILED"
        exit 1
    else
        log_success "All tests passed!"
        exit 0
    fi
}

# Run main function
main "$@"