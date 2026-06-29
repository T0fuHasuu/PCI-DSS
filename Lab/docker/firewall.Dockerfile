FROM alpine:3.22

RUN apk add --no-cache \
    bash \
    ca-certificates \
    chrony \
    curl \
    iproute2 \
    iptables \
    openssl \
    socat \
    wireguard-tools

COPY scripts/lib.sh \
     scripts/start-pos.sh \
     scripts/start-peri-fw.sh \
     scripts/start-int-fw.sh \
     /usr/local/lib/lab/

RUN chmod 0755 /usr/local/lib/lab/*.sh

CMD ["sleep", "infinity"]
