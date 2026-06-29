FROM alpine:3.22

RUN apk add --no-cache \
    ca-certificates \
    chrony \
    curl \
    iproute2 \
    iptables \
    nginx \
    openssl \
    && rm -f /etc/nginx/http.d/default.conf

COPY scripts/lib.sh scripts/start-dmz.sh /usr/local/lib/lab/
RUN chmod 0755 /usr/local/lib/lab/*.sh

CMD ["nginx", "-g", "daemon off;"]
