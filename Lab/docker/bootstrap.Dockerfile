FROM alpine:3.22.5

RUN apk add --no-cache \
    bash \
    openssl \
    wireguard-tools

WORKDIR /workspace
ENTRYPOINT ["bash"]
