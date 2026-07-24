# Lab System-Hardening Baseline

This baseline supports selected Requirement 2 evidence. It is a lab standard,
not a production benchmark certification.

| Control | Required state in this repository | Verification source |
|---|---|---|
| Images | Explicit image/runtime versions; rebuild and scan after updates | Dockerfiles and external VA/SCA evidence |
| Host exposure | Publish only the dashboard and bind it to `127.0.0.1` | `docker-compose.yml` |
| Network placement | Attach each service only to required zones | Compose and scope register |
| Host firewall | Default-drop INPUT/FORWARD/OUTPUT where application flows are enforced | `scripts/start-*.sh` |
| Privileges | `no-new-privileges`; grant `NET_ADMIN` only to containers enforcing their own network policy | Compose |
| Secrets | Generate locally; never distribute `.env`, private keys, or Vault bootstrap data | `.gitignore`, `.dockerignore`, startup workflow |
| Configuration | Mount service/firewall configuration read-only | Compose volumes |
| TLS | TLS 1.2 only in this project; verify CA, hostname, client certificate, and expected client subject | Nginx, Vault, PostgreSQL, and Python TLS configs |
| Services | No SSH, shell management listener, or unused host port | Dockerfiles, Compose, port inventory |
| Application surface | Disable API documentation; restrict methods/routes/body size; no sensitive-body logs | FastAPI and Nginx configs |
| Data | Synthetic test data only; never log PAN/CVV; do not store CVV | Application, schema, security policy |
| Logs | Centralize security metadata; restrict receiver sources; keep log service non-routing | rsyslog and log-server startup |
| Time | Containers inherit host time and validate the approved source without `CAP_SYS_TIME` | Chrony configuration |
| Change control | Revalidate Compose, images, scope register, matrix, and segmentation after material changes | Project process |

## Accepted lab exceptions

- Containers that install their own `iptables` rules require `NET_ADMIN`.
- Vault bootstrap/unseal material is kept in a local persistent volume for a
  repeatable single-node demo.
- PostgreSQL permits local trust inside its isolated container for bootstrap and
  local evidence commands; all network clients are denied except the certificate-
  authenticated application identity.
- UDP DNS, NTP, and syslog are confined to isolated networks and do not carry
  payment payloads. Their production limitations are recorded in the network
  matrix.

Every exception is limited to the isolated demonstration and must be redesigned
before production use.
