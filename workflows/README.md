## CDE Design — T495 (Arch Linux)

---

### Architecture Overview

```
INTERNET (Simulated)
        │
   [TP-Link WR940N]
   192.168.1.1 (Perimeter)
        │
        ├── 192.168.30.x → PC Win11 (Admin Workstation)
        │
        ├── 192.168.20.x → X230 (DMZ / Security)
        │                   └── Snort, Graylog, OpenVAS
        │
        └── 192.168.10.x → T495 CDE (Payment Server)
                            └── nftables (internal firewall)
                            └── Nginx (reverse proxy / TLS termination)
                            └── Flask App (payment processor)
                            └── PostgreSQL (card data store)
                            └── Vault (key management)
                            └── Telegram Alert Agent
```

---

### T495 Internal Service Layout

```
T495 — 192.168.10.10
│
├── nftables           → Firewall (port control, zone enforcement)
├── Nginx (port 443)   → TLS 1.2/1.3 only, reverse proxy
├── Flask (port 5000)  → Internal only, payment logic
├── PostgreSQL (5432)  → Internal only, encrypted card data
├── HashiCorp Vault    → Key/secret management
├── auditd             → System-level audit logging
├── rsyslog            → Log forwarding to X230
├── ClamAV             → Antivirus daemon
├── chrony             → NTP time sync
└── Telegram Agent     → Alert dispatcher
```

---

### Step-by-Step CDE Build

---

#### Step 1 — OS Baseline (T495 Arch)

```bash
# Update system
sudo pacman -Syu

# Install required packages
sudo pacman -S nginx postgresql python python-pip \
  vault audit rsyslog clamav chrony nftables \
  openssl git curl python-flask python-sqlalchemy \
  python-cryptography python-psycopg2

# Disable all unnecessary services
sudo systemctl disable bluetooth avahi-daemon cups

# Set hostname
sudo hostnamectl set-hostname cde-server
```

---

#### Step 2 — Network Zone Enforcement (nftables)

Create `/etc/nftables.conf`:

```nft
#!/usr/sbin/nft -f

flush ruleset

define CDE_IP     = 192.168.10.10
define DMZ_IP     = 192.168.20.10
define ADMIN_IP   = 192.168.30.10

table inet filter {

  chain input {
    type filter hook input priority 0; policy drop;

    # Allow established connections
    ct state established,related accept

    # Allow loopback
    iif "lo" accept

    # Allow SSH from admin workstation only
    ip saddr $ADMIN_IP tcp dport 22 accept

    # Allow HTTPS from DMZ (Nginx health check) and Admin
    ip saddr { $DMZ_IP, $ADMIN_IP } tcp dport 443 accept

    # Allow log forwarding from self to X230 (rsyslog)
    ip saddr $CDE_IP tcp dport 514 accept

    # Allow NTP
    udp dport 123 accept

    # Allow Telegram outbound (handled in output chain)

    # Drop everything else
    log prefix "INPUT-DROP: " drop
  }

  chain output {
    type filter hook output priority 0; policy drop;

    # Allow established
    ct state established,related accept

    # Allow loopback
    oif "lo" accept

    # Allow DNS
    udp dport 53 accept
    tcp dport 53 accept

    # Allow NTP
    udp dport 123 accept

    # Allow HTTPS outbound for Telegram API only
    ip daddr 149.154.160.0/20 tcp dport 443 accept
    ip daddr 91.108.4.0/22 tcp dport 443 accept

    # Allow log to X230
    ip daddr $DMZ_IP tcp dport 514 accept

    log prefix "OUTPUT-DROP: " drop
  }

  chain forward {
    type filter hook forward priority 0; policy drop;
  }
}
```

```bash
sudo systemctl enable --now nftables
```

---

#### Step 3 — TLS Setup (Nginx)

```bash
# Generate self-signed cert (use Let's Encrypt in real deployment)
sudo openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/cde.key \
  -out /etc/nginx/ssl/cde.crt \
  -subj "/CN=cde-server/O=ACLEDA-SIM/C=KH"

sudo chmod 600 /etc/nginx/ssl/cde.key
```

Create `/etc/nginx/nginx.conf`:

