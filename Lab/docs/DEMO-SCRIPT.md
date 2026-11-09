# PCI DSS Network Segmentation Lab Demo

Run commands from the repository root.

## 1. Start and verify

```bash
./lab.sh
```

Show status:

```bash
./lab.sh status
```

## 2. Show trust zones

```bash
./scripts/demo/show-zones.sh
```

Main zones:

- `store_net`: Retail/POS
- `dmz_net`: Perimeter and DMZ
- `app_net`: CDE application
- `kms_net`: Vault KMS
- `db_net`: PostgreSQL
- `ui_net`: Demonstration UI
- `security_tools_net`: ClamAV and centralized anti-malware logging

## 3. Open the dashboard

```bash
xdg-open https://localhost:8443
```

## 4. Show WireGuard

```bash
./scripts/demo/show-vpn.sh
```

Expected tunnel addresses:

- POS: `10.255.0.2/24`
- Perimeter: `10.255.0.1/24`

## 5. Follow evidence logs

```bash
./scripts/demo/live-logs.sh
```

Keep this terminal open during the following tests.

## 6. Generate real blocked traffic

```bash
./lab.sh deny-test
```

Expected results:

- `PERI_FW_DROP` for direct Store-side HTTPS access.
- `INT_FW_DROP action=REJECT` for the unauthorized DMZ test port.
- Both results come from real iptables/NFLOG events.

## 7. Run an approved transaction

```bash
./lab.sh demo
```

Expected results:

- Healthy Vault and PostgreSQL dependencies.
- HTTP 200 transaction response.
- `PERI_FW_ALLOW`, `INT_FW_ALLOW`, and `CDE_TRANSACTION` events.

## 8. Show protected database records

```bash
./scripts/demo/db-table.sh
```

The output should show masked PAN, opaque token, Vault ciphertext, key version, and no CVV column.

## 9. Show Vault controls

```bash
./scripts/demo/show-vault.sh
```

The `payment-chd` key encrypts CHD. The `payment-token` key supports HMAC-derived token generation. Keys are non-exportable.

## 10. Show firewall policy

```bash
./scripts/demo/show-firewall-rules.sh
```

## 11. Run the EICAR anti-malware test

```bash
./lab.sh av-test
```

Expected result: ClamAV detects the isolated EICAR file and forwards a `CLAMAV_EICAR` event to the centralized log server. No PAN or CVV is submitted to ClamAV.

## 12. Show time-source validation

```bash
./lab.sh time
```

Chrony validates the lab NTP source in monitor-only mode. Containers inherit the Docker host clock and are not granted permission to change it.
