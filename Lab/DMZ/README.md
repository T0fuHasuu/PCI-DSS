## Project Structure

```
pci-dss-lab/
├── docker-compose.yml
├── .env
├── networks/
│   └── init-networks.sh
├── firewall/
│   ├── Dockerfile
│   └── iptables.sh
├── pos/
│   └── Dockerfile
├── dmz-nginx/
│   ├── Dockerfile
│   ├── nginx.conf
│   └── ssl/
│       ├── pos.crt
│       └── pos.key
└── scripts/
    └── test.sh
```

---

## 1. `docker-compose.yml`

```yaml
services:
  firewall:
    build: ./firewall
    container_name: perimeter-firewall
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.ip_forward=1
    networks:
      store_vlan10:
        ipv4_address: 192.168.10.254
      dmz_vlan20:
        ipv4_address: 10.0.10.1

  pos:
    build: ./pos
    container_name: retailer-pos
    networks:
      store_vlan10:
        ipv4_address: 192.168.10.20
    depends_on:
      - firewall

  dmz-nginx:
    build: ./dmz-nginx
    container_name: dmz-nginx
    networks:
      dmz_vlan20:
        ipv4_address: 10.0.10.10
    depends_on:
      - firewall

networks:
  store_vlan10:
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.10.0/24

  dmz_vlan20:
    driver: bridge
    ipam:
      config:
        - subnet: 10.0.10.0/24
```

---

## 2. Firewall Container

### `firewall/Dockerfile`

```dockerfile
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y iptables iproute2 curl && rm -rf /var/lib/apt/lists/*

COPY iptables.sh /iptables.sh
RUN chmod +x /iptables.sh

CMD ["/iptables.sh"]
```

### `firewall/iptables.sh`

```bash
#!/bin/bash

sysctl -w net.ipv4.ip_forward=1

iptables -F
iptables -P FORWARD DROP

iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# POS -> NGINX only TLS (443)
iptables -A FORWARD -p tcp -s 192.168.10.20 -d 10.0.10.10 --dport 443 -j ACCEPT

echo "[+] Firewall rules applied"

tail -f /dev/null
```

---

## 3. POS Container

### `pos/Dockerfile`

```dockerfile
FROM alpine:3.19

RUN apk add --no-cache curl iproute2

CMD ["sh", "-c", "sleep infinity"]
```

---

## 4. DMZ NGINX Container

### `dmz-nginx/Dockerfile`

```dockerfile
FROM nginx:stable-alpine

RUN apk add --no-cache openssl

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY ssl/ /etc/nginx/ssl/

EXPOSE 443
```

---

### `dmz-nginx/nginx.conf`

```nginx
server {
    listen 443 ssl;
    server_name 10.0.10.10;

    ssl_certificate /etc/nginx/ssl/pos.crt;
    ssl_certificate_key /etc/nginx/ssl/pos.key;

    ssl_protocols TLSv1.2;

    ssl_ciphers 'ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256';
    ssl_prefer_server_ciphers on;

    location / {
        return 200 "DMZ NGINX OK\n";
    }
}
```

---

## 5. TLS Certificate Generation (one-time)

Run from `dmz-nginx/ssl`:

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout pos.key \
  -out pos.crt \
  -subj "/CN=10.0.10.10"
```

---

## 6. Network Initialization (optional sanity script)

### `networks/init-networks.sh`

```bash
#!/bin/bash

docker network create --subnet=192.168.10.0/24 store_vlan10
docker network create --subnet=10.0.10.0/24 dmz_vlan20
```

(Only needed if not using compose networks)

---

## 7. Test Script

### `scripts/test.sh`

```bash
#!/bin/sh

docker exec -it retailer-pos sh -c "
apk add curl &&
curl -k --tlsv1.2 https://10.0.10.10
"
```

---

## Key Behavior (what you actually get)

* POS is isolated in `192.168.10.0/24`
* DMZ is isolated in `10.0.10.0/24`
* Firewall container routes between both networks
* All traffic dropped except:

  * POS → NGINX : TCP 443 only
* NGINX enforces:

  * TLS 1.2 only
  * basic hardened cipher suite

---

If you want next step: adding **CDE zone + internal database + re-encryption hop (TLS bridging vs passthrough)** is the actual PCI-DSS realistic model.