```nginx
server {
    listen 443 ssl;
    server_name cde-server;

    ssl_certificate     /etc/nginx/ssl/cde.crt;
    ssl_certificate_key /etc/nginx/ssl/cde.key;

    # TLS 1.2 minimum — PCI DSS Req 4
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5:!RC4;
    ssl_prefer_server_ciphers on;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header Strict-Transport-Security "max-age=31536000";

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        # Log access — PCI DSS Req 10
        access_log /var/log/nginx/cde_access.log;
        error_log  /var/log/nginx/cde_error.log;
    }
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    return 301 https://$host$request_uri;
}
```

---

#### Step 4 — PostgreSQL Setup (Card Data Store)

```bash
sudo -u postgres initdb -D /var/lib/postgres/data
sudo systemctl enable --now postgresql
sudo -u postgres psql
```

Inside psql:

```sql
-- Create restricted CDE database
CREATE DATABASE cde_payment;
CREATE USER cde_app WITH ENCRYPTED PASSWORD 'StrongPass!2024';
GRANT CONNECT ON DATABASE cde_payment TO cde_app;

-- Enable pgcrypto for column-level encryption (Req 3)
\c cde_payment
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Cardholder data table
CREATE TABLE cardholder_data (
    id              SERIAL PRIMARY KEY,
    token_id        UUID DEFAULT gen_random_uuid(),  -- token replaces PAN for display
    pan_encrypted   BYTEA NOT NULL,                  -- AES-256 encrypted PAN
    cardholder_name TEXT NOT NULL,
    expiry_month    INT NOT NULL,
    expiry_year     INT NOT NULL,
    created_at      TIMESTAMP DEFAULT NOW(),
    last_accessed   TIMESTAMP
);

-- Audit trail table (Req 10)
CREATE TABLE audit_log (
    id          SERIAL PRIMARY KEY,
    event_time  TIMESTAMP DEFAULT NOW(),
    user_id     TEXT,
    action      TEXT,
    table_name  TEXT,
    record_id   INT,
    ip_address  TEXT,
    status      TEXT
);

-- Restrict app user to minimum required (Req 7)
GRANT SELECT, INSERT ON cardholder_data TO cde_app;
GRANT INSERT ON audit_log TO cde_app;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;

\q
```

---

#### Step 5 — HashiCorp Vault (Key Management — Req 3.6 & 3.7)

```bash
# Install and initialize Vault
sudo systemctl enable --now vault

# Initialize
vault operator init -key-shares=3 -key-threshold=2

# Store the 3 unseal keys and root token securely
# In real deployment these go to separate custodians

# Unseal (requires 2 of 3 keys)
vault operator unseal <key1>
vault operator unseal <key2>

# Login
vault login <root_token>

# Create encryption key for PAN data
vault secrets enable transit
vault write -f transit/keys/pan-encryption-key type=aes256-gcm96

# Create a policy for the Flask app
vault policy write cde-app-policy - <<EOF
path "transit/encrypt/pan-encryption-key" { capabilities = ["update"] }
path "transit/decrypt/pan-encryption-key" { capabilities = ["update"] }
EOF

# Create app token
vault token create -policy=cde-app-policy -ttl=24h
```

---

#### Step 6 — Flask Payment Application

Create `/opt/cde-app/app.py`:

