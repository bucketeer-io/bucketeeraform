FROM nginx:1.31.9-alpine
ARG NGINX_CONF=config/nginx/bucketeer-ecs.conf
RUN apk add --no-cache gettext && rm -f /etc/nginx/conf.d/default.conf
RUN mkdir -p /etc/nginx/certs
COPY certs/tls.crt /etc/nginx/certs/tls.crt
COPY certs/tls.key /etc/nginx/certs/tls.key
COPY config/nginx/nginx.conf /etc/nginx/nginx.conf
COPY ${NGINX_CONF} /etc/nginx/conf.d/bucketeer.conf.template
COPY services/nginx/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
