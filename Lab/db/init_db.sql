-- PCI-DSS Compliant Database Schema
-- Contains customer and transaction data with proper constraints

-- Create CUSTOMERS table
CREATE TABLE IF NOT EXISTS customers (
    customer_id SERIAL PRIMARY KEY,
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create TRANSACTIONS table
CREATE TABLE IF NOT EXISTS transactions (
    tx_id BIGSERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    tx_amount DECIMAL(10, 2) NOT NULL,
    masked_pan VARCHAR(19) NOT NULL,
    card_token VARCHAR(255) NOT NULL,
    encrypted_chd TEXT NOT NULL,
    tx_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_customers_email ON customers(email);
CREATE INDEX IF NOT EXISTS idx_transactions_customer_id ON transactions(customer_id);
CREATE INDEX IF NOT EXISTS idx_transactions_timestamp ON transactions(tx_timestamp);
CREATE INDEX IF NOT EXISTS idx_transactions_token ON transactions(card_token);

-- Set up proper permissions (for production)
GRANT CONNECT ON DATABASE cde_db TO cde_user;
GRANT USAGE ON SCHEMA public TO cde_user;
GRANT CREATE ON SCHEMA public TO cde_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO cde_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cde_user;

-- Enable row-level security (optional, for additional compliance)
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;