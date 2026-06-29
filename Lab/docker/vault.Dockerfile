FROM hashicorp/vault:1.21.4

USER root

RUN apk add --no-cache \
    ca-certificates \
    chrony \
    curl \
    iproute2 \
    iptables \
    jq

COPY scripts/lib.sh scripts/start-vault.sh /usr/local/lib/lab/
RUN chmod 0755 /usr/local/lib/lab/*.sh

USER root
ENTRYPOINT ["/usr/local/lib/lab/start-vault.sh"]
CMD []
