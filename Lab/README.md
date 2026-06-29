# PCI Segmentation Lab — Working Set

This is a Docker Compose demonstration of routed network segmentation around a small Cardholder Data Environment. It is a technical lab, not a claim of PCI DSS certification.

## Implemented path

```text
POS
  -> WireGuard VPN
  -> perimeter firewall
  -> DMZ Nginx TLS 1.2 reverse proxy
  -> internal firewall
  -> application Nginx mTLS 1.2
  -> FastAPI application
       -> HashiCorp Vault Transit over mTLS 1.2
       -> PostgreSQL over TLS 1.2 and client certificates
```

The combined `log-server` also provides isolated lab DNS, local NTP, and UDP syslog collection.

## First start on Windows

Run from the extracted project directory:

```bat
scripts\fresh-start.cmd
```

That command removes old lab state, regenerates PKI and WireGuard material, builds all images, and starts the stack.

Do not reuse old Vault volumes with this release. Vault bootstrap metadata and storage must be reset together.

## Normal start and stop

```bat
docker compose up -d
docker compose ps

docker compose stop
docker compose start
```

## Verify

```bat
scripts\verify-lab.cmd
```

Manual checks:

```bat
docker compose ps
docker compose logs --tail=150 kms
docker compose logs --tail=100 app
docker compose logs --tail=100 db
```

A successful first Vault bootstrap ends with:

```text
[kms] Vault TLS listener is available (HTTP 501)
[kms] Initializing new Vault storage
[kms] Vault initialized for lab use
[kms] Unsealing Vault
[kms] Vault is initialized, unsealed, and active
[kms] Configuring Transit secrets engine
[kms] Configuring AppRole
[kms] Configuring UDP audit forwarding
[kms] Vault Transit, AppRole, and UDP audit forwarding configured
```

HTTP 501 is expected only before initialization. Vault uses it to indicate an uninitialized node. The bootstrap script then initializes and unseals it through the API.

## Services and addresses

| Service | Address | Purpose |
|---|---:|---|
| `pos` | `192.168.10.20` / VPN `10.255.0.2` | Test payment origin |
| `peri-fw` | `192.168.10.254`, `10.0.10.1` / VPN `10.255.0.1` | VPN termination and routed filtering |
| `dmz` | `10.0.10.10:443` | TLS 1.2 reverse proxy |
| `int-fw` | `10.0.10.254`, `10.100.10.1` | CDE ingress filtering |
| `app` | `10.100.10.10`, `10.100.20.20`, `10.100.30.20` | Payment processing boundary |
| `kms` | `10.100.20.10:8200` | Vault Transit and AppRole |
| `db` | `10.100.30.10:5432` | PostgreSQL TLS storage |
| `log-server` | `.200` on each segment | UDP syslog, DNS, and NTP |

## Data handling

The application accepts test PAN, expiry, and CVV data. It then:

1. Uses CVV only for a simulated in-memory authorization check.
2. Excludes CVV from Vault encryption and database storage.
3. Masks the PAN.
4. Encrypts PAN and expiry through Vault Transit.
5. Creates an opaque token through Vault HMAC.
6. Stores masked PAN, token, Vault ciphertext, key version, amount, and status.

Use test card data only.

## Central logs

```bat
docker compose exec log-server sh -lc "find /var/log/remote -type f -print"
docker compose exec log-server sh -lc "tail -n 50 /var/log/remote/*/*.log"
```

UDP syslog is intentionally restricted to known source addresses. It is not encrypted or delivery-guaranteed, so application logs must never contain PAN, CVV, Vault tokens, unseal keys, or request bodies.

## Important lab limitations

- Docker bridge networks simulate VLAN/security zones; they are not 802.1Q VLANs.
- The Docker host remains security-impacting.
- Vault uses a one-share, one-threshold bootstrap for lab automation.
- The Vault unseal key and initial root token are stored in a protected named volume for restart automation.
- Real deployments should use proper auto-unseal, external secret delivery, hardened hosts, HA Vault, protected logging transport, and independent segmentation testing.

## POS transaction and encryption verification

After all containers are healthy, run:

```bat
scripts\transaction-test.cmd
```

The script performs a real request from the `pos` container through WireGuard,
the perimeter firewall, DMZ Nginx, internal firewall, and the application. It
then verifies the PostgreSQL row, copies only the Vault ciphertext to the KMS
container, decrypts it under the lab root token, and confirms that CVV/SAD was
not included in the encrypted or persisted CHD structure.
