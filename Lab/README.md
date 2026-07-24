# PCI DSS Network Segmentation Scope-Reduction Lab

A Docker-based technical demonstration for the project **Network Segmentation
Effectiveness for PCI DSS Scope Reduction**. It models an approved payment path,
default-deny boundaries, protected account-data handling, centralized logging,
and isolated departmental networks.

> This lab demonstrates selected PCI DSS v4.0.1-aligned technical controls. It
> is not a production payment platform, a PCI DSS certification, or a substitute
> for a Qualified Security Assessor.

## Defensible scope model

```text
Browser / Demo UI -> Demo API -> POS Agent / POS
                                      |
                               WireGuard + TLS 1.2
                                      v
Perimeter FW -> DMZ Nginx -> Internal FW -> Application
                                             |       |
                                          Vault   PostgreSQL
```

- **CDE systems:** demo UI, demo API, POS agent/POS, DMZ, application,
  Vault, and PostgreSQL. These components process, transmit, or store the
  simulated account data.
- **Connected-to/security-impacting:** perimeter firewall, internal firewall,
  DNS/NTP/log server, anti-malware service, and the Docker host.
- **Candidate out of scope:** isolated departmental placeholder networks. They
  become defensibly out of scope only after segmentation validation confirms
  they cannot access or affect any CDE or security-impacting system.

The separate networks alone are not the proof. The proof is the combination of
documented flows, default-deny enforcement, absence of unauthorized paths,
firewall evidence, and repeatable segmentation testing.

See [docs/SCOPE-REGISTER.md](docs/SCOPE-REGISTER.md) and
[docs/NETWORK-MATRIX.md](docs/NETWORK-MATRIX.md).

## Windows 10/11 — Docker Desktop

Requirements:

- Docker Desktop using the **WSL 2 backend** and **Linux containers**
- Windows PowerShell (included with Windows)
- At least 4 GB of memory available to Docker Desktop
- `/dev/net/tun` available inside Docker Desktop for WireGuard

Open **Command Prompt** in the project folder:

```cmd
lab.cmd up
```

The command performs the full startup workflow:

1. Checks Docker Desktop, Compose v2, Linux-container mode, and `/dev/net/tun`.
2. Creates a local `.env` with a cryptographically random database password.
3. Generates the lab CA, service certificates, and WireGuard keys inside Docker.
4. Validates Compose, builds the images, waits for health checks, and verifies
   the dashboard and anti-malware service.

Open:

```text
https://localhost:8443
```

The dashboard is bound to `127.0.0.1` only. The browser will show a certificate
warning unless the generated lab CA is trusted locally.

Useful Windows commands:

```cmd
lab.cmd status
lab.cmd verify
lab.cmd config
lab.cmd topology
lab.cmd logs
lab.cmd down
lab.cmd reset --yes
lab.cmd regenerate-secrets --yes
```

`topology` starts the optional departmental and jumpbox placeholders. They are
excluded from normal startup because they are topology markers, not implemented
access-control systems.

See [docs/WINDOWS-RUNBOOK.md](docs/WINDOWS-RUNBOOK.md) for troubleshooting.

## Linux

```bash
chmod +x lab.sh
./lab.sh up
```

Linux host commands remain available:

```bash
./lab.sh status
./lab.sh verify
./lab.sh config
./lab.sh topology
./lab.sh demo
./lab.sh deny-test
./lab.sh av-test
./lab.sh av-scan
./lab.sh time
./lab.sh down
```

The existing evidence scripts are retained. Further segmentation test scripting
can be added separately without changing the core transaction path.

## Implemented control layers

- User-defined Docker networks represent Retail, DMZ, application, KMS,
  database, UI, security-tool, administrative, and departmental zones.
- Perimeter and internal boundaries use stateful, default-deny `iptables`
  policies with NFLOG evidence.
- The transaction path uses WireGuard, TLS 1.2, and mTLS on sensitive internal
  service connections.
- Nginx restricts routes, methods, request sizes, rates, certificates, and
  client-certificate subjects.
- Vault Transit encrypts PAN/expiry data and derives an HMAC token without
  exporting key material.
- The routine Vault policy can encrypt and tokenize but cannot decrypt.
  Controlled decrypt is added only while `DEMO_EVIDENCE_ENABLED=true`.
- PostgreSQL accepts the application only through TLS 1.2 client-certificate
  authentication and stores no CVV or plaintext-PAN column.
- Centralized DNS, NTP-source validation, syslog collection, and partial
  ClamAV support are implemented without creating a routing path between zones.
- Departmental placeholders are isolated and disabled by default.

## Important limitations

- Docker networks simulate logical segmentation; they are not equivalent to a
  production design using independently administered hosts, VLANs, firewalls,
  and management planes.
- All containers share one Docker host. The host is therefore
  security-impacting and remains in scope for the conceptual assessment.
- UDP syslog is centralized but not a complete SIEM or cryptographically
  authenticated logging pipeline.
- Vault uses a single-node lab bootstrap/unseal design, not production auto-
  unseal, quorum, high availability, or dual control.
- ClamAV demonstrates scheduled/on-demand repository scanning. It does not
  prove real-time endpoint coverage, removable-media scanning, or anti-phishing.
- JumpServer/MFA, enterprise RBAC, physical security, formal incident response,
  authenticated recurring scans, and organizational processes require separate
  evidence.

Review [docs/REQUIREMENT-MAPPING.md](docs/REQUIREMENT-MAPPING.md) before making
any compliance claim.

## Data and secret safety

- Use only the bundled synthetic test values—never real PAN, CVV, customer, or
  bank data.
- `.env`, generated PKI, WireGuard keys, Vault bootstrap material, database
  volumes, and logs are not included in the release archive.
- `lab.cmd reset --yes` removes persistent Docker volumes.
- `lab.cmd regenerate-secrets --yes` replaces the local lab PKI and WireGuard
  material after the containers are stopped.

Authoritative references:

- [PCI DSS v4.0.1 document library](https://www.pcisecuritystandards.org/document_library/)
- [PCI DSS scoping and segmentation guidance](https://www.pcisecuritystandards.org/documents/Guidance-PCI-DSS-Scoping-and-Segmentation_v1.pdf)
