# PCI DSS Lab Environment: Context, Architecture & Parameters

## 1. Project Overview & Objectives

- **Project Title:** Network Segmentation Effectiveness for PCI DSS Scope Reduction
- **Target Standard:** Selected technical controls aligned with **PCI DSS v4.0.1**
- **Core Objective:** Demonstrate how logical network segmentation, default-deny firewall boundaries, encrypted transit, cryptographic tokenization/isolation, and centralized infrastructure reduce the compliance assessment boundary (scope reduction) from a flat network down to a defensible Cardholder Data Environment (CDE).
- **Scope Metric:**
  - **Flat Baseline:** 20 total components in scope (Docker host + 12 core services + 7 placeholder networks).
  - **Segmented Lab Model:** 13 in scope (7 CDE + 5 Connected-to/Security-Impacting + 1 Docker Host); 7 candidate exclusions (isolated departmental VLANs 51–56 + jumpbox).

---

## 2. Scope Classification Register

| Component | Category | Justification | Assessment In-Scope? |
|---|---|---|---|
| **Docker Desktop / Host** | Connected-to / Security-Impacting | Daemon controls all containers, volumes, namespaces, and secrets | Yes |
| **Demo UI** (`demo-ui`) | CDE | Terminates browser TLS and captures simulated PAN/CVV | Yes |
| **Demo API** (`demo-api`) | CDE | Validates and relays account-data requests to the POS agent | Yes |
| **POS Agent / POS** (`pos`, `pos-agent`) | CDE | Processes and transmits cardholder data via WireGuard VPN | Yes |
| **DMZ Proxy** (`dmz`) | CDE | Terminates payment TLS, holds clear payload in memory, proxies upstream | Yes |
| **Application** (`app`) | CDE | Processes PAN/CVV, invokes Vault cryptographic services, writes to DB | Yes |
| **Vault KMS** (`kms`) | CDE | Processes PAN/expiry, stores encryption keys, executes tokenization/encryption | Yes |
| **PostgreSQL** (`db`) | CDE | Persists encrypted CHD, token, masked PAN, and transaction metadata | Yes |
| **Perimeter Firewall** (`peri-fw`) | Connected-to / Security-Impacting | Enforces outer boundary, terminates VPN transport, default-deny filtering | Yes |
| **Internal Firewall** (`int-fw`) | Connected-to / Security-Impacting | Enforces CDE boundary between DMZ and Application, default-deny filtering | Yes |
| **Log / DNS / NTP Server** (`log-server`) | Connected-to / Security-Impacting | Provides core DNS, time synchronization, and audit syslog to CDE | Yes |
| **Anti-Malware** (`antimalware`) | Connected-to / Security-Impacting | Scans source/config repositories and forwards detection alerts | Yes (to Req 5) |
| **Jumpbox Placeholder** (`jumpbox`) | Candidate Out-of-Scope | Disabled topology placeholder; no CDE path (in-scope if made functional) | Excluded pending validation |
| **VLAN 51–56 Placeholders** (Dept nets) | Candidate Out-of-Scope | Completely isolated subnets with no routes to CDE or shared services | Excluded pending validation |

---

## 3. Network Topology & Trust Zones

### Docker Networks

| Network Name | Subnet | Gateway | Type | Zone Classification | Connected Containers |
|---|---|---|---|---|---|
| `store_net` | `192.168.10.0/24` | `192.168.10.1` | Internal bridge | Retail / POS Zone | `pos`, `demo-api`, `peri-fw`, `log-server` |
| `dmz_net` | `10.0.10.0/24` | `10.0.10.253` | Internal bridge | DMZ Zone | `peri-fw`, `dmz`, `int-fw`, `log-server` |
| `app_net` | `10.100.10.0/24` | `10.100.10.254` | Internal bridge | CDE Application Zone | `int-fw`, `app`, `log-server` |
| `kms_net` | `10.100.20.0/24` | `10.100.20.254` | Internal bridge | Key Management Zone | `app`, `kms`, `log-server` |
| `db_net` | `10.100.30.0/24` | `10.100.30.254` | Internal bridge | Database Zone | `app`, `db`, `log-server` |
| `ui_net` | `172.30.10.0/24` | `172.30.10.1` | Bridge | Demo Control Zone | `demo-ui`, `demo-api` |
| `security_tools_net` | `172.31.10.0/24` | `172.31.10.1` | Bridge | Security Tools Zone | `antimalware`, `log-server` |
| `vlan99_net` | `10.50.99.0/24` | None | Internal bridge | Administrative (Placeholder) | `jumpbox-zone` (profile: topology) |
| `vlan51_net`–`vlan56_net` | `10.50.51.0/24`–`10.50.56.0/24` | None | Internal bridge | Departmental Out-of-Scope | `branch-manager`, `operation-manager`, `compliance-officer`, `finance-manager`, `it-department`, `it-security` |

