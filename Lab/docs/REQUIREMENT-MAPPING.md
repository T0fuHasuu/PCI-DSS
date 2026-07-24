# PCI DSS v4.0.1 Project Requirement Mapping

Status vocabulary:

- **Lab implemented:** directly enforced and observable in this repository.
- **Partial lab demonstration:** part of the control exists, but the complete
  technical or organizational requirement is not proven.
- **Referenced evidence:** evidence exists in another authorized workspace and
  is not bundled here.
- **Not demonstrated:** no defensible evidence in this lab.
- **N/A to lab function:** the condition does not occur in this lab; this does
  not automatically make it N/A for a real organization.

## Phase 1 — scope reduction and account-data protection

| Requirement | Status | Repository treatment / remaining boundary |
|---|---|---|
| 1.2.3 | Lab implemented | Report diagrams, scope register, Compose networks, and approved matrix must remain synchronized |
| 1.2.4 | Lab implemented | Browser/POS-to-storage data flow and cryptographic stages are documented |
| 1.2.5 | Lab implemented | Approved services, protocols, ports, purposes, and owners are in `NETWORK-MATRIX.md` |
| 1.2.6 | Partial lab demonstration | Insecure DNS/NTP/UDP-syslog are isolated and justified; production authentication/integrity is not implemented |
| 1.2.8 | Partial lab demonstration | Config and secret mounts are read-only and no keys are shipped; Windows host ACL/administrator governance is external |
| 1.3.1 | Lab implemented | CDE-side host firewalls accept only documented sources and ports |
| 1.3.2 | Lab implemented | CDE egress uses default drop with only Vault, DB, DNS, NTP, and logging flows as applicable |
| 1.4.1 | Lab implemented | Perimeter and internal network security controls separate trust zones |
| 1.4.2 | Lab implemented | Stateful allow rules and default-deny policies enforce the structured route |
| 1.4.4 | Lab implemented | No direct untrusted route to Vault/PostgreSQL; dashboard is host-loopback only |
| 1.4.5 | Partial lab demonstration | Internal IPs are not externally published; the evidence UI intentionally displays architecture detail |
| 1.5.1 | Partial lab demonstration | Dual-homed demo controller is default-drop and flow-limited, but it is classified as CDE rather than excluded |
| 2.2.1–2.2.6 | Partial lab demonstration | Repository hardening baseline, minimal packages/services, explicit versions, restricted ports, and security parameters |
| 2.2.7 | N/A to lab function / host external | No container remote-admin service is exposed; Docker host administration is outside this repository |
| 3.2.1 | Partial lab demonstration | Data model minimizes CHD, but quarterly retention review and secure-disposal workflow are organizational |
| 3.3.1 | Lab implemented | CVV is cleared after simulated authorization and no CVV/CVC/security-code column exists |
| 3.3.2 | N/A to lab function | SAD is never persisted before authorization |
| 3.4.1 | Lab implemented | PAN display and database field are masked to last four digits |
| 3.4.2 | N/A to lab function | No remote-access technology exposes unmasked PAN; organizational remote access remains external |
| 3.5.1 | Lab implemented | Stored PAN is represented by Vault ciphertext, masked PAN, and an HMAC-derived token |
| 3.6.1 / 3.7.1 / 3.7.2 / 3.7.5 / 3.7.7 | Partial lab implementation | Vault keys are generated internally, non-exportable, access-controlled, and auto-rotated for CHD encryption; full lifecycle procedures are organizational |
| 3.7.6 | Not demonstrated | Single-node bootstrap does not implement dual control/split knowledge for manual cleartext key operations |
| 4.2.1 | Lab implemented | WireGuard, TLS 1.2, mTLS, CA/hostname checks, and service identity restrictions protect account-data paths |
| 4.2.2 | N/A to lab workflow / policy external | The lab contains no email/SMS/chat path; an organizational prohibition still requires policy and user controls |

## Phase 2 — supporting technical controls

