FROM alpine:3.22.5

RUN apk add --no-cache \
    busybox-extras \
    ca-certificates \
    clamav-scanner \
    freshclam \
    tzdata

COPY configs/av/eicar.ndb /opt/clamav/eicar.ndb
COPY configs/av/freshclam.conf /etc/clamav/freshclam.conf
COPY scripts/clamav-control.sh /usr/local/lib/lab/clamav-control.sh
RUN chmod 0755 /usr/local/lib/lab/clamav-control.sh

ENTRYPOINT ["/usr/local/lib/lab/clamav-control.sh"]
CMD ["daemon"]