```python
from flask import Flask, request, jsonify, g
import psycopg2
import hvac          # pip install hvac
import logging
import datetime
import os
import requests      # for Telegram
import hashlib
import re

app = Flask(__name__)

# ── Config ──────────────────────────────────────────────
DB_CONFIG = {
    "dbname": "cde_payment",
    "user": "cde_app",
    "password": os.environ.get("DB_PASSWORD"),
    "host": "127.0.0.1",
    "port": 5432
}
VAULT_ADDR  = "http://127.0.0.1:8200"
VAULT_TOKEN = os.environ.get("VAULT_TOKEN")

# ── Logging ──────────────────────────────────────────────
logging.basicConfig(
    filename="/var/log/cde-app/app.log",
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

# ── Helpers ──────────────────────────────────────────────
def get_db():
    return psycopg2.connect(**DB_CONFIG)

def get_vault():
    return hvac.Client(url=VAULT_ADDR, token=VAULT_TOKEN)

def luhn_check(pan: str) -> bool:
    """Validate PAN format before processing."""
    pan = pan.replace(" ", "")
    if not re.fullmatch(r"\d{13,19}", pan):
        return False
    total = 0
    reverse = pan[::-1]
    for i, digit in enumerate(reverse):
        n = int(digit)
        if i % 2 == 1:
            n *= 2
            if n > 9:
                n -= 9
        total += n
    return total % 10 == 0

def mask_pan(pan: str) -> str:
    """Return masked PAN for logging — never log full PAN."""
    return pan[:6] + "*" * (len(pan) - 10) + pan[-4:]

def encrypt_pan(vault_client, pan: str) -> str:
    result = vault_client.secrets.transit.encrypt_data(
        name="pan-encryption-key",
        plaintext=pan.encode().hex()
    )
    return result["data"]["ciphertext"]

def decrypt_pan(vault_client, ciphertext: str) -> str:
    result = vault_client.secrets.transit.decrypt_data(
        name="pan-encryption-key",
        ciphertext=ciphertext
    )
    return bytes.fromhex(result["data"]["plaintext"]).decode()

def write_audit(conn, user_id, action, table, record_id, ip, status):
    with conn.cursor() as cur:
        cur.execute("""
            INSERT INTO audit_log
              (user_id, action, table_name, record_id, ip_address, status)
            VALUES (%s, %s, %s, %s, %s, %s)
        """, (user_id, action, table, record_id, ip, status))
    conn.commit()

# ── Routes ───────────────────────────────────────────────
@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "zone": "CDE"}), 200


@app.route("/api/v1/tokenize", methods=["POST"])
def tokenize_card():
    """Accept raw PAN, validate, encrypt, store token, return token only."""
    data     = request.get_json()
    pan      = data.get("pan", "")
    name     = data.get("cardholder_name", "")
    exp_m    = data.get("expiry_month")
    exp_y    = data.get("expiry_year")
    user_id  = data.get("user_id", "anonymous")
    client_ip = request.remote_addr

    # Input validation
    if not luhn_check(pan):
        send_telegram_alert(
            level="WARNING",
            event="Invalid PAN submitted",
            detail=f"User: {user_id} | IP: {client_ip} | PAN: {mask_pan(pan)}"
        )
        return jsonify({"error": "Invalid card number"}), 400

    try:
        vault  = get_vault()
        conn   = get_db()

        encrypted_pan = encrypt_pan(vault, pan)

        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO cardholder_data
                  (pan_encrypted, cardholder_name, expiry_month, expiry_year)
                VALUES (%s, %s, %s, %s)
                RETURNING token_id, id
            """, (encrypted_pan, name, exp_m, exp_y))
            token_id, record_id = cur.fetchone()
        conn.commit()

        write_audit(conn, user_id, "TOKENIZE", "cardholder_data",
                    record_id, client_ip, "SUCCESS")

        send_telegram_alert(
            level="INFO",
            event="Card Tokenized",
            detail=f"Token: {token_id} | PAN: {mask_pan(pan)} | User: {user_id}"
        )

        logging.info(f"TOKENIZE SUCCESS | user={user_id} | pan={mask_pan(pan)} | token={token_id}")
        return jsonify({"token": str(token_id), "masked_pan": mask_pan(pan)}), 200

    except Exception as e:
        logging.error(f"TOKENIZE FAIL | {str(e)}")
        send_telegram_alert(
            level="CRITICAL",
            event="Tokenization Failed",
            detail=str(e)
        )
        return jsonify({"error": "Internal error"}), 500


@app.route("/api/v1/process", methods=["POST"])
def process_payment():
    """Simulate payment processing using token, never raw PAN."""
    data     = request.get_json()
    token    = data.get("token")
    amount   = data.get("amount")
    user_id  = data.get("user_id", "anonymous")
    client_ip = request.remote_addr

    if not token or not amount:
        return jsonify({"error": "Missing fields"}), 400

    try:
        conn = get_db()
        with conn.cursor() as cur:
            cur.execute("""
                SELECT id, pan_encrypted, cardholder_name
                FROM cardholder_data
                WHERE token_id = %s
            """, (token,))
            row = cur.fetchone()

        if not row:
            send_telegram_alert(
                level="WARNING",
                event="Invalid Token Used",
                detail=f"Token: {token} | User: {user_id} | IP: {client_ip}"
            )
            return jsonify({"error": "Token not found"}), 404

        record_id = row[0]

        # Simulate authorization (replace with real payment gateway in production)
        auth_code = hashlib.sha256(f"{token}{amount}".encode()).hexdigest()[:8].upper()

        write_audit(conn, user_id, "PROCESS_PAYMENT", "cardholder_data",
                    record_id, client_ip, "SUCCESS")

        send_telegram_alert(
            level="INFO",
            event="Payment Processed",
            detail=f"Token: {token} | Amount: {amount} | Auth: {auth_code} | User: {user_id}"
        )

        logging.info(f"PAYMENT | token={token} | amount={amount} | auth={auth_code}")
        return jsonify({"auth_code": auth_code, "status": "APPROVED"}), 200

    except Exception as e:
        logging.error(f"PAYMENT FAIL | {str(e)}")
        send_telegram_alert(level="CRITICAL", event="Payment Processing Error", detail=str(e))
        return jsonify({"error": "Internal error"}), 500


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=False)
```