### VPN Overlay Network (WireGuard)

- **Subnet:** `10.255.0.0/24`
- **Perimeter Firewall (`peri-fw`):** `10.255.0.1/24`, Listen Port UDP `51820`
- **POS (`pos`):** `10.255.0.2/24`, Listen Port UDP `51821`, Endpoint `192.168.10.254:51820`
- **Encryption:** X25519 key exchange, ChaCha20-Poly1305 authenticated tunnel

---

## 4. Container & Service Parameters

| Container Name | Static IP(s) | Base Image | Security Profile / Capabilities | Core Function & Listeners |
|---|---|---|---|---|
| `demo-ui` | `172.30.10.10` | `nginx:1.30.3-alpine3.23` | `no-new-privileges:true` | Web frontend, publishes `127.0.0.1:8443` on host, proxies `/api/` to `demo-api` |
| `demo-api` | `172.30.10.20`, `192.168.10.30` | `python:3.12-alpine3.22` | `NET_ADMIN`, `no-new-privileges:true` | FastAPI controller on TCP `9000` behind Nginx on TCP `9443` (TLS 1.2 + mTLS) |
| `pos` | `192.168.10.20`, `10.255.0.2` (wg0) | `alpine:3.22.5` | `NET_ADMIN`, `/dev/net/tun` | WireGuard client endpoint, iptables firewall, exports status to `/run/pos-status` |
| `pos-agent` | Shares netns with `pos` | `python:3.12-alpine3.22` | `no-new-privileges:true` | FastAPI agent on TCP `9001` behind Nginx on TCP `9444` (mTLS, DN: `demo-api-controller`) |
| `peri-fw` | `192.168.10.254`, `10.0.10.1`, `10.255.0.1` (wg0) | `alpine:3.22.5` | `NET_ADMIN`, `/dev/net/tun`, `ip_forward: 1` | WireGuard server, default-deny iptables, NFLOG forwarder, `socat` TCP 443 -> DMZ |
| `dmz` | `10.0.10.10` | `alpine:3.22.5` | `NET_ADMIN`, `no-new-privileges:true` | Nginx reverse proxy on TCP `443` (`payment.gateway`), limits rate (10 r/s), forwards to App via `int-fw` |
| `int-fw` | `10.0.10.254`, `10.100.10.1` | `alpine:3.22.5` | `NET_ADMIN`, `ip_forward: 1` | Default-deny iptables, NFLOG forwarder, `socat` TCP 8443 -> App, rejects TCP 9443 |
| `app` | `10.100.10.10`, `10.100.20.20`, `10.100.30.20` | `python:3.12-alpine3.22` | `NET_ADMIN`, `no-new-privileges:true`, `ip_forward: 0` | Nginx TCP 8443 (mTLS DN check: `dmz-proxy`) + FastAPI TCP 8000. Manages Vault AppRole & PostgreSQL TLS |
| `kms` | `10.100.20.10` | `hashicorp/vault:1.21.4` | `NET_ADMIN`, `no-new-privileges:true` | HashiCorp Vault on TCP `8200` (TLS 1.2). Transit engine, AppRole auth, UDP audit socket |
| `db` | `10.100.30.10` | `postgres:16.14-alpine3.23` | `NET_ADMIN`, `no-new-privileges:true` | PostgreSQL 16 on TCP `5432` (TLS 1.2, cert authentication for user `cde_user`, `log_statement='none'`) |
| `log-server` | `.200` across all functional subnets | `alpine:3.22.5` | `NET_ADMIN`, `no-new-privileges:true`, `ip_forward: 0` | Authoritative DNS (`dnsmasq` 53), NTP server (`chrony` 123), Syslog receiver (`rsyslog` UDP 514) |
| `antimalware` | `172.31.10.10` | `alpine:3.22.5` | `no-new-privileges:true` | ClamAV engine, FreshClam updater (12h), daily repo scan (`/scan`), EICAR detector |

