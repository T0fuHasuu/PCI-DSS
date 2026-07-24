# PCI DSS Scope Register

The register uses the PCI SSC scoping categories: **CDE**,
**connected-to/security-impacting**, and **candidate out of scope**. A component
is not out of scope merely because it is on another subnet.

## Runtime components

| Component | Category | Reason | Included in applicable PCI DSS evaluation? |
|---|---|---|---|
| Docker Desktop / Docker host | Connected-to/security-impacting | Administrators and the Docker daemon can control every CDE container, network, volume, and secret | Yes |
| Demo UI | CDE | Terminates browser TLS and transmits the synthetic PAN/CVV request | Yes |
| Demo API | CDE | Validates and transmits the account-data request | Yes |
| POS agent and POS network namespace | CDE | Processes and transmits account data through the approved payment channel | Yes |
| DMZ Nginx | CDE | Terminates payment TLS, handles the clear request in memory, and re-encrypts it upstream | Yes |
| Application | CDE | Processes PAN/CVV, requests cryptographic operations, and writes protected records | Yes |
| Vault KMS | CDE | Processes PAN/expiry and holds the cryptographic keys used to protect stored account data | Yes |
| PostgreSQL | CDE | Stores encrypted CHD and associated account data | Yes |
| Perimeter firewall | Connected-to/security-impacting | Enforces segmentation and protects the payment path | Yes |
| Internal firewall | Connected-to/security-impacting | Enforces the CDE boundary | Yes |
| DNS/NTP/log server | Connected-to/security-impacting | Provides name resolution, time support, and audit-log storage to the CDE | Yes |
| Anti-malware service | Connected-to/security-impacting | Supports malware-control evidence for in-scope code/configuration | Yes, to applicable controls |
| Jumpbox placeholder | Candidate out of scope in current state | No CDE connectivity and no implemented administration function | Validate before exclusion; a working CDE jumpbox becomes in scope |
| Department VLAN 51–56 placeholders | Candidate out of scope | Separate internal networks with no CDE or shared-service path | Validate before exclusion |

Development repositories, CI/CD systems, vulnerability scanners, administrator
workstations, identity services, and external log/SIEM platforms are not bundled
runtime services. If they can deploy to, scan, administer, authenticate, or
otherwise affect the CDE, treat them as connected-to/security-impacting in the
real assessment.

## Scope-reduction result

| View | Runtime host/components treated as in scope | Candidate exclusions | Meaning |
|---|---:|---:|---|
| Flat-network starting assumption | 20 | 0 | Docker host + 12 core services + 7 optional topology placeholders |
| Segmented target model | 13 | 7 | Core CDE/supporting systems remain in scope; isolated placeholders become candidates for exclusion |

The count is an illustrative lab metric, not a PCI DSS assessment result. The
seven candidates can be excluded only after the segmentation tests confirm they
cannot reach or affect any in-scope system. A future functional jumpbox would
move back into the connected-to/security-impacting category.

## Decision rule

A system remains in scope if any answer is **yes**:

1. Does it store, process, or transmit CHD/SAD?
2. Is it on the same network segment as such a system?
3. Can it connect to the CDE directly or through another system?
4. Can it change, secure, administer, authenticate, log, resolve names for,
   synchronize time for, deploy to, or otherwise affect the CDE?
5. Does it implement the segmentation control itself?

Only systems that answer **no** to all five questions are candidates for an
out-of-scope determination, subject to documented validation.

Reference: [PCI SSC Guidance for PCI DSS Scoping and Network Segmentation](https://www.pcisecuritystandards.org/documents/Guidance-PCI-DSS-Scoping-and-Segmentation_v1.pdf).
