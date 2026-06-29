FROM alpine:3.22

RUN apk add --no-cache \
    chrony \
    dnsmasq \
    iproute2 \
    iptables \
    procps \
    rsyslog

COPY scripts/lib.sh scripts/start-log-server.sh /usr/local/lib/lab/
RUN chmod 0755 /usr/local/lib/lab/*.sh

CMD ["/usr/local/lib/lab/start-log-server.sh"]