---

## 5. Approved Network Traffic Matrix (Allowlist)

| Flow ID | Source IP / Entity | Destination IP / Entity | Port / Protocol | Security Enforcement | Purpose |
|---|---|---|---|---|---|
| **A01** | Host Browser | `127.0.0.1` (`demo-ui`) | TCP `8443` | TLS 1.2, loopback only | User dashboard / terminal UI |
| **A02** | `demo-ui` (`172.30.10.10`) | `demo-api` (`172.30.10.20`) | TCP `9443` | TLS 1.2 + mTLS (DN: `demo-ui-proxy`) | Relay transaction to controller |
| **A03** | `demo-api` (`192.168.10.30`) | `pos-agent` (`192.168.10.20`) | TCP `9444` | TLS 1.2 + mTLS (DN: `demo-api-controller`) | Execute POS transaction workflow |
| **A04** | `pos` (`192.168.10.20`) | `peri-fw` (`192.168.10.254`) | UDP `51820` | WireGuard authenticated encryption | Secure tunnel transport across store net |
| **A05** | `pos` wg0 (`10.255.0.2`) | `peri-fw` wg0 (`10.255.0.1`) | TCP `443` | TLS 1.2 inside WireGuard tunnel | Payment request to `payment.gateway` |
| **A06** | `peri-fw` (`10.0.10.1`) | `dmz` (`10.0.10.10`) | TCP `443` | TCP passthrough (`socat`) | Forward payment TLS to DMZ proxy |
| **A07** | `dmz` (`10.0.10.10`) | `int-fw` (`10.0.10.254`) | TCP `8443` | TLS 1.2 + mTLS (`dmz-client`) | Forward authorized payment to internal FW |
| **A08** | `int-fw` (`10.100.10.1`) | `app` (`10.100.10.10`) | TCP `8443` | TCP passthrough (`socat`), mTLS at App Nginx | Forward to CDE Application boundary |
| **A09** | `app` (`10.100.20.20`) | `kms` (`10.100.20.10`) | TCP `8200` | TLS 1.2 + mTLS + AppRole auth | Encrypt CHD & derive HMAC token |
| **A10** | `app` (`10.100.30.20`) | `db` (`10.100.30.10`) | TCP `5432` | PostgreSQL TLS 1.2 + Client Cert (`cde_user`) | Persist protected transaction record |
| **A11** | In-scope components | Local `log-server` (`.200`) | UDP/TCP `53` | Direct interface on subnet, source allowlist | Lab authoritative DNS resolution |
| **A12** | In-scope components | Local `log-server` (`.200`) | UDP `123` | Direct interface on subnet, source allowlist | NTP synchronization & offset monitoring |
| **A13** | In-scope components | Local `log-server` (`.200`) | UDP `514` | Direct interface on subnet, source allowlist | Centralized audit & firewall log collection |
| **A14** | `antimalware` (`172.31.10.10`) | `log-server` (`172.31.10.200`) | UDP `514` | Isolated security tools network | ClamAV scan/update/EICAR event logging |
| **A15** | `antimalware` | FreshClam upstream | HTTPS/DNS | Container egress | ClamAV signature database updates |

---

## 6. Cardholder Data & Key Protection Architecture (Req 3 & 4)

### Data Handling Flow
1. **SAD / CVV Handling:** 
   - Received in-memory by FastAPI (`app/main.py`).
   - Evaluated for simulated authorization.
   - Immediately overwritten in memory (`request.card.cvv = ""` and `cvv = ""`).
   - Never sent to Vault, never written to disk, and no CVV column exists in PostgreSQL (`transactions` table).
2. **PAN Masking:**
   - Evaluated as `*` padding up to the last 4 digits (`mask_pan(pan)`).
   - Displayed and logged only as masked PAN (e.g., `************1111`).
3. **PAN Tokenization:**
   - Vault Transit HMAC engine derives SHA-256 HMAC using key `payment-token`.
   - Application formats opaque surrogate token: `tok_<sha256_hash_prefix>`.
