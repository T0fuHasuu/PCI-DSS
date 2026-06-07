#!/bin/sh
set -eu

iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# DMZ -> App only
iptables -A FORWARD -i eth0 -o eth1 -p tcp -d 10.100.10.10 --dport 443 -j ACCEPT

# App -> KMS only
iptables -A FORWARD -i eth1 -o eth2 -p tcp -s 10.100.10.10 -d 10.100.20.10 --dport 8443 -j ACCEPT

# App -> DB only
iptables -A FORWARD -i eth1 -o eth3 -p tcp -s 10.100.10.10 -d 10.100.30.10 --dport 5432 -j ACCEPT

# App -> Log Server
iptables -A FORWARD -i eth1 -o eth4 -p udp -d 10.200.10.10 --dport 514 -j ACCEPT

# KMS -> Log Server
iptables -A FORWARD -i eth2 -o eth4 -p udp -d 10.200.10.10 --dport 514 -j ACCEPT

# DB -> Log Server
iptables -A FORWARD -i eth3 -o eth4 -p udp -d 10.200.10.10 --dport 514 -j ACCEPT