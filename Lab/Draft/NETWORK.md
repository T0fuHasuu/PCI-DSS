# Network Architecture

## PCI-DSS VLAN Segmentation

This CDE simulation implements network segmentation to comply with PCI-DSS requirements for segregating cardholder data processing environments.

### Network Topology

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Docker Host Network                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌──────────────────────────────────────────────────────────────────┐       │
│  │                    VLAN 110 (vlan110)                             │       │
│  │               Subnet: 10.100.10.0/24                             │       │
│  │                                                                    │       │
│  │   ┌──────────────────────────────────────────────────────┐      │       │
│  │   │  Application Server (cde-app)                        │      │       │
│  │   │  IP: 10.100.10.10                                    │      │       │
│  │   │  Port: 8000 (exposed to localhost:8000)             │      │       │
│  │   │  Role: Transaction Processing, PAN Masking          │      │       │
│  │   └──────────────────────────────────────────────────────┘      │       │
│  │                                                                    │       │
│  └──────────────────────────────────────────────────────────────────┘       │
│                         ↓ HTTP/REST Calls                                    │
│                                                                               │
│  ┌──────────────────────────────────────────────────────────────────┐       │
│  │                    VLAN 120 (vlan120)                             │       │
│  │               Subnet: 10.100.20.0/24                             │       │
│  │                                                                    │       │
│  │   ┌──────────────────────────────────────────────────────┐      │       │
│  │   │  Key Management Service (cde-kms)                    │      │       │
│  │   │  IP: 10.100.20.10                                    │      │       │
│  │   │  Port: 8001 (exposed to localhost:8001)             │      │       │
│  │   │  Role: Encryption/Decryption, Key Storage           │      │       │
│  │   └──────────────────────────────────────────────────────┘      │       │
│  │                                                                    │       │
│  └──────────────────────────────────────────────────────────────────┘       │
│                         ↓ HTTP/REST Calls                                    │
│                                                                               │
│  ┌──────────────────────────────────────────────────────────────────┐       │
│  │                    VLAN 130 (vlan130)                             │       │
│  │               Subnet: 10.100.30.0/24                             │       │
│  │                                                                    │       │
│  │   ┌──────────────────────────────────────────────────────┐      │       │
│  │   │  PostgreSQL Database (cde-postgres)                  │      │       │
│  │   │  IP: 10.100.30.10                                    │      │       │
│  │   │  Port: 5432 (exposed to localhost:5432)             │      │       │
│  │   │  Role: Data Storage, Transaction Ledger             │      │       │
│  │   └──────────────────────────────────────────────────────┘      │       │
│  │                                                                    │       │
│  └──────────────────────────────────────────────────────────────────┘       │
│                                                                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Network Communication

### Allowed Connections

```
Application Server → KMS Database
   (VLAN 110)    →  (VLAN 120)
   Purpose: Encryption/Decryption of CHD
   Protocol: HTTP/REST
   Port: 8001

Application Server → PostgreSQL
   (VLAN 110)    →  (VLAN 130)
   Purpose: Data Storage/Retrieval
   Protocol: psycopg2 (PostgreSQL Protocol)
   Port: 5432

External (POS) → Application Server
   (Host)      →  (VLAN 110)
   Purpose: Transaction Processing
   Protocol: HTTP/REST
   Port: 8000
```

### Blocked Connections (Network Isolation)

```
✗ KMS ↔ Database (Direct communication not allowed)
✗ External ↔ KMS (KMS only accessible via App Server)
✗ External ↔ Database (Database only accessible via App Server)
```

## Docker Network Configuration

### Bridge Networks

Each VLAN is implemented as a Docker bridge network:

```yaml
networks:
  vlan110:
    driver: bridge
    ipam:
      config:
        - subnet: 10.100.10.0/24

  vlan120:
    driver: bridge
    ipam:
      config:
        - subnet: 10.100.20.0/24

  vlan130:
    driver: bridge
    ipam:
      config:
        - subnet: 10.100.30.0/24
```

## Service Connectivity

### Application Server Network Attachment

```yaml
services:
  app:
    networks:
      vlan110:
        ipv4_address: 10.100.10.10
    # Can access:
    # - kms (via DNS name 'kms' resolving within docker)
    # - postgres (via DNS name 'postgres' resolving within docker)
```

### KMS Network Attachment

```yaml
services:
  kms:
    networks:
      vlan120:
        ipv4_address: 10.100.20.10
    # Isolated in VLAN 120
    # Only accessible from Application Server
```

