-- Lab schema. This is a technical demonstration, not a PCI DSS compliance claim.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cde_user') THEN
        CREATE ROLE cde_user LOGIN;
    END IF;
END
$$;

CREATE TABLE IF NOT EXISTS customers (
    customer_id BIGSERIAL PRIMARY KEY,
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS transactions (
    tx_id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    tx_amount NUMERIC(10, 2) NOT NULL CHECK (tx_amount > 0),
    authorization_status VARCHAR(16) NOT NULL CHECK (authorization_status IN ('approved', 'declined')),
    masked_pan VARCHAR(19) NOT NULL,
    card_token TEXT NOT NULL,
    encrypted_chd TEXT NOT NULL,
    vault_key_version INTEGER NOT NULL CHECK (vault_key_version > 0),
    tx_timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_customers_email
    ON customers(email);
CREATE INDEX IF NOT EXISTS idx_transactions_customer_id
    ON transactions(customer_id);
CREATE INDEX IF NOT EXISTS idx_transactions_timestamp
    ON transactions(tx_timestamp);
CREATE INDEX IF NOT EXISTS idx_transactions_token
    ON transactions(card_token);

GRANT CONNECT ON DATABASE cde_db TO cde_user;
GRANT USAGE ON SCHEMA public TO cde_user;
GRANT SELECT, INSERT, UPDATE ON customers TO cde_user;
GRANT SELECT, INSERT ON transactions TO cde_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cde_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE ON TABLES TO cde_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO cde_user;
