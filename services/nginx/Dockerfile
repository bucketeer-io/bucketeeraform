FROM nginx:1.25-alpine
RUN apk add --no-cache gettext && rm -f /etc/nginx/conf.d/default.conf
# Bake TLS certs (backends use grpcs://, nginx needs to trust them for proxying)
RUN mkdir -p /etc/nginx/certs
COPY certs/tls.crt /etc/nginx/certs/tls.crt
COPY certs/tls.key /etc/nginx/certs/tls.key
# Copy base nginx config
COPY config/nginx/nginx.conf /etc/nginx/nginx.conf
# Copy ECS-specific config (uses resolver + variables for runtime DNS)
COPY config/nginx/bucketeer-ecs.conf /etc/nginx/conf.d/bucketeer.conf.template
COPY services/nginx/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
