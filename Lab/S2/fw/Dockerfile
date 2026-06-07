FROM alpine:3.23

RUN apk add --no-cache iptables iproute2 bash

COPY entrypoint.sh /entrypoint.sh
COPY perimeter-rules.sh /perimeter-rules.sh
COPY internal-rules.sh /internal-rules.sh

RUN chmod +x /entrypoint.sh /perimeter-rules.sh /internal-rules.sh

ENTRYPOINT ["/entrypoint.sh"]