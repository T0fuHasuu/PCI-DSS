FROM python:3.12-alpine

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apk add --no-cache \
    bind-tools \
    ca-certificates \
    chrony \
    curl \
    iproute2 \
    iptables \
    nginx \
    openssl \
    postgresql-client \
    supervisor \
    && rm -f /etc/nginx/http.d/default.conf

WORKDIR /opt/payment-app
COPY app/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ /opt/payment-app/app/
COPY scripts/lib.sh scripts/start-app.sh /usr/local/lib/lab/
RUN chmod 0755 /usr/local/lib/lab/*.sh

CMD ["/usr/local/lib/lab/start-app.sh"]
