FROM alpine:3.22.5

RUN apk add --no-cache \
      bind-tools \
      ca-certificates \
      chrony \
      curl \
      iproute2 \
      iptables \
      procps-ng \
      rsyslog \
      socat \
      ulogd \
      wireguard-tools

COPY scripts/lib.sh \
     scripts/firewall-log-forwarder.sh \
     scripts/start-pos.sh \
     scripts/start-peri-fw.sh \
     scripts/start-int-fw.sh \
     /usr/local/lib/lab/

RUN chmod 0755 /usr/local/lib/lab/*.sh