| Requirement | Status | Repository treatment / remaining boundary |
|---|---|---|
| 5.2.1 / 5.2.2 | Partial lab demonstration | Separate ClamAV scanner covers repository files and supports EICAR detection; not every runtime endpoint is actively protected |
| 5.3.1 | Partial lab implementation | FreshClam attempts updates every 12 hours and records degraded offline fallback |
| 5.3.2 | Partial lab implementation | Scheduled daily and on-demand scans; no real-time protection |
| 5.3.3 | Not demonstrated | Docker lab does not implement removable-media insertion scanning |
| 5.3.4 | Partial lab implementation | ClamAV events are centralized; formal retention and review are not implemented |
| 5.3.5 | Partial lab demonstration | No end-user disable interface; Docker administrators can still alter/stop the service |
| 5.4.1 | Not demonstrated | No automated anti-phishing control is bundled |
| 6.2.3 / 6.2.4 | Referenced evidence | Code review, SAST/SCA, and release-gate evidence remains external |
| 6.4.1 | Partial lab implementation + referenced scan | Nginx method/path/body/rate controls and application validation exist; ZAP/WAF evidence is external |
| 6.4.3 | Partial lab implementation + referenced evidence | Local scripts only, CSP, no third-party JavaScript; inventory/integrity evidence remains external |
| 6.5.3–6.5.6 | Referenced or N/A to runtime | Environment separation, roles, test-data policy, and release cleanup require SDLC evidence outside this runtime lab |

## Phase 3 — referenced access control and logging

| Requirement area | Status | Repository treatment / remaining boundary |
|---|---|---|
| 7.x | Referenced evidence | Docker labels or a placeholder do not prove RBAC/business need |
| 8.x | Referenced evidence / not implemented here | Unique IDs, password policy, lifecycle, lockout, and MFA require identity-system evidence |
| 8.4.1 / 8.4.2 / 8.5.1 | Not demonstrated in this lab | Do not mark N/A solely because the jumpbox is a placeholder; assess actual non-console CDE access |
| 9.x | Outside technical lab | Physical security applicability must be decided for the real assessed facilities, not from Docker |
| 10.2.1 | Partial lab implementation | Firewall, proxy, app, Vault, DB, DNS, and anti-malware events are centralized |
| 10.3.1 / 10.3.2 / 10.3.4 | Referenced / not implemented here | Container file modes alone do not prove access governance, tamper protection, or FIM |
| 10.4.1–10.4.3 | Referenced evidence | Daily/periodic review and investigation are people/process controls |
| 10.5.1 | Not implemented | Docker volume persistence is not proof of 12-month retention with three months immediately available |
| 10.6.1 / 10.6.2 | Partial lab demonstration | Common host clock and Chrony source validation support correlation; production redundancy/monitoring is external |

## Phase 4 — validation and governance

| Requirement | Status | Repository treatment / remaining boundary |
|---|---|---|
| 11.3.1 / 11.3.1.3 | Referenced evidence | Existing internal and post-change scan artifacts are outside this package |
| 11.3.2 | Requires correct external evidence | OpenVAS is not an Approved Scanning Vendor; quarterly external-scan compliance requires the applicable ASV process |
| 11.3.2.1 | Referenced evidence | Post-significant-change external scan evidence is outside this package |
| 11.4.5 | Referenced evidence | Existing multi-position Nmap segmentation validation is retained; new test scripting is deferred |
| 11.6.1 | Referenced/previously completed | Payment-page script/header change-detection evidence is outside this runtime package |
| 12.3.3 | Documented / previously completed | TLS/protocol inventory is represented in the matrix and service configs; retain the separate approved inventory evidence |
| 12.5.1 | Documented / previously completed | Scope register and Compose labels identify runtime components and classification |
| 12.10.1 / 12.10.2 | Not demonstrated | Incident-response plan and annual exercise are organizational requirements; “not in this lab” is not the same as N/A |

## Claim rule

Use **“demonstrates selected controls aligned with PCI DSS v4.0.1”**. Do not use
“PCI DSS compliant,” “fully compliant,” or “certified” for this repository.

Official source: [PCI SSC document library](https://www.pcisecuritystandards.org/document_library/).
