FROM postgres:16.14-alpine3.23

RUN apk add --no-cache \
    chrony \
    iproute2 \
    iptables

COPY scripts/lib.sh scripts/start-db.sh /usr/local/lib/lab/
RUN chmod 0755 /usr/local/lib/lab/*.sh

ENTRYPOINT ["/usr/local/lib/lab/start-db.sh"]
CMD ["postgres"]