4. **CHD Encryption:**
   - JSON payload `{"pan": "...", "exp_month": .., "exp_year": ..}` encrypted via Vault Transit key `payment-chd` (`aes256-gcm96`).
   - Key attributes: `exportable=false`, `allow_plaintext_backup=false`, `auto_rotate_period=720h`.
   - Resulting ciphertext formatted as `vault:v<version>:<base64_ciphertext>`.
5. **Vault Least-Privilege Policy:**
   - Standard application token policy (`payment-app`): Grants `create` / `update` on `transit/encrypt/payment-chd` and `transit/hmac/payment-token/*`. Decrypt capability is completely absent.
   - Controlled decryption policy (`payment-evidence`): Enabled only when `DEMO_EVIDENCE_ENABLED=true` to allow the evidence endpoint (`/transaction/{id}/evidence`) to verify ciphertext integrity.
6. **Database Persistence:**
   - Table `transactions` schema: `tx_id`, `customer_id`, `tx_amount`, `authorization_status`, `masked_pan`, `card_token`, `encrypted_chd`, `vault_key_version`, `tx_timestamp`.
   - Authentication strictly requires TLS 1.2 client certificate with `CN=cde_user` (`pg_hba.conf`).
   - Statements are unlogged (`log_statement='none'`) in `postgresql.conf` to prevent CHD leakage into log streams.

---

## 7. Firewall & Defense-in-Depth Mechanisms

- **Stateful Default-Deny:** All firewalls (`peri-fw`, `int-fw`) enforce `INPUT DROP`, `FORWARD DROP`, `OUTPUT DROP` with explicit stateful rules (`ESTABLISHED,RELATED`).
- **NFLOG + ulogd + rsyslog Pipeline:**
  - Blocked and allowed packets are directed to `NFLOG --nflog-group 2` with prefixes (`PERI_FW_ALLOW`, `PERI_FW_DROP`, `INT_FW_ALLOW`, `INT_FW_DROP`).
  - Rate-limited using iptables conntrack limits (`limit 30/minute burst 20` for allow, `limit 12/minute burst 6` for drops).
  - Forwarded via local `rsyslogd` to central `log-server:514` (UDP).
- **mTLS with DN Filtering:**
  - Nginx at `app` enforces client certificates signed by the Lab CA and explicitly validates Common Names: `CN=(dmz-proxy|app-healthcheck)`.
  - Nginx at `demo-api` validates `CN=(demo-ui-proxy|demo-api-controller)`.
  - Nginx at `pos-agent` validates `CN=demo-api-controller`.
- **Non-Routing Infrastructure Server:**
  - `log-server` attaches to 6 subnets simultaneously but has Linux kernel forwarding disabled (`net.ipv4.ip_forward: 0`) and iptables policies dropping FORWARD packets, preventing inter-zone bridging.

---

## 8. Cryptographic Materials & Secrets Configuration

All certificates and keys are generated dynamically during initial startup via `scripts/generate-lab-secrets.sh` (or `lab.cmd` / `lab.sh`) and excluded from source control:

- **Root CA:** RSA 3072-bit, SHA-256 (`/C=KH/O=PCI Segmentation Lab/CN=PCI Lab Root CA`), valid 3650 days.
- **Service Certs:** RSA 3072-bit, SHA-256, valid 825 days, strictly isolated per service:
  - `dmz`: `server.crt` (`payment.gateway`, `10.0.10.10`, `10.255.0.1`), `client.crt` (`CN=dmz-proxy`).
  - `app`: `server.crt` (`app.internal`, `10.100.10.10`), `vault-client.crt` (`CN=payment-app`), `db-client.crt` (`CN=cde_user`), `health-client.crt` (`CN=app-healthcheck`).
  - `kms`: `server.crt` (`vault.internal`, `10.100.20.10`), `admin-client.crt` (`CN=vault-bootstrap`).
  - `db`: `server.crt` (`db.internal`, `10.100.30.10`).
  - `demo-ui`: `server.crt` (`pci-demo.local`, `localhost`, `127.0.0.1`), `client.crt` (`CN=demo-ui-proxy`).
  - `demo-api`: `server.crt` (`demo-api.internal`), `client.crt` (`CN=demo-api-controller`).
  - `pos-agent`: `server.crt` (`pos-agent.internal`).
