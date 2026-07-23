FROM alpine:3.22

RUN apk add --no-cache \
      chrony \
      dnsmasq \
      iproute2 \
      iptables \
      procps-ng \
      rsyslog

COPY scripts/start-log-server.sh \
     scripts/health-log-server.sh \
     /usr/local/lib/lab/

RUN chmod 0755 /usr/local/lib/lab/*.sh
