# Required Report Alignment Notes

The uploaded report is broadly consistent with the architecture, but the
following statements must be corrected before final submission so the report,
diagrams, checklist, and enhanced lab do not contradict one another.

| Report topic | Required correction |
|---|---|
| CDE boundary | Include demo UI, demo API, POS agent/POS, DMZ, application, Vault, and PostgreSQL because each stores, processes, transmits, or shares a segment with account-data handling |
| Firewall category | Describe perimeter and internal firewalls as connected-to/security-impacting systems, not CDE systems unless they terminate or inspect clear CHD |
| DNS/NTP/log server | Explicitly classify it as connected-to/security-impacting because it supports CDE name resolution, time, and audit logging |
| Anti-malware service | Treat it as supporting/security-impacting and only partially implemented for the selected lab coverage |
| Department networks | Use “candidate out of scope pending segmentation validation,” not an unconditional OOS claim |
| Docker host | Add the Docker Desktop/host platform as security-impacting because control of the daemon affects every CDE container |
| Scope result | State that the lab reduces the candidate runtime set from 20 host/components to 13 in-scope and 7 candidate exclusions; label the count illustrative, not an assessment result |
| Requirement 5 | Do not mark real-time protection, removable-media scanning, user-disable prevention, or anti-phishing completed from this ClamAV container |
| Requirements 7–8 | Keep them as referenced evidence. A placeholder jumpbox is not RBAC, unique-user, password-policy, or MFA evidence |
| Requirement 10 | State centralized collection is partial; UDP syslog plus a Docker volume does not prove SIEM, FIM, daily review, or 12-month/3-month retention |
| Requirement 11.3.2 | Do not use OpenVAS alone as quarterly external ASV evidence; retain the correct applicable ASV evidence or mark it not demonstrated |
| Requirement 12.10 | Use “not demonstrated / organizational future work,” not N/A solely because incident response is outside the runtime lab |
| Overall verdict | Use “demonstrates selected controls aligned with PCI DSS v4.0.1,” never “fully compliant,” “flawless,” or “certified” |

Diagrams should use the same three visual categories as `SCOPE-REGISTER.md` and
the exact network/port identifiers from `NETWORK-MATRIX.md`.
