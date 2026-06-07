#!/bin/sh
set -eu

# Default deny
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Basic allowed traffic
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# External -> DMZ only on HTTPS
# ext_net side is expected to be the external-facing interface
# vlan20_dmz side is expected to be the DMZ-facing interface
iptables -A FORWARD -p tcp -d 10.0.10.1 --dport 443 -j ACCEPT
iptables -A FORWARD -p tcp -d 10.0.10.2 --dport 443 -j ACCEPT