# Security Policy

## Intended use

This repository is for controlled education and demonstration. Use only synthetic payment data and isolated lab systems.

## Do not commit

- `.env`
- Private keys or generated certificates
- Vault bootstrap data or root tokens
- Database credentials
- Real PAN, CVV, customer, or bank data
- Production logs or internal network information

The distributed ZIP must contain only `secrets/README.md` under `secrets/`.
Run `lab.cmd up` or `lab.sh up` to generate local runtime material.

## Scope safety

Do not label a system out of scope merely because it is on a separate Docker
network. Use `docs/SCOPE-REGISTER.md`, validate every possible path, and treat
the Docker host as security-impacting.

## Reporting issues

Report security defects privately to the repository owner before opening a public issue. Include the affected file, reproduction steps, and expected impact. Do not include real secrets or cardholder data.
