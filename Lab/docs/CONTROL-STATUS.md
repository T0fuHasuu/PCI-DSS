# Control Status Summary

| Area | Honest status | Boundary |
|---|---|---|
| Scope definition and inventory | Implemented for the lab | Explicit CDE, connected/security-impacting, and candidate-OOS register |
| Network segmentation | Implemented for the lab | Docker trust zones, two enforced firewall boundaries, default deny, optional isolated departmental topology |
| Approved transaction route | Implemented | Browser → demo UI/API → POS → perimeter → DMZ → internal firewall → app |
| Transmission protection | Implemented for selected paths | WireGuard, TLS 1.2, mTLS, certificate verification, subject restriction |
| Stored-data protection | Implemented for the lab | PAN masking, CVV non-storage, Vault encryption/HMAC, protected PostgreSQL record |
| Vault least privilege | Improved; demo exception documented | Routine role cannot decrypt; optional evidence policy grants controlled decrypt |
| Secure configuration | Partial lab implementation | Pinned base versions, no-new-privileges, minimal services, read-only config/secret mounts, host firewalls |
| Centralized logging | Partial | Source-restricted UDP syslog; not a complete SIEM, FIM, or protected reliable transport |
| Time synchronization | Demonstrated safely | Host clock inheritance plus Chrony source/offset validation; no container changes host time |
| Anti-malware | Partial | FreshClam and scheduled/on-demand repository scans; no real-time endpoint/removable-media/phishing coverage |
| Secure development and web testing | External/selected controls | CSP, route restrictions, rate limiting, dependency pinning; external ZAP/SAST/SCA evidence not bundled |
| Administrative access, RBAC, and MFA | Referenced / not implemented here | Jumpbox is a disabled placeholder, not evidence of access control |
| Vulnerability and segmentation testing | Existing external evidence | Nmap/OpenVAS evidence referenced by the report; new scripts intentionally deferred |
| Log retention, integrity, and review workflow | Not implemented | Requires separate SIEM/storage/process evidence |
| Incident response and governance | Not implemented in the runtime lab | Organizational policies, exercises, ownership, and records are required |
| Formal PCI DSS validation | Not claimed | Requires complete applicability analysis, evidence, and the appropriate assessor/SAQ/ROC process |

“Partial,” “referenced,” and “not implemented” must not be changed to
“completed” based only on the existence of a container, configuration file, or
screenshot.
