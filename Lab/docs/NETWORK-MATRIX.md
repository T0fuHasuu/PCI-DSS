# Approved Service, Protocol, and Port Matrix

This is the allowlist for the runtime lab. Anything not listed is denied by a
host firewall policy, absent from the Docker topology, or both.

| ID | Source | Destination | Port / protocol | Protection | Purpose | Approval |
|---|---|---|---|---|---|---|
| A01 | Host browser | Demo UI `127.0.0.1` | TCP 8443 | TLS 1.2; loopback-only publish | Local payment demonstration | Lab owner |
| A02 | Demo UI `172.30.10.10` | Demo API `172.30.10.20` | TCP 9443 | TLS 1.2 + mTLS + client-subject restriction | Submit the synthetic transaction | Lab owner |
| A03 | Demo API `192.168.10.30` | POS/agent `192.168.10.20` | TCP 9444 | TLS 1.2 + mTLS + client-subject restriction | Drive the POS workflow | Lab owner |
| A04 | POS `192.168.10.20` | Perimeter `192.168.10.254` | UDP 51820 | WireGuard authenticated encryption | VPN transport | Lab owner |
| A05 | POS WG `10.255.0.2` | Perimeter WG `10.255.0.1` | TCP 443 | TLS 1.2 inside WireGuard | Payment request | Lab owner |
| A06 | Perimeter `10.0.10.1` | DMZ `10.0.10.10` | TCP 443 | TLS pass-through | Forward approved payment TLS only | Lab owner |
| A07 | DMZ `10.0.10.10` | Internal FW `10.0.10.254` | TCP 8443 | TLS 1.2 + mTLS | Approved CDE application path | Lab owner |
| A08 | Internal FW `10.100.10.1` | App `10.100.10.10` | TCP 8443 | TLS pass-through; mTLS ends at App Nginx | CDE application service | Lab owner |
| A09 | App `10.100.20.20` | Vault `10.100.20.10` | TCP 8200 | TLS 1.2 + mTLS + AppRole | Encrypt CHD and derive HMAC token | Lab owner |
| A10 | App `10.100.30.20` | PostgreSQL `10.100.30.10` | TCP 5432 | TLS 1.2 + client-certificate authentication | Store protected transaction record | Lab owner |
| A11 | In-scope components | Infrastructure interface in same zone | UDP/TCP 53 | Isolated network + source allowlist | Authoritative lab DNS | Lab owner |
| A12 | In-scope components | Infrastructure interface in same zone | UDP 123 | Isolated network + source allowlist | NTP-source validation | Lab owner |
| A13 | In-scope components | Infrastructure interface in same zone | UDP 514 | Isolated network + source allowlist; no CHD bodies logged | Central audit collection | Lab owner |
| A14 | Anti-malware `172.31.10.10` | Log server `172.31.10.200` | UDP 514 | Dedicated security-tool network | ClamAV events | Lab owner |
| A15 | Anti-malware | ClamAV update service | HTTPS/DNS egress as required by FreshClam | Vendor signature validation | Signature updates | Lab owner |

## Required protocols without native confidentiality

| Protocol | Why retained | Compensating lab restriction | Residual limitation |
|---|---|---|---|
| DNS 53 | Resolves authoritative lab-only names | Per-zone interface, source allowlist, no upstream forwarding | DNS is not authenticated |
| NTP 123 | Correlates event time without changing the host clock | Per-zone interface and source allowlist | Lab source is not authenticated or redundant |
| Syslog UDP 514 | Low-overhead centralized evidence | Per-zone interface, source allowlist, metadata-only audit design | No delivery guarantee, transport authentication, or message integrity |

These three protocols do not carry PAN or CVV. Their use is acceptable only for
this isolated demonstration. A production design should use authenticated DNS
where appropriate, approved redundant time sources, and protected reliable log
transport such as TLS with integrity monitoring.

## Explicitly prohibited paths

- Departmental or jumpbox placeholder networks to any CDE or supporting system.
- Store network directly to DMZ, application, Vault, or PostgreSQL services.
- DMZ directly to Vault or PostgreSQL.
- Vault to PostgreSQL or PostgreSQL to Vault.
- Any externally published CDE service other than the dashboard on host
  loopback.
- Plaintext payment application traffic across a Docker network.

Review this matrix after every topology, service, port, certificate, or firewall
change. Validation evidence must use the same source, destination, and port
identifiers.
