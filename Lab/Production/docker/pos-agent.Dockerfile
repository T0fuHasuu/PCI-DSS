FROM python:3.12-alpine

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apk add --no-cache ca-certificates wireguard-tools nginx
WORKDIR /opt/pos-agent

COPY pos-agent/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY pos-agent/ /opt/pos-agent/
COPY pos-agent/nginx.conf /etc/nginx/nginx.conf
COPY scripts/start-pos-agent.sh /usr/local/lib/lab/start-pos-agent.sh

RUN chmod 0755 /usr/local/lib/lab/start-pos-agent.sh

CMD ["/usr/local/lib/lab/start-pos-agent.sh"]
