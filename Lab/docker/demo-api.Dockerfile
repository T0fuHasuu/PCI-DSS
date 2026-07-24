FROM python:3.12.13-alpine3.22

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apk add --no-cache ca-certificates iptables nginx
WORKDIR /opt/demo-api
COPY demo-api/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY demo-api/ /opt/demo-api/
COPY demo-api/nginx.conf /etc/nginx/nginx.conf
COPY scripts/start-demo-api.sh /usr/local/lib/lab/start-demo-api.sh
RUN chmod 0755 /usr/local/lib/lab/start-demo-api.sh
CMD ["/usr/local/lib/lab/start-demo-api.sh"]
