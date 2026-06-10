#!/bin/sh

echo "Initializing Firewall..."

if [ "$FW_ROLE" = "perimeter" ]; then
    echo "Applying Perimeter Firewall Rules..."
    ./perimeter-rules.sh
elif [ "$FW_ROLE" = "internal" ]; then
    echo "Applying Internal CDE Firewall Rules..."
    ./internal-rules.sh
else
    echo "ERROR: Unknown FW_ROLE '$FW_ROLE'. Dropping all traffic for safety."
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
fi

echo "Firewall rules applied successfully. Monitoring traffic..."
# Keep container alive to maintain network namespace rules
sleep infinity