- **WireGuard Keypairs:** Generated via `wg genkey` or OpenSSL X25519; private keys stored with `0600` permissions.
- **Database Password:** Generated cryptographically (`openssl rand -hex 32`) into `.env`.
- **Vault Bootstrap Data:** Unseal keys and root token generated at first boot into persistent volume `vault_bootstrap` (`init.json`, permissions `0600`).

---

## 9. Operating Commands & Demo Scripts

Managed via `lab.sh` (Linux) or `lab.cmd` (Windows):

| Action | Command | Purpose |
|---|---|---|
| **Start Lab** | `./lab.sh up` or `lab.cmd up` | Generates secrets/.env, builds containers, starts services, waits for health checks |
| **Verify Status** | `./lab.sh verify` | Validates demo UI endpoint, anti-malware status, and container states |
| **Run Transaction** | `./lab.sh demo` | Executes synthetic transaction through POS and reports status & tx_id |
| **Deny / Drop Test** | `./lab.sh deny-test` | Tests store-to-perimeter drop (`PERI_FW_DROP`) and DMZ-to-int-fw reject (`INT_FW_DROP`) |
| **Anti-Malware Test**| `./lab.sh av-test` | Tests ClamAV detection of isolated EICAR test string and logs alert |
| **On-Demand Scan** | `./lab.sh av-scan` | Triggers immediate recursive scan of mounted repository files |
| **Time Validation** | `./lab.sh time` | Prints UTC timestamp, Stratum, and offset across all components via Chrony |
| **Topology View** | `./lab.sh topology` | Boots the 7 isolated out-of-scope and jumpbox placeholder containers |
| **Follow Logs** | `./lab.sh logs` | Tails live Docker logs |
| **Stop Lab** | `./lab.sh down` | Gracefully stops containers without destroying volumes |
| **Reset Environment**| `./lab.sh reset --yes` | Wipes all containers, networks, and persistent Docker volumes |
| **Regen Secrets** | `./lab.sh regenerate-secrets --yes` | Regenerates PKI and WireGuard keys after stopping containers |

---

## 10. PCI DSS v4.0.1 Requirement Mapping Summary

| Requirement Area | Honest Implementation Status | Boundary & Limitations |
|---|---|---|
| **Req 1 (Network Security Controls)** | **Lab Implemented** | Stateful default-deny, dual firewall boundaries, network isolation, documented network matrix. (Docker bridge simulation, not physical hardware). |
| **Req 2 (Secure Configurations)** | **Partial Lab Implementation** | Hardened base images (Alpine), no-new-privileges, unneeded ports eliminated, read-only config mounts. (Host OS governance external). |
| **Req 3 (Account Data Protection)** | **Lab Implemented** | Zero SAD/CVV retention, PAN masking, Vault Transit AES-256-GCM encryption, HMAC tokenization, non-exportable keys. (Single-node Vault). |
| **Req 4 (Protect Cardholder Data in Transit)** | **Lab Implemented** | WireGuard VPN, strict TLS 1.2 across all internal links, mTLS with client certificate DN validation. |
| **Req 5 (Anti-Malware)** | **Partial Lab Implementation** | ClamAV repository scanning, FreshClam scheduled updates, EICAR alerting. (No real-time endpoint or removable media protection). |
| **Req 6 (Secure Systems & Software)** | **Partial / External Evidence** | Minimal attack surface, input validation, CSP headers. (Full SAST/DAST/ASV vulnerability scans handled as referenced external evidence). |
| **Req 7 & 8 (Access Control & Identification)** | **Referenced / Not Implemented** | Jumpbox container is an isolated topology placeholder; production MFA/SSO/IAM is external. |
| **Req 10 (Logging & Monitoring)** | **Partial Lab Implementation** | Centralized rsyslog for firewall, transaction, and malware events; Chrony time synchronization. (No complete SIEM, FIM, or 12-month retention pipeline). |
| **Req 11 (Security Testing)** | **Referenced External Evidence** | Multi-position Nmap and vulnerability scans retained as external project evidence. |
| **Req 12 (Governance & Policy)** | **Documented / External** | Scope register, network matrix, hardware/software inventory documented. (Incident response exercises and enterprise policies are organizational). |