### Database Network Attachment

```yaml
services:
  postgres:
    networks:
      vlan130:
        ipv4_address: 10.100.30.10
    # Isolated in VLAN 130
    # Only accessible from Application Server
```

## Docker DNS Resolution

Docker provides automatic DNS resolution for service names:

```
# From Application Server:
- nslookup kms → resolves to 10.100.20.10
- nslookup postgres → resolves to 10.100.30.10

# From external:
- localhost:8000 → routes to 10.100.10.10:8000
- localhost:8001 → routes to 10.100.20.10:8001
- localhost:5432 → routes to 10.100.30.10:5432
```

## Port Mapping

### Internal (Container-to-Container)

```
Application Server:
  - Listens on: 0.0.0.0:8000
  - Accessible within Docker as: kms:8001, postgres:5432

KMS Service:
  - Listens on: 0.0.0.0:8001
  - Accessible within Docker as: kms:8001

PostgreSQL:
  - Listens on: 0.0.0.0:5432
  - Accessible within Docker as: postgres:5432
```

### External (Host-to-Container)

```
Application Server:
  - Host: http://localhost:8000
  - Maps to: 10.100.10.10:8000

KMS Service:
  - Host: http://localhost:8001
  - Maps to: 10.100.20.10:8001

PostgreSQL:
  - Host: localhost:5432
  - Maps to: 10.100.30.10:5432
```

## Security Benefits

### 1. Defense in Depth
Multiple network segments isolate critical components

### 2. Reduced Attack Surface
KMS and Database not directly accessible from external networks

### 3. Lateral Movement Prevention
Compromised Application Server cannot directly access KMS encryption keys (only via API)

### 4. Network Access Control (NAC)
Docker networks enforce L2/L3 isolation between VLANs

### 5. Audit and Logging
Network traffic can be monitored per VLAN

## Verification

### List Networks
```bash
docker network ls | grep vlan
```

### Inspect Network
```bash
docker network inspect cde_vlan110
```

### Test Connectivity
```bash
# From host to app
curl http://localhost:8000/health

# From app to kms (inside container)
docker-compose exec app curl http://kms:8001/health

# From app to database (inside container)
docker-compose exec app pg_isready -h postgres -U cde_user
```

## Scaling Considerations

### Multiple Application Servers
```yaml
app1:
  networks:
    vlan110:
      ipv4_address: 10.100.10.11

app2:
  networks:
    vlan110:
      ipv4_address: 10.100.10.12

# Both can access KMS and Database
```

### Load Balancing
```
┌─────────────────────────┐
│  External Load Balancer │
└────────────┬────────────┘
             │
    ┌────────┼────────┐
    ↓        ↓        ↓
  app1     app2     app3
  (VLAN 110)
    │        │        │
    └────────┼────────┘
             │
        ┌────┴──────┐
        ↓           ↓
       KMS       Database
    (VLAN 120) (VLAN 130)
```

## Network Monitoring

### Enable Bridge Logging (Optional)
```bash
docker run --net=host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  nicolaka/netshoot \
  tcpdump -i br-<network-id> port 8000 or port 8001 or port 5432
```

### View Network Statistics
```bash
docker network stats
```

## Compliance Alignment

✓ **PCI-DSS 1.2**: Firewall configuration (Docker networks)
✓ **PCI-DSS 1.3**: Network segmentation (VLAN simulation)
✓ **PCI-DSS 2.2.4**: Network access control
✓ **PCI-DSS 6.4.6**: Network segmentation

## Troubleshooting

### Services Cannot Reach Each Other

Check if services are on correct networks:
```bash
docker inspect cde-app | grep Networks
docker inspect cde-kms | grep Networks
docker inspect cde-postgres | grep Networks
```

Ensure service names are used in URLs:
```
# Correct (inside Docker)
http://kms:8001/health
http://postgres:5432

# Wrong (inside Docker)
http://10.100.20.10:8001/health
http://localhost:8001/health
```

### Cannot Access from Host

Use localhost and exposed ports:
```
# From host
curl http://localhost:8000/health

# Inside Docker
curl http://app:8000/health
```

### Network Isolation Test

Verify networks are properly isolated:
```bash
# Create a test container in vlan120
docker run --net=cde_vlan120 \
  nicolaka/netshoot \
  curl http://postgres:5432

# Should fail (no connection)
```