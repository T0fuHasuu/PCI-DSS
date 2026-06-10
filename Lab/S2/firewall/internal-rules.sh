#!/bin/sh
# Flush existing rules and custom chains
iptables -F
iptables -X

# 1. Default PCI Policies: Drop everything unless explicitly allowed 
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# 2. State Tracking: Allow responses for already established connections back through
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 3. Local Loopback
iptables -A INPUT -i lo -j ACCEPT

# 4. Phase 2 Data Flow: DMZ to Application Processing [cite: 52]
# Permits DMZ Server (10.0.10.10) to forward validated data to the Application Server (10.100.10.10) [cite: 14, 32, 53, 54]
iptables -A FORWARD -s 10.0.10.10 -d 10.100.10.10 -p tcp --dport 443 -j ACCEPT

# 5. Phase 3 Data Flow: Cryptography & Tokenization [cite: 58]
# Permits exclusive bidirectional communication between the App Server (10.100.10.10) and KMS (10.100.20.10) [cite: 32, 33, 45, 60]
iptables -A FORWARD -s 10.100.10.10 -d 10.100.20.10 -p tcp --dport 8443 -j ACCEPT

# 6. Phase 4 Data Flow: Persistence [cite: 65]
# Permits the App Server (10.100.10.10) to write to the isolated PostgreSQL Database (10.100.30.10) [cite: 32, 34, 66]
iptables -A FORWARD -s 10.100.10.10 -d 10.100.30.10 -p tcp --dport 5432 -j ACCEPT

# 7. Centralized Audit & Logging Strategy [cite: 86]
# Allows components inside the internal networks to passively stream UDP telemetry logs to the Log Server (10.200.10.10) [cite: 36, 87]
iptables -A FORWARD -d 10.200.10.10 -p udp --dport 514 -j ACCEPT