---

#### Step 7 — Telegram Alert System

Create `/opt/cde-app/telegram_alerts.py`:

```python
import requests
import datetime
import os

# ── Configuration ────────────────────────────────────────
# Set these as environment variables, never hardcode
TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHATS = {
    "admin":    os.environ.get("TG_ADMIN_CHAT_ID"),    # IT Security Admin
    "ops":      os.environ.get("TG_OPS_CHAT_ID"),      # Operations team
    "audit":    os.environ.get("TG_AUDIT_CHAT_ID"),    # Compliance/Audit channel
}

# ── Alert Routing Logic ──────────────────────────────────
ALERT_ROUTING = {
    "INFO":     ["ops"],
    "WARNING":  ["ops", "admin"],
    "CRITICAL": ["ops", "admin", "audit"],
    "AUDIT":    ["audit", "admin"],
    "BREACH":   ["ops", "admin", "audit"],   # All channels immediately
}

LEVEL_EMOJI = {
    "INFO":     "ℹ️",
    "WARNING":  "⚠️",
    "CRITICAL": "🚨",
    "AUDIT":    "📋",
    "BREACH":   "🔴🔴🔴",
}

def send_telegram_alert(level: str, event: str, detail: str, extra: dict = None):
    """
    level  : INFO | WARNING | CRITICAL | AUDIT | BREACH
    event  : Short event name
    detail : What happened
    extra  : Optional dict for additional fields
    """
    if not TELEGRAM_BOT_TOKEN:
        return

    emoji     = LEVEL_EMOJI.get(level, "📌")
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    targets   = ALERT_ROUTING.get(level, ["admin"])

    message = (
        f"{emoji} *[{level}] CDE ALERT*\n"
        f"━━━━━━━━━━━━━━━━━━\n"
        f"🕐 *Time:* `{timestamp}`\n"
        f"📌 *Event:* {event}\n"
        f"📝 *Detail:* {detail}\n"
    )

    if extra:
        for k, v in extra.items():
            message += f"🔹 *{k}:* {v}\n"

    message += "━━━━━━━━━━━━━━━━━━"

    for target in targets:
        chat_id = TELEGRAM_CHATS.get(target)
        if not chat_id:
            continue
        try:
            requests.post(
                f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage",
                json={
                    "chat_id":    chat_id,
                    "text":       message,
                    "parse_mode": "Markdown"
                },
                timeout=5
            )
        except Exception as e:
            # Fail silently — never let alert failure break payment flow
            pass
```

Import this in `app.py`:

```python
from telegram_alerts import send_telegram_alert
```

---

#### Alert Types and Who Gets Them

| Event | Level | Who Gets It |
|-------|-------|-------------|
| Card tokenized successfully | INFO | Ops |
| Payment processed | INFO | Ops |
| Invalid PAN submitted | WARNING | Ops + Admin |
| Invalid token used | WARNING | Ops + Admin |
| Failed login attempt to CDE | WARNING | Ops + Admin |
| Multiple failed logins (brute force) | CRITICAL | Ops + Admin + Audit |
| Tokenization/payment system error | CRITICAL | Ops + Admin + Audit |
| Root login detected | CRITICAL | Ops + Admin + Audit |
| File integrity change (AIDE) | AUDIT | Audit + Admin |
| New user created on CDE | AUDIT | Audit + Admin |
| `sudo` usage on CDE | AUDIT | Audit + Admin |
| Daily compliance summary | AUDIT | Audit + Admin |
| Antivirus threat detected | BREACH | Everyone |
| IDS alert triggered | BREACH | Everyone |
| Vault seal/unseal event | BREACH | Everyone |

---

#### Step 8 — auditd Rules (Req 10 — Track Everything)

Add to `/etc/audit/rules.d/cde.rules`:

```bash
# Delete all existing rules
-D

# Audit all authentication events
-w /etc/pam.d/ -p wa -k pam_changes
-w /etc/passwd -p wa -k user_modification
-w /etc/shadow -p rw -k shadow_access
-w /etc/sudoers -p wa -k sudoers_changes

# Audit CDE application files
-w /opt/cde-app/ -p rwxa -k cde_app_access
-w /var/log/cde-app/ -p rwa -k cde_log_access

# Audit PostgreSQL data directory
-w /var/lib/postgres/ -p rwa -k postgres_data

# Audit Vault config
-w /etc/vault.d/ -p wa -k vault_config

# Audit network config
-w /etc/nftables.conf -p wa -k firewall_change

# Track sudo usage
-a always,exit -F arch=b64 -S execve -F euid=0 -k root_commands

# Track SSH logins
-w /var/log/auth.log -p rwa -k auth_log
```

```bash
sudo augenrules --load
sudo systemctl enable --now auditd
```

#### Wire auditd → Telegram

Create `/opt/cde-app/audit_watcher.py` (runs as a service):

```python
import subprocess
import time
from telegram_alerts import send_telegram_alert

WATCH_KEYS = {
    "firewall_change":   ("CRITICAL", "Firewall Configuration Changed"),
    "sudoers_changes":   ("CRITICAL", "Sudoers File Modified"),
    "user_modification": ("AUDIT",    "User Account Modified"),
    "cde_app_access":    ("AUDIT",    "CDE Application File Accessed"),
    "vault_config":      ("CRITICAL", "Vault Configuration Changed"),
    "root_commands":     ("WARNING",  "Root Command Executed"),
}

def tail_audit():
    proc = subprocess.Popen(
        ["ausearch", "-k", ",".join(WATCH_KEYS.keys()), "--input-logs", "-i"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    while True:
        line = proc.stdout.readline().decode("utf-8", errors="ignore")
        if not line:
            time.sleep(5)
            continue
        for key, (level, event) in WATCH_KEYS.items():
            if key in line:
                send_telegram_alert(level=level, event=event, detail=line.strip()[:300])
                break

if __name__ == "__main__":
    tail_audit()
```

---

#### Step 9 — Environment Variables (Never Hardcode Secrets)

Create `/etc/systemd/system/cde-app.service`:

```ini
[Unit]
Description=CDE Payment Application
After=network.target postgresql.service vault.service

[Service]
Type=simple
User=cde-user
WorkingDirectory=/opt/cde-app
EnvironmentFile=/etc/cde-app/secrets.env
ExecStart=/usr/bin/python app.py
Restart=on-failure
RestartSec=5

# Security hardening (Req 2)
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ReadWritePaths=/var/log/cde-app

[Install]
WantedBy=multi-user.target
```

Create `/etc/cde-app/secrets.env` (chmod 600, root owned):

```env
DB_PASSWORD=StrongPass!2024
VAULT_TOKEN=<your-vault-token>
TELEGRAM_BOT_TOKEN=<your-bot-token>
TG_ADMIN_CHAT_ID=<admin-chat-id>
TG_OPS_CHAT_ID=<ops-chat-id>
TG_AUDIT_CHAT_ID=<audit-chat-id>
```

```bash
sudo chmod 600 /etc/cde-app/secrets.env
sudo chown root:root /etc/cde-app/secrets.env
```

---

#### Step 10 — Telegram Bot Setup (Quick)

1. Message `@BotFather` on Telegram → `/newbot` → get token
2. Create 3 group chats: `CDE-Ops`, `CDE-Admin`, `CDE-Audit`
3. Add your bot to each group
4. Get chat IDs:
```bash
curl "https://api.telegram.org/bot<TOKEN>/getUpdates"
# Find chat.id for each group
```
5. Put values in `secrets.env`

---

### What This Simulates vs Real Bank

| This Lab | Real Bank Equivalent |
|----------|---------------------|
| T495 (single server) | Clustered payment servers |
| nftables | Dedicated hardware firewall (Cisco/Fortinet) |
| Nginx reverse proxy | Load balancer + WAF appliance |
| HashiCorp Vault | HSM (Hardware Security Module) |
| PostgreSQL + pgcrypto | PCI-compliant payment database |
| Flask app | Core banking payment module |
| Telegram alerts | SIEM + SOC notification system |
| X230 IDS | Dedicated IDS/IPS appliance |
| Self-signed cert | CA-signed certificate |
| Single zone router | VLAN-capable managed switch |

The logic, security controls, data flow, encryption, audit trail, and alerting are all equivalent — only the hardware scale differs. This makes it a valid reference for real implementations.