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

# 4. Phase 1 Data Flow: Allow encrypted transaction entry 
# Permits Retailer POS (192.168.10.20) to send TLS traffic to the DMZ Server (10.0.10.10) [cite: 5, 14, 50, 51]
iptables -A FORWARD -s 192.168.10.20 -d 10.0.10.10 -p tcp --dport 443 -j ACCEPT