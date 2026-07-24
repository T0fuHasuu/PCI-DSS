FROM nginx:1.30.3-alpine3.23

RUN apk add --no-cache curl
COPY demo-ui/nginx.conf /etc/nginx/nginx.conf
COPY demo-ui/index.html demo-ui/checkout.html demo-ui/app.js demo-ui/checkout.js demo-ui/styles.css demo-ui/checkout.css /usr/share/nginx/html/
CMD ["nginx", "-g", "daemon off;"